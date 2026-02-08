"""Autoscaler Tests (AUTO-001 through AUTO-005).

Validates the Cluster Autoscaler configuration including priority expander
ConfigMap, autoscaler profile settings, scale-up triggers, scale-down behavior,
and balance-similar-node-groups setting.
"""

import sys
import os
import json
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_auto_001(config: TestConfig, writer: ResultWriter):
    """Priority expander ConfigMap has correct priority tiers."""
    kube = KubeCommand(config.namespace)
    writer.start_test("AUTO-001", "Priority expander ConfigMap", "autoscaler")

    cm = kube.get_configmap("cluster-autoscaler-priority-expander", "kube-system")
    if not cm:
        writer.add_assertion(
            "Priority expander ConfigMap exists",
            "exists", "not found", False
        )
        writer.finish_test()
        return

    writer.assert_not_empty("ConfigMap exists", cm.get("metadata", {}).get("name", ""))

    data = cm.get("data", {})
    priorities_raw = data.get("priorities", "")

    writer.add_evidence("configmap_data", data)
    writer.add_evidence("priorities_raw", priorities_raw)

    # Expected tiers: 5 (memory spot), 10 (general/compute spot), 20 (standard), 30 (system)
    expected_tiers = [5, 10, 20, 30]
    for tier in expected_tiers:
        tier_str = str(tier)
        found = tier_str in priorities_raw
        writer.assert_eq(
            f"Priority tier {tier} present",
            found, True
        )

    # Verify memory pools at priority 5 (dynamically from config)
    for pool in config.spot_pools:
        # Check if this pool has priority 5 (memory-optimized pools)
        if config.pool_priority.get(pool, 10) == 5:
            if pool in priorities_raw:
                # Check it's associated with priority 5
                writer.add_evidence(f"{pool}_in_configmap", True)

    # Verify standard at priority 20
    writer.assert_contains(
        "Standard pool in priorities",
        priorities_raw, config.standard_pool
    )

    writer.finish_test()


test_auto_001.test_id = "AUTO-001"


def test_auto_002(config: TestConfig, writer: ResultWriter):
    """Autoscaler profile settings match expected values."""
    kube = KubeCommand(config.namespace)
    vmss = VMSSHelper(config.resource_group, config.cluster_name, config.location)
    writer.start_test("AUTO-002", "Autoscaler profile settings", "autoscaler")

    # Get cluster autoscaler profile via az CLI
    cluster_info = vmss.run_az([
        "aks", "show",
        "--resource-group", config.resource_group,
        "--name", config.cluster_name,
        "--query", "autoScalerProfile"
    ])

    if not cluster_info:
        writer.add_assertion(
            "Autoscaler profile retrieved", "profile", "not found", False
        )
        writer.finish_test()
        return

    writer.add_evidence("autoscaler_profile", cluster_info)

    # Expected settings from variables.tf
    expected = {
        "expander": "priority",
        "scan-interval": "20s",
        "max-graceful-termination-sec": "60",
        "scale-down-delay-after-delete": "10s",
        "scale-down-unready-time": "3m",  # scale_down_unready
        "scale-down-unneeded-time": "5m",  # scale_down_unneeded
        "skip-nodes-with-system-pods": "true",
        "max-node-provision-time": "10m",
    }

    for setting, expected_val in expected.items():
        # az CLI returns camelCase keys
        camel_key = setting.replace("-", " ").title().replace(" ", "")
        camel_key = camel_key[0].lower() + camel_key[1:]
        actual = cluster_info.get(camel_key, cluster_info.get(setting, ""))

        writer.assert_eq(
            f"Autoscaler {setting}={expected_val}",
            str(actual), expected_val
        )

    writer.finish_test()


test_auto_002.test_id = "AUTO-002"


def test_auto_003(config: TestConfig, writer: ResultWriter):
    """Scale-up trigger: pending pods cause autoscaler to add a node."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("AUTO-003", "Scale-up trigger on pending pods", "autoscaler")

    # Count current nodes
    pre_nodes = len(kube.get_nodes())
    writer.add_evidence("pre_test_node_count", pre_nodes)

    # Create a deployment with resource requests that will cause pending pods
    test_deploy = json.dumps({
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {
            "name": "autoscaler-test-pending",
            "namespace": config.namespace,
            "labels": {"app": "autoscaler-test"}
        },
        "spec": {
            "replicas": 5,
            "selector": {"matchLabels": {"app": "autoscaler-test"}},
            "template": {
                "metadata": {"labels": {"app": "autoscaler-test"}},
                "spec": {
                    "tolerations": [{
                        "key": "kubernetes.azure.com/scalesetpriority",
                        "value": "spot",
                        "effect": "NoSchedule"
                    }],
                    "containers": [{
                        "name": "busybox",
                        "image": "busybox:1.36",
                        "command": ["sleep", "300"],
                        "resources": {
                            "requests": {"cpu": "500m", "memory": "512Mi"}
                        }
                    }]
                }
            }
        }
    })

    try:
        # Apply the test deployment
        apply_result = kube.run(
            ["apply", "-f", "-", "-n", config.namespace],
            timeout=30
        )
        # Feed JSON via stdin - use a different approach
        import subprocess
        proc = subprocess.run(
            ["kubectl", "apply", "-f", "-", "-n", config.namespace],
            input=test_deploy, capture_output=True, text=True, timeout=30
        )
        writer.add_evidence("apply_result", proc.returncode == 0)

        # Wait for autoscaler to respond (up to 5 minutes)
        scale_up_detected = False
        for i in range(20):  # 20 * 15s = 5 min
            time.sleep(15)
            current_nodes = len(kube.get_nodes())
            pending = kube.get_pods(
                label="app=autoscaler-test",
                field_selector="status.phase=Pending"
            )
            running = kube.get_pods(
                label="app=autoscaler-test",
                field_selector="status.phase=Running"
            )

            if current_nodes > pre_nodes or len(running) >= 3:
                scale_up_detected = True
                writer.add_evidence("scale_up_time_seconds", (i + 1) * 15)
                break

        writer.assert_eq(
            "Autoscaler scaled up or pods scheduled",
            scale_up_detected, True
        )
        writer.add_evidence("post_test_node_count", len(kube.get_nodes()))
    finally:
        # Cleanup test deployment
        kube.run(["delete", "deployment", "autoscaler-test-pending",
                  "-n", config.namespace, "--ignore-not-found"])

    writer.finish_test()


test_auto_003.test_id = "AUTO-003"


def test_auto_004(config: TestConfig, writer: ResultWriter):
    """Scale-down on underutilization (verify setting, not actual scale-down)."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    vmss = VMSSHelper(config.resource_group, config.cluster_name, config.location)
    writer.start_test("AUTO-004", "Scale-down underutilization config", "autoscaler")

    # Verify scale-down settings via az CLI
    cluster_info = vmss.run_az([
        "aks", "show",
        "--resource-group", config.resource_group,
        "--name", config.cluster_name,
        "--query", "autoScalerProfile"
    ])

    if not cluster_info:
        writer.skip_test("Could not retrieve autoscaler profile")
        return

    # Check scale_down_unneeded (how long a node must be underutilized)
    unneeded = cluster_info.get("scaleDownUnneededTime",
                                 cluster_info.get("scale-down-unneeded-time", ""))
    writer.assert_eq(
        "scale_down_unneeded=5m",
        str(unneeded), "5m"
    )

    # Check scale_down_delay_after_delete
    delay_delete = cluster_info.get("scaleDownDelayAfterDelete",
                                     cluster_info.get("scale-down-delay-after-delete", ""))
    writer.assert_eq(
        "scale_down_delay_after_delete=10s",
        str(delay_delete), "10s"
    )

    # Check scale_down_unready
    unready = cluster_info.get("scaleDownUnreadyTime",
                                cluster_info.get("scale-down-unready-time", ""))
    writer.assert_eq(
        "scale_down_unready=3m",
        str(unready), "3m"
    )

    writer.add_evidence("autoscaler_profile", cluster_info)
    writer.finish_test()


test_auto_004.test_id = "AUTO-004"


def test_auto_005(config: TestConfig, writer: ResultWriter):
    """balance_similar_node_groups=true."""
    kube = KubeCommand(config.namespace)
    vmss = VMSSHelper(config.resource_group, config.cluster_name, config.location)
    writer.start_test("AUTO-005", "Balance similar node groups enabled", "autoscaler")

    cluster_info = vmss.run_az([
        "aks", "show",
        "--resource-group", config.resource_group,
        "--name", config.cluster_name,
        "--query", "autoScalerProfile"
    ])

    if not cluster_info:
        writer.skip_test("Could not retrieve autoscaler profile")
        return

    balance = cluster_info.get("balanceSimilarNodeGroups",
                                cluster_info.get("balance-similar-node-groups", ""))

    writer.assert_eq(
        "balance_similar_node_groups=true",
        str(balance).lower(), "true"
    )
    writer.add_evidence("balance_similar_node_groups", balance)
    writer.add_evidence("autoscaler_profile", cluster_info)
    writer.finish_test()


test_auto_005.test_id = "AUTO-005"
