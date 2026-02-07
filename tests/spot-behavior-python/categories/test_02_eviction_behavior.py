"""Eviction Behavior Tests (EVICT-001 through EVICT-010).

Validates pod rescheduling after node drains, graceful termination settings,
preStop hooks, PDB enforcement during eviction, and multi-node drain scenarios.
Destructive tests use try/finally to ensure nodes are uncordoned.
"""

import sys
import os
import json
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_evict_001(config: TestConfig, writer: ResultWriter):
    """Single node drain reschedules pods."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-001", "Single node drain reschedules pods", "eviction-behavior")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    target = spot_nodes[0]["metadata"]["name"]
    target_pool = nodes.get_pool_name(spot_nodes[0])

    # Count pods on the target node before drain
    all_pods = kube.get_pods()
    pods_on_target = [p for p in all_pods if pods.get_pod_node(p) == target and pods.is_running(p)]
    pre_drain_count = len(pods_on_target)
    pod_names_before = [p["metadata"]["name"] for p in pods_on_target]

    writer.add_evidence("target_node", target)
    writer.add_evidence("target_pool", target_pool)
    writer.add_evidence("pods_on_target_before_drain", pod_names_before)

    try:
        drain_ok = nodes.drain(target, timeout=config.drain_timeout)
        writer.assert_eq("Drain completed successfully", drain_ok, True)

        # Wait for pods to reschedule
        time.sleep(30)

        # Check that pods from target node are now running elsewhere
        rescheduled_count = 0
        all_pods_after = kube.get_pods()
        running_after = [p for p in all_pods_after if pods.is_running(p)]

        # Count how many pods are now on spot nodes (excluding drained node)
        on_other_spot = 0
        for p in running_after:
            n = pods.get_pod_node(p)
            if n and n != target:
                node_obj = kube.get_node(n)
                if node_obj and nodes.is_spot(node_obj):
                    on_other_spot += 1

        writer.assert_gt(
            "Pods rescheduled to other spot nodes",
            on_other_spot, 0
        )
        writer.add_evidence("running_pods_on_other_spot_after", on_other_spot)
        writer.add_evidence("total_running_after", len(running_after))
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_evict_001.test_id = "EVICT-001"


def test_evict_002(config: TestConfig, writer: ResultWriter):
    """Graceful termination period set to 35s on pods."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-002", "Graceful termination period configured", "eviction-behavior")

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        grace = pod.get("spec", {}).get("terminationGracePeriodSeconds", 30)
        results[svc] = {"terminationGracePeriodSeconds": grace}
        writer.assert_eq(
            f"{svc} terminationGracePeriodSeconds={config.termination_grace_period}",
            grace, config.termination_grace_period
        )

    writer.add_evidence("termination_periods", results)
    writer.finish_test()


test_evict_002.test_id = "EVICT-002"


def test_evict_003(config: TestConfig, writer: ResultWriter):
    """PreStop hook configured on stateless service pods."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-003", "PreStop hook configured", "eviction-behavior")

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        containers = pod.get("spec", {}).get("containers", [])
        has_prestop = False
        prestop_details = None
        for c in containers:
            lifecycle = c.get("lifecycle", {})
            prestop = lifecycle.get("preStop")
            if prestop:
                has_prestop = True
                prestop_details = prestop
                break

        results[svc] = {"has_prestop": has_prestop, "prestop": prestop_details}
        writer.assert_eq(
            f"{svc} has preStop lifecycle hook",
            has_prestop, True
        )

    writer.add_evidence("prestop_hooks", results)
    writer.finish_test()


test_evict_003.test_id = "EVICT-003"


def test_evict_004(config: TestConfig, writer: ResultWriter):
    """Multi-node drain from different pools reschedules pods."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-004", "Multi-node drain from different pools", "eviction-behavior")

    spot_nodes = nodes.get_spot_nodes()
    if len(spot_nodes) < 2:
        writer.skip_test(f"Need at least 2 spot nodes, found {len(spot_nodes)}")
        return

    # Select 2 nodes from different pools
    seen_pools = set()
    targets = []
    for n in spot_nodes:
        pool = nodes.get_pool_name(n)
        if pool not in seen_pools:
            seen_pools.add(pool)
            targets.append(n["metadata"]["name"])
            if len(targets) == 2:
                break

    if len(targets) < 2:
        # If only 1 pool, pick 2 nodes from it
        targets = [spot_nodes[0]["metadata"]["name"], spot_nodes[1]["metadata"]["name"]]

    pre_running = len([p for p in kube.get_pods() if pods.is_running(p)])
    writer.add_evidence("targets", targets)
    writer.add_evidence("pre_drain_running_pods", pre_running)

    try:
        for t in targets:
            drain_ok = nodes.drain(t, timeout=config.drain_timeout)
            writer.add_evidence(f"drain_{t}", drain_ok)

        # Wait for rescheduling
        time.sleep(45)

        post_running = len([p for p in kube.get_pods() if pods.is_running(p)])
        writer.assert_gte(
            "Running pod count recovers after multi-drain",
            post_running, pre_running - 2  # allow small margin
        )
        writer.add_evidence("post_drain_running_pods", post_running)
    finally:
        for t in targets:
            nodes.uncordon(t)

    writer.finish_test()


test_evict_004.test_id = "EVICT-004"


def test_evict_005(config: TestConfig, writer: ResultWriter):
    """Pod eviction respects PDBs."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-005", "Pod eviction respects PDBs", "eviction-behavior")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Find a spot node that has pods from a PDB-protected service
    target = None
    target_svc = None
    for n in spot_nodes:
        node_name = n["metadata"]["name"]
        for svc in config.pdb_services:
            svc_pods = pods.get_service_pods(svc)
            for p in svc_pods:
                if pods.get_pod_node(p) == node_name:
                    target = node_name
                    target_svc = svc
                    break
            if target:
                break
        if target:
            break

    if not target:
        writer.skip_test("No PDB-protected pods found on spot nodes")
        return

    pre_count = pods.count_running_for_service(target_svc)
    pdbs = kube.get_pdbs()
    pdb_min = None
    for pdb in pdbs:
        spec = pdb.get("spec", {})
        selector_labels = spec.get("selector", {}).get("matchLabels", {})
        if target_svc in str(selector_labels):
            pdb_min = spec.get("minAvailable", 0)
            break

    writer.add_evidence("target_node", target)
    writer.add_evidence("target_service", target_svc)
    writer.add_evidence("pre_drain_count", pre_count)
    writer.add_evidence("pdb_minAvailable", pdb_min)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(15)

        post_count = pods.count_running_for_service(target_svc)
        min_expected = pdb_min if isinstance(pdb_min, int) else 1
        writer.assert_gte(
            f"PDB minAvailable={min_expected} maintained during drain",
            post_count, min_expected
        )
        writer.add_evidence("post_drain_count", post_count)
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_evict_005.test_id = "EVICT-005"


def test_evict_006(config: TestConfig, writer: ResultWriter):
    """Service endpoint removal before termination."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-006", "Service endpoint removal before termination", "eviction-behavior")

    # Verify that pods have readinessProbe or readinessGates
    # which ensure endpoint removal before container stop
    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        containers = pod.get("spec", {}).get("containers", [])
        has_readiness_probe = False
        for c in containers:
            if c.get("readinessProbe"):
                has_readiness_probe = True
                break

        # Also check if there's a preStop hook for connection draining
        has_prestop = False
        for c in containers:
            lifecycle = c.get("lifecycle", {})
            if lifecycle.get("preStop"):
                has_prestop = True
                break

        results[svc] = {
            "has_readiness_probe": has_readiness_probe,
            "has_prestop": has_prestop,
        }
        writer.assert_eq(
            f"{svc} has readiness probe or preStop for endpoint removal",
            has_readiness_probe or has_prestop, True
        )

    writer.add_evidence("endpoint_removal_config", results)
    writer.finish_test()


test_evict_006.test_id = "EVICT-006"


def test_evict_007(config: TestConfig, writer: ResultWriter):
    """DaemonSet pods survive node drain (--ignore-daemonsets)."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-007", "DaemonSet survival during drain", "eviction-behavior")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    target = spot_nodes[0]["metadata"]["name"]

    # Count daemonset pods across all nodes before drain
    ds_data = kube.run_json(["get", "daemonsets", "--all-namespaces"])
    ds_items = ds_data.get("items", []) if ds_data else []
    pre_ds_count = sum(
        ds.get("status", {}).get("desiredNumberScheduled", 0) for ds in ds_items
    )

    writer.add_evidence("target_node", target)
    writer.add_evidence("pre_drain_daemonset_count", pre_ds_count)

    try:
        drain_ok = nodes.drain(target, timeout=config.drain_timeout)
        writer.assert_eq("Drain completed (daemonsets ignored)", drain_ok, True)

        time.sleep(10)

        # DaemonSets should still have desired count on other nodes
        ds_data_after = kube.run_json(["get", "daemonsets", "--all-namespaces"])
        ds_items_after = ds_data_after.get("items", []) if ds_data_after else []
        for ds in ds_items_after:
            name = ds.get("metadata", {}).get("name", "")
            desired = ds.get("status", {}).get("desiredNumberScheduled", 0)
            ready = ds.get("status", {}).get("numberReady", 0)
            # Ready should be >= desired - 1 (the drained node)
            writer.assert_gte(
                f"DaemonSet {name} ready >= desired-1",
                ready, desired - 1
            )

        writer.add_evidence("post_drain_daemonsets", len(ds_items_after))
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_evict_007.test_id = "EVICT-007"


def test_evict_008(config: TestConfig, writer: ResultWriter):
    """Eviction during deployment rollout."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-008", "Eviction during deployment rollout", "eviction-behavior")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Pick a stateless service that has a deployment
    svc = config.stateless_services[0]
    svc_pods = pods.get_service_pods(svc)
    if not svc_pods:
        writer.skip_test(f"No pods for service {svc}")
        return

    target = None
    for n in spot_nodes:
        node_name = n["metadata"]["name"]
        for p in svc_pods:
            if pods.get_pod_node(p) == node_name:
                target = node_name
                break
        if target:
            break

    if not target:
        writer.skip_test(f"No spot node found hosting {svc} pods")
        return

    writer.add_evidence("target_node", target)
    writer.add_evidence("service", svc)

    try:
        # Trigger a rollout restart
        kube.run(["rollout", "restart", f"deployment/{svc}", "-n", config.namespace])
        time.sleep(5)

        # Drain the node during rollout
        drain_ok = nodes.drain(target, timeout=config.drain_timeout)
        writer.add_evidence("drain_during_rollout", drain_ok)

        # Wait for rollout to complete
        rollout_result = kube.run(
            ["rollout", "status", f"deployment/{svc}", "-n", config.namespace,
             "--timeout=120s"],
            timeout=130
        )
        rollout_ok = rollout_result.returncode == 0
        writer.assert_eq("Rollout completes after drain", rollout_ok, True)
        writer.add_evidence("rollout_status", rollout_result.stdout.strip() if rollout_ok else rollout_result.stderr.strip())
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_evict_008.test_id = "EVICT-008"


def test_evict_009(config: TestConfig, writer: ResultWriter):
    """Empty node drain causes no disruption."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-009", "Empty node drain no disruption", "eviction-behavior")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Find a spot node with no user pods (or fewest)
    target = None
    min_pods = 99999
    for n in spot_nodes:
        node_name = n["metadata"]["name"]
        all_pods = kube.get_pods()
        user_pods = [p for p in all_pods if pods.get_pod_node(p) == node_name]
        if len(user_pods) < min_pods:
            min_pods = len(user_pods)
            target = node_name

    if not target:
        writer.skip_test("Could not identify target node")
        return

    # Count total running pods before
    pre_running = len([p for p in kube.get_pods() if pods.is_running(p)])
    writer.add_evidence("target_node", target)
    writer.add_evidence("user_pods_on_target", min_pods)
    writer.add_evidence("pre_drain_running", pre_running)

    try:
        drain_ok = nodes.drain(target, timeout=config.drain_timeout)
        writer.assert_eq("Drain completed", drain_ok, True)

        time.sleep(15)

        post_running = len([p for p in kube.get_pods() if pods.is_running(p)])
        writer.assert_gte(
            "Total running pods not significantly reduced",
            post_running, pre_running - min_pods
        )
        writer.add_evidence("post_drain_running", post_running)
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_evict_009.test_id = "EVICT-009"


def test_evict_010(config: TestConfig, writer: ResultWriter):
    """Simultaneous multi-pool drain (1 node from each of 3 pools)."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("EVICT-010", "Simultaneous multi-pool drain", "eviction-behavior")

    spot_nodes = nodes.get_spot_nodes()
    if len(spot_nodes) < 3:
        writer.skip_test(f"Need at least 3 spot nodes, found {len(spot_nodes)}")
        return

    # Select 1 node per pool, up to 3 pools
    pool_targets = {}
    for n in spot_nodes:
        pool = nodes.get_pool_name(n)
        if pool not in pool_targets and len(pool_targets) < 3:
            pool_targets[pool] = n["metadata"]["name"]

    if len(pool_targets) < 3:
        # Fill remaining from any pool
        for n in spot_nodes:
            name = n["metadata"]["name"]
            if name not in pool_targets.values() and len(pool_targets) < 3:
                pool_targets[f"extra_{name}"] = name

    targets = list(pool_targets.values())
    pre_running = len([p for p in kube.get_pods() if pods.is_running(p)])
    writer.add_evidence("pool_targets", pool_targets)
    writer.add_evidence("pre_drain_running", pre_running)

    try:
        # Drain all 3 simultaneously (as fast as sequential allows)
        drain_results = {}
        for t in targets:
            ok = nodes.drain(t, timeout=config.drain_timeout)
            drain_results[t] = ok

        writer.add_evidence("drain_results", drain_results)

        # Wait for rescheduling
        time.sleep(60)

        post_running = len([p for p in kube.get_pods() if pods.is_running(p)])
        writer.assert_gte(
            "Running pods recover after 3-pool drain",
            post_running, pre_running - len(targets) * 2  # generous margin
        )
        writer.add_evidence("post_drain_running", post_running)
    finally:
        for t in targets:
            nodes.uncordon(t)

    writer.finish_test()


test_evict_010.test_id = "EVICT-010"
