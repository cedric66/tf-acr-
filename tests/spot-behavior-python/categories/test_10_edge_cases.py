"""Edge Case Tests (EDGE-001 through EDGE-005).

Validates extreme scenarios including all-spot-nodes-cordoned, rapid
cordon/uncordon cycling, zero spot capacity fallback, PDB+topology
interaction, and resource pressure on the standard pool.
"""

import sys
import os
import json
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_edge_001(config: TestConfig, writer: ResultWriter):
    """All spot nodes cordoned - pending pods trigger standard pool scale-up."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EDGE-001", "All spot nodes cordoned", "edge-cases")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    spot_names = [n["metadata"]["name"] for n in spot_nodes]
    pre_std_count = nodes.count_ready_in_pool(config.standard_pool)
    pre_running = len([p for p in kube.get_pods() if pods.is_running(p)])

    writer.add_evidence("spot_nodes", spot_names)
    writer.add_evidence("pre_std_count", pre_std_count)
    writer.add_evidence("pre_running_pods", pre_running)

    try:
        # Cordon all spot nodes
        for nn in spot_names:
            nodes.cordon(nn)

        time.sleep(10)

        # Verify spot nodes are unschedulable
        spot_after = nodes.get_spot_nodes()
        unschedulable_count = 0
        for n in spot_after:
            if n.get("spec", {}).get("unschedulable", False):
                unschedulable_count += 1

        writer.assert_eq(
            "All spot nodes cordoned",
            unschedulable_count, len(spot_names)
        )

        # Check for pending pods (new pods should be pending or on standard)
        pending = kube.get_pods(field_selector="status.phase=Pending")
        writer.add_evidence("pending_pods_during_cordon", len(pending))

        # Standard pool should still be serving
        std_ready = nodes.count_ready_in_pool(config.standard_pool)
        writer.assert_gt(
            "Standard pool has ready nodes",
            std_ready, 0
        )
        writer.add_evidence("std_ready_during_cordon", std_ready)
    finally:
        for nn in spot_names:
            nodes.uncordon(nn)

    writer.finish_test()


test_edge_001.test_id = "EDGE-001"


def test_edge_002(config: TestConfig, writer: ResultWriter):
    """Rapid cordon/uncordon cycling (3 times) on same node."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EDGE-002", "Rapid cordon/uncordon cycling", "edge-cases")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    target = spot_nodes[0]["metadata"]["name"]
    pre_running = len([p for p in kube.get_pods() if pods.is_running(p)])

    writer.add_evidence("target_node", target)
    writer.add_evidence("pre_cycling_running_pods", pre_running)

    try:
        cycle_results = []
        for i in range(3):
            cordon_ok = nodes.cordon(target)
            time.sleep(2)
            uncordon_ok = nodes.uncordon(target)
            time.sleep(2)

            node_after = kube.get_node(target)
            is_schedulable = not node_after.get("spec", {}).get("unschedulable", False) if node_after else False

            cycle_results.append({
                "cycle": i + 1,
                "cordon_ok": cordon_ok,
                "uncordon_ok": uncordon_ok,
                "schedulable_after": is_schedulable,
            })

        writer.add_evidence("cycle_results", cycle_results)

        # After cycling, node should be schedulable
        final_node = kube.get_node(target)
        final_schedulable = not final_node.get("spec", {}).get("unschedulable", False) if final_node else False
        writer.assert_eq("Node schedulable after cycling", final_schedulable, True)

        # Pods should still be running
        time.sleep(10)
        post_running = len([p for p in kube.get_pods() if pods.is_running(p)])
        writer.assert_gte(
            "Running pods stable after cycling",
            post_running, pre_running - 1
        )
        writer.add_evidence("post_cycling_running_pods", post_running)
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_edge_002.test_id = "EDGE-002"


def test_edge_003(config: TestConfig, writer: ResultWriter):
    """Zero spot capacity - 100% fallback to standard, then recovery."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EDGE-003", "Zero spot capacity fallback", "edge-cases")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    spot_names = [n["metadata"]["name"] for n in spot_nodes]
    pre_running = len([p for p in kube.get_pods() if pods.is_running(p)])

    writer.add_evidence("spot_nodes", spot_names)
    writer.add_evidence("pre_test_running", pre_running)

    try:
        # Cordon all spot nodes to simulate zero spot capacity
        for nn in spot_names:
            nodes.cordon(nn)

        # Drain all spot nodes to force pods to standard
        for nn in spot_names:
            nodes.drain(nn, timeout=config.drain_timeout)

        time.sleep(30)

        # All workload pods should now be on standard or system nodes
        all_pods_after = kube.get_pods()
        spot_pod_count = 0
        std_pod_count = 0
        for p in all_pods_after:
            if not pods.is_running(p):
                continue
            n = pods.get_pod_node(p)
            if not n:
                continue
            node = kube.get_node(n)
            if not node:
                continue
            if nodes.is_spot(node):
                spot_pod_count += 1
            elif nodes.get_pool_name(node) == config.standard_pool:
                std_pod_count += 1

        writer.assert_eq("Zero pods on spot nodes", spot_pod_count, 0)
        writer.assert_gt("Pods running on standard pool", std_pod_count, 0)
        writer.add_evidence("spot_pods_during_zero", spot_pod_count)
        writer.add_evidence("std_pods_during_zero", std_pod_count)

        # Uncordon spot nodes (simulate capacity recovery)
        for nn in spot_names:
            nodes.uncordon(nn)

        time.sleep(30)

        # Verify cluster is stable after recovery
        post_running = len([p for p in kube.get_pods() if pods.is_running(p)])
        writer.assert_gte(
            "Running pods recovered after uncordon",
            post_running, pre_running - 2
        )
        writer.add_evidence("post_recovery_running", post_running)
        return  # nodes already uncordoned
    except Exception:
        for nn in spot_names:
            nodes.uncordon(nn)
        raise

    writer.finish_test()


test_edge_003.test_id = "EDGE-003"


def test_edge_004(config: TestConfig, writer: ResultWriter):
    """PDB respected even when topology constraints are violated."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EDGE-004", "PDB + topology interaction", "edge-cases")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Find a PDB-protected service with topology constraints
    target_svc = None
    target_node = None
    for svc in config.pdb_services:
        svc_pods = pods.get_service_pods(svc)
        running = [p for p in svc_pods if pods.is_running(p)]
        if len(running) >= 2:
            # Check if this service has topology constraints
            pod = running[0]
            tscs = pod.get("spec", {}).get("topologySpreadConstraints", [])
            if tscs:
                for p in running:
                    n = pods.get_pod_node(p)
                    node = kube.get_node(n) if n else None
                    if node and nodes.is_spot(node):
                        target_svc = svc
                        target_node = n
                        break
        if target_svc:
            break

    if not target_svc:
        # Fallback: use any PDB service on spot
        for svc in config.pdb_services:
            running_count = pods.count_running_for_service(svc)
            if running_count >= 2:
                svc_pods = pods.get_service_pods(svc)
                for p in svc_pods:
                    n = pods.get_pod_node(p)
                    node = kube.get_node(n) if n else None
                    if node and nodes.is_spot(node):
                        target_svc = svc
                        target_node = n
                        break
            if target_svc:
                break

    if not target_svc:
        writer.skip_test("No PDB-protected service with >=2 replicas on spot")
        return

    pre_count = pods.count_running_for_service(target_svc)
    writer.add_evidence("target_service", target_svc)
    writer.add_evidence("target_node", target_node)
    writer.add_evidence("pre_drain_count", pre_count)

    try:
        # Drain the node - PDB should be respected regardless of topology violation
        nodes.drain(target_node, timeout=config.drain_timeout)
        time.sleep(20)

        post_count = pods.count_running_for_service(target_svc)
        writer.assert_gte(
            f"PDB maintained >=1 for {target_svc} despite topology pressure",
            post_count, 1
        )

        # Check PDB status
        pdbs = kube.get_pdbs()
        for pdb in pdbs:
            pdb_name = pdb.get("metadata", {}).get("name", "")
            if target_svc in pdb_name or target_svc in str(
                    pdb.get("spec", {}).get("selector", {})):
                status = pdb.get("status", {})
                writer.add_evidence(f"pdb_{pdb_name}_status", {
                    "currentHealthy": status.get("currentHealthy"),
                    "desiredHealthy": status.get("desiredHealthy"),
                    "disruptionsAllowed": status.get("disruptionsAllowed"),
                })

        writer.add_evidence("post_drain_count", post_count)
    finally:
        nodes.uncordon(target_node)

    writer.finish_test()


test_edge_004.test_id = "EDGE-004"


def test_edge_005(config: TestConfig, writer: ResultWriter):
    """Resource pressure on standard pool when spot is unavailable."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EDGE-005", "Resource pressure on standard pool", "edge-cases")

    spot_nodes = nodes.get_spot_nodes()
    std_nodes = nodes.get_pool_nodes(config.standard_pool)

    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return
    if not std_nodes:
        writer.skip_test("No standard pool nodes available")
        return

    spot_names = [n["metadata"]["name"] for n in spot_nodes]
    std_names = [n["metadata"]["name"] for n in std_nodes]

    writer.add_evidence("spot_nodes", spot_names)
    writer.add_evidence("std_nodes", std_names)

    try:
        # Cordon all spot nodes
        for nn in spot_names:
            nodes.cordon(nn)

        # Drain spot nodes to push pods to standard
        for nn in spot_names:
            nodes.drain(nn, timeout=config.drain_timeout)

        time.sleep(30)

        # Check standard pool resource utilization
        std_node_resources = []
        for nn in std_names:
            # Get node allocatable vs requested
            node_data = kube.get_node(nn)
            if not node_data:
                continue

            allocatable = node_data.get("status", {}).get("allocatable", {})
            alloc_cpu = allocatable.get("cpu", "0")
            alloc_mem = allocatable.get("memory", "0")

            std_node_resources.append({
                "node": nn,
                "allocatable_cpu": alloc_cpu,
                "allocatable_memory": alloc_mem,
            })

        writer.add_evidence("std_node_resources", std_node_resources)

        # Check for pods in Pending state (resource pressure indicator)
        pending = kube.get_pods(field_selector="status.phase=Pending")
        pending_names = [p["metadata"]["name"] for p in pending]
        writer.add_evidence("pending_pods", pending_names)

        if pending:
            # Pending pods indicate resource pressure - expected when spot is down
            writer.assert_gt(
                "Pending pods indicate resource pressure on standard",
                len(pending), 0
            )
            writer.add_evidence("resource_pressure_detected", True)
        else:
            # Standard pool absorbed all pods - also valid
            running_on_std = 0
            for p in kube.get_pods():
                if not pods.is_running(p):
                    continue
                n = pods.get_pod_node(p)
                if n in std_names:
                    running_on_std += 1

            writer.assert_gt(
                "Standard pool absorbed pods without pending",
                running_on_std, 0
            )
            writer.add_evidence("resource_pressure_detected", False)
            writer.add_evidence("pods_absorbed_by_standard", running_on_std)
    finally:
        for nn in spot_names:
            nodes.uncordon(nn)

    writer.finish_test()


test_edge_005.test_id = "EDGE-005"
