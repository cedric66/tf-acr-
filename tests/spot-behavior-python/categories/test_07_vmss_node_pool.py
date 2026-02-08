"""VMSS Node Pool Tests (VMSS-001 through VMSS-006).

Validates Azure VMSS-level configuration for spot node pools including
priority, eviction policy, max price, zone alignment, VM SKUs, autoscale
ranges, node labels, and spot taints.
"""

import sys
import os
import json

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_vmss_001(config: TestConfig, writer: ResultWriter):
    """Spot pool VMSS config: priority=Spot, evictionPolicy=Delete, maxPrice=-1."""
    kube = KubeCommand(config.namespace)
    vmss = VMSSHelper(config.resource_group, config.cluster_name, config.location)
    writer.start_test("VMSS-001", "Spot pool VMSS config", "vmss-node-pool")

    results = {}
    for pool in config.spot_pools:
        vmss_list = vmss.get_vmss_for_pool(pool)
        if not vmss_list:
            results[pool] = {"error": "VMSS not found"}
            writer.add_assertion(f"VMSS found for {pool}", "exists", "not found", False)
            continue

        vmss_name = vmss_list[0].get("name", "")
        spot_config = vmss.get_spot_config(vmss_name)
        if not spot_config:
            results[pool] = {"error": "Could not get spot config"}
            continue

        results[pool] = {
            "vmss_name": vmss_name,
            "priority": spot_config["priority"],
            "eviction_policy": spot_config["eviction_policy"],
            "max_price": spot_config["max_price"],
        }

        writer.assert_eq(
            f"{pool} priority=Spot",
            spot_config["priority"], "Spot"
        )
        writer.assert_eq(
            f"{pool} evictionPolicy=Delete",
            spot_config["eviction_policy"], "Delete"
        )
        writer.assert_eq(
            f"{pool} maxPrice=-1",
            spot_config["max_price"], -1
        )

    writer.add_evidence("vmss_spot_configs", results)
    writer.finish_test()


test_vmss_001.test_id = "VMSS-001"


def test_vmss_002(config: TestConfig, writer: ResultWriter):
    """VMSS zone alignment matches expected config."""
    kube = KubeCommand(config.namespace)
    vmss = VMSSHelper(config.resource_group, config.cluster_name, config.location)
    writer.start_test("VMSS-002", "Zone alignment matches config", "vmss-node-pool")

    results = {}
    for pool in config.all_pools:
        expected_zones = config.pool_zones.get(pool, [])
        vmss_list = vmss.get_vmss_for_pool(pool)
        if not vmss_list:
            results[pool] = {"error": "VMSS not found", "expected": expected_zones}
            continue

        vmss_name = vmss_list[0].get("name", "")
        # Get zones from VMSS definition (not instance-level)
        vmss_detail = vmss.run_az(["vmss", "show", "-n", vmss_name, "-g", vmss.mc_rg])
        actual_zones = sorted(vmss_detail.get("zones", [])) if vmss_detail else []

        results[pool] = {
            "vmss_name": vmss_name,
            "expected_zones": expected_zones,
            "actual_zones": actual_zones,
        }
        writer.assert_eq(
            f"{pool} zones match config",
            actual_zones, sorted(expected_zones)
        )

    writer.add_evidence("zone_alignment", results)
    writer.finish_test()


test_vmss_002.test_id = "VMSS-002"


def test_vmss_003(config: TestConfig, writer: ResultWriter):
    """VM SKU matches pool_vm_size config."""
    kube = KubeCommand(config.namespace)
    vmss = VMSSHelper(config.resource_group, config.cluster_name, config.location)
    writer.start_test("VMSS-003", "VM SKU matches pool config", "vmss-node-pool")

    results = {}
    for pool, expected_sku in config.pool_vm_size.items():
        vmss_list = vmss.get_vmss_for_pool(pool)
        if not vmss_list:
            results[pool] = {"error": "VMSS not found", "expected": expected_sku}
            continue

        vmss_name = vmss_list[0].get("name", "")
        vmss_detail = vmss.run_az(["vmss", "show", "-n", vmss_name, "-g", vmss.mc_rg])
        actual_sku = ""
        if vmss_detail:
            actual_sku = vmss_detail.get("sku", {}).get("name", "")

        results[pool] = {
            "vmss_name": vmss_name,
            "expected_sku": expected_sku,
            "actual_sku": actual_sku,
        }
        writer.assert_eq(
            f"{pool} SKU={expected_sku}",
            actual_sku, expected_sku
        )

    writer.add_evidence("sku_mapping", results)
    writer.finish_test()


test_vmss_003.test_id = "VMSS-003"


def test_vmss_004(config: TestConfig, writer: ResultWriter):
    """Autoscale ranges match config (via az aks nodepool show).

    IMPORTANT: This test validates that the DEPLOYED cluster matches your .env config.
    If you deployed with Terraform using custom min/max values, you MUST set matching
    env vars in .env (e.g., POOL_MIN_spotgeneral1=0, POOL_MAX_spotgeneral1=20).
    Test failures here mean config mismatch, NOT deployment issues.
    """
    kube = KubeCommand(config.namespace)
    vmss = VMSSHelper(config.resource_group, config.cluster_name, config.location)
    writer.start_test("VMSS-004", "Autoscale ranges match config", "vmss-node-pool")

    # Build expected ranges dynamically from config
    expected_ranges = {}
    for pool in config.all_pools:
        expected_ranges[pool] = {
            "min": config.pool_min.get(pool, 0),
            "max": config.pool_max.get(pool, 20),
        }

    results = {}
    for pool, expected in expected_ranges.items():
        pool_info = vmss.run_az([
            "aks", "nodepool", "show",
            "--resource-group", config.resource_group,
            "--cluster-name", config.cluster_name,
            "--name", pool
        ])
        if not pool_info:
            results[pool] = {"error": "nodepool not found"}
            continue

        actual_min = pool_info.get("minCount")
        actual_max = pool_info.get("maxCount")
        autoscaling = pool_info.get("enableAutoScaling", False)

        results[pool] = {
            "expected_min": expected["min"],
            "expected_max": expected["max"],
            "actual_min": actual_min,
            "actual_max": actual_max,
            "autoscaling_enabled": autoscaling,
        }

        writer.assert_eq(f"{pool} autoscaling enabled", autoscaling, True)
        writer.assert_eq(f"{pool} min={expected['min']}", actual_min, expected["min"])
        writer.assert_eq(f"{pool} max={expected['max']}", actual_max, expected["max"])

    writer.add_evidence("autoscale_ranges", results)
    writer.finish_test()


test_vmss_004.test_id = "VMSS-004"


def test_vmss_005(config: TestConfig, writer: ResultWriter):
    """Node labels match expected values."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    writer.start_test("VMSS-005", "Node labels match expected values", "vmss-node-pool")

    results = {}
    # Build expected labels dynamically based on pool type
    expected_labels = {}
    for pool in config.all_pools:
        if pool == config.system_pool:
            expected_labels[pool] = {"workload-type": "standard", "priority": "system"}
        elif pool == config.standard_pool:
            expected_labels[pool] = {"workload-type": "standard", "priority": "on-demand"}
        elif pool in config.spot_pools:
            expected_labels[pool] = {"workload-type": "spot", "priority": "spot"}

    for pool, expected in expected_labels.items():
        pool_nodes = nodes.get_pool_nodes(pool)
        if not pool_nodes:
            results[pool] = {"error": "no nodes found"}
            continue

        node = pool_nodes[0]
        labels = node.get("metadata", {}).get("labels", {})

        results[pool] = {
            "expected": expected,
            "actual_workload_type": labels.get("workload-type"),
            "actual_priority": labels.get("priority"),
        }

        for label_key, label_val in expected.items():
            actual = labels.get(label_key, "")
            writer.assert_eq(
                f"{pool} label {label_key}={label_val}",
                actual, label_val
            )

        # Check Azure-managed spot label
        if pool in config.spot_pools:
            azure_priority = labels.get("kubernetes.azure.com/scalesetpriority", "")
            writer.assert_eq(
                f"{pool} azure scalesetpriority=spot",
                azure_priority, "spot"
            )

    writer.add_evidence("node_labels", results)
    writer.finish_test()


test_vmss_005.test_id = "VMSS-005"


def test_vmss_006(config: TestConfig, writer: ResultWriter):
    """All spot nodes have NoSchedule taint."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    writer.start_test("VMSS-006", "Spot nodes have NoSchedule taint", "vmss-node-pool")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    results = {}
    for node in spot_nodes:
        node_name = node["metadata"]["name"]
        taints = node.get("spec", {}).get("taints", [])
        has_spot_taint = False
        for t in taints:
            if (t.get("key") == "kubernetes.azure.com/scalesetpriority"
                    and t.get("value") == "spot"
                    and t.get("effect") == "NoSchedule"):
                has_spot_taint = True
                break

        results[node_name] = {
            "has_spot_taint": has_spot_taint,
            "taints": taints,
        }
        writer.assert_eq(
            f"{node_name} has spot NoSchedule taint",
            has_spot_taint, True
        )

    writer.add_evidence("spot_taints", results)
    writer.finish_test()


test_vmss_006.test_id = "VMSS-006"
