"""Sticky Fallback Tests (STICK-001 through STICK-005).

Validates the "sticky fallback" behavior where pods land on standard on-demand
nodes after spot eviction and do not automatically migrate back. Checks for
Descheduler configuration and manual spot-return simulation.
"""

import sys
import os
import json
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_stick_001(config: TestConfig, writer: ResultWriter):
    """Fallback to standard pool after spot pool drain."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("STICK-001", "Fallback to standard pool", "sticky-fallback")

    # Pick one spot pool and drain all its nodes
    target_pool = config.spot_pools[0]
    pool_nodes = nodes.get_pool_nodes(target_pool)

    if not pool_nodes:
        writer.skip_test(f"No nodes in pool {target_pool}")
        return

    node_names = [n["metadata"]["name"] for n in pool_nodes]
    writer.add_evidence("target_pool", target_pool)
    writer.add_evidence("pool_nodes", node_names)

    # Count pods on standard before drain
    pre_std_pods = 0
    all_pods = kube.get_pods()
    for p in all_pods:
        if not pods.is_running(p):
            continue
        n = pods.get_pod_node(p)
        if n:
            node = kube.get_node(n)
            if node and nodes.get_pool_name(node) == config.standard_pool:
                pre_std_pods += 1

    writer.add_evidence("pre_drain_standard_pods", pre_std_pods)

    try:
        for nn in node_names:
            nodes.drain(nn, timeout=config.drain_timeout)

        time.sleep(30)

        # Count pods on standard after drain
        post_std_pods = 0
        all_pods_after = kube.get_pods()
        for p in all_pods_after:
            if not pods.is_running(p):
                continue
            n = pods.get_pod_node(p)
            if n:
                node = kube.get_node(n)
                if node and nodes.get_pool_name(node) == config.standard_pool:
                    post_std_pods += 1

        writer.add_evidence("post_drain_standard_pods", post_std_pods)
        writer.assert_gt(
            "Pods fell back to standard pool",
            post_std_pods, pre_std_pods
        )
    finally:
        for nn in node_names:
            nodes.uncordon(nn)

    writer.finish_test()


test_stick_001.test_id = "STICK-001"


def test_stick_002(config: TestConfig, writer: ResultWriter):
    """Pods stay on standard pool after fallback (sticky behavior)."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("STICK-002", "Pods stay on standard (sticky fallback)", "sticky-fallback")

    # Drain one spot pool to force pods to standard
    target_pool = config.spot_pools[0]
    pool_nodes = nodes.get_pool_nodes(target_pool)

    if not pool_nodes:
        writer.skip_test(f"No nodes in pool {target_pool}")
        return

    node_names = [n["metadata"]["name"] for n in pool_nodes]

    try:
        for nn in node_names:
            nodes.drain(nn, timeout=config.drain_timeout)

        time.sleep(15)

        # Count pods on standard immediately after drain
        std_pods_after_drain = 0
        for p in kube.get_pods():
            if not pods.is_running(p):
                continue
            n = pods.get_pod_node(p)
            if n:
                node = kube.get_node(n)
                if node and nodes.get_pool_name(node) == config.standard_pool:
                    std_pods_after_drain += 1

        writer.add_evidence("std_pods_after_drain", std_pods_after_drain)

        # Uncordon spot nodes (simulate spot capacity recovery)
        for nn in node_names:
            nodes.uncordon(nn)

        # Wait 60 seconds - pods should NOT move back automatically
        time.sleep(60)

        std_pods_after_wait = 0
        for p in kube.get_pods():
            if not pods.is_running(p):
                continue
            n = pods.get_pod_node(p)
            if n:
                node = kube.get_node(n)
                if node and nodes.get_pool_name(node) == config.standard_pool:
                    std_pods_after_wait += 1

        writer.add_evidence("std_pods_after_60s_wait", std_pods_after_wait)

        # Pods should still be on standard (sticky)
        writer.assert_gte(
            "Pods remain on standard after spot recovery (sticky)",
            std_pods_after_wait, std_pods_after_drain
        )
        return  # nodes already uncordoned above
    except Exception:
        # Ensure cleanup on error
        for nn in node_names:
            nodes.uncordon(nn)
        raise

    writer.finish_test()


test_stick_002.test_id = "STICK-002"


def test_stick_003(config: TestConfig, writer: ResultWriter):
    """Descheduler deployment exists with RemovePodsViolatingNodeAffinity."""
    kube = KubeCommand(config.namespace)
    writer.start_test("STICK-003", "Descheduler configured", "sticky-fallback")

    # Check for descheduler deployment in common namespaces
    descheduler_found = False
    descheduler_ns = None
    descheduler_details = {}

    for ns in ["kube-system", "descheduler", "default"]:
        deploys = kube.run_json(["get", "deployments", "-n", ns])
        items = deploys.get("items", []) if deploys else []
        for d in items:
            name = d.get("metadata", {}).get("name", "")
            if "descheduler" in name.lower():
                descheduler_found = True
                descheduler_ns = ns
                descheduler_details["deployment"] = name
                descheduler_details["namespace"] = ns
                break
        if descheduler_found:
            break

    # Also check CronJobs (descheduler is often deployed as a CronJob)
    if not descheduler_found:
        for ns in ["kube-system", "descheduler", "default"]:
            crons = kube.run_json(["get", "cronjobs", "-n", ns])
            items = crons.get("items", []) if crons else []
            for c in items:
                name = c.get("metadata", {}).get("name", "")
                if "descheduler" in name.lower():
                    descheduler_found = True
                    descheduler_ns = ns
                    descheduler_details["cronjob"] = name
                    descheduler_details["namespace"] = ns
                    break
            if descheduler_found:
                break

    writer.assert_eq("Descheduler deployment/cronjob exists", descheduler_found, True)

    # Check for RemovePodsViolatingNodeAffinity strategy in configmap
    if descheduler_ns:
        cms = kube.run_json(["get", "configmaps", "-n", descheduler_ns])
        cm_items = cms.get("items", []) if cms else []
        strategy_found = False
        for cm in cm_items:
            cm_name = cm.get("metadata", {}).get("name", "")
            if "descheduler" in cm_name.lower():
                data = cm.get("data", {})
                for key, val in data.items():
                    if "RemovePodsViolatingNodeAffinity" in str(val):
                        strategy_found = True
                        descheduler_details["strategy_configmap"] = cm_name
                        break
            if strategy_found:
                break

        writer.assert_eq(
            "RemovePodsViolatingNodeAffinity strategy configured",
            strategy_found, True
        )
        writer.add_evidence("strategy_found", strategy_found)

    writer.add_evidence("descheduler_details", descheduler_details)
    writer.finish_test()


test_stick_003.test_id = "STICK-003"


def test_stick_004(config: TestConfig, writer: ResultWriter):
    """Descheduler interval is 5 minutes."""
    kube = KubeCommand(config.namespace)
    writer.start_test("STICK-004", "Descheduler interval 5m", "sticky-fallback")

    interval_found = False
    interval_value = None

    for ns in ["kube-system", "descheduler", "default"]:
        # Check deployment args for --descheduling-interval
        deploys = kube.run_json(["get", "deployments", "-n", ns])
        items = deploys.get("items", []) if deploys else []
        for d in items:
            name = d.get("metadata", {}).get("name", "")
            if "descheduler" not in name.lower():
                continue
            containers = d.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])
            for c in containers:
                args = c.get("args", []) + c.get("command", [])
                for i, arg in enumerate(args):
                    if "--descheduling-interval" in arg:
                        if "=" in arg:
                            interval_value = arg.split("=")[1]
                        elif i + 1 < len(args):
                            interval_value = args[i + 1]
                        interval_found = True
                        break

        # Also check CronJob schedule
        if not interval_found:
            crons = kube.run_json(["get", "cronjobs", "-n", ns])
            citems = crons.get("items", []) if crons else []
            for c in citems:
                cname = c.get("metadata", {}).get("name", "")
                if "descheduler" in cname.lower():
                    schedule = c.get("spec", {}).get("schedule", "")
                    interval_value = schedule
                    interval_found = True
                    break

        if interval_found:
            break

    writer.add_evidence("interval_found", interval_found)
    writer.add_evidence("interval_value", interval_value)

    if interval_found and interval_value:
        is_5m = interval_value in ("5m", "5m0s", "300s", "*/5 * * * *")
        writer.assert_eq(
            "Descheduler interval is 5 minutes",
            is_5m, True
        )
    else:
        writer.add_assertion(
            "Descheduler interval found", "interval present", "not found", False
        )

    writer.finish_test()


test_stick_004.test_id = "STICK-004"


def test_stick_005(config: TestConfig, writer: ResultWriter):
    """Manual spot return simulation - new pods prefer spot nodes."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("STICK-005", "Manual spot return simulation", "sticky-fallback")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Verify spot nodes are ready (uncordoned)
    ready_spot = [n for n in spot_nodes if nodes.is_ready(n)]
    if not ready_spot:
        writer.skip_test("No ready spot nodes available")
        return

    writer.add_evidence("ready_spot_nodes", len(ready_spot))

    # Check that stateless services with spot affinity preference land on spot
    svc = config.stateless_services[0]
    spot_pods = pods.get_pods_on_spot(svc)
    total_pods = pods.get_service_pods(svc)

    writer.add_evidence("service", svc)
    writer.add_evidence("total_pods", len(total_pods))
    writer.add_evidence("pods_on_spot", len(spot_pods))

    # With spot nodes available and spot affinity weight=100, new/existing pods should prefer spot
    if total_pods:
        spot_pct = len(spot_pods) / len(total_pods) * 100
        writer.assert_gt(
            "Pods prefer spot nodes when available",
            len(spot_pods), 0
        )
        writer.add_evidence("spot_percentage", round(spot_pct, 1))
    else:
        writer.add_assertion(f"Pods exist for {svc}", ">0", 0, False)

    writer.finish_test()


test_stick_005.test_id = "STICK-005"
