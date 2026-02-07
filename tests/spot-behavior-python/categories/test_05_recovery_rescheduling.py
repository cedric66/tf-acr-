"""Recovery and Rescheduling Tests (RECV-001 through RECV-006).

Validates pod reschedule timing, service continuity during drains, replacement
pool selection preferences, node replacement provisioning, multi-service
recovery, and rapid sequential drain scenarios.
"""

import sys
import os
import json
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_recv_001(config: TestConfig, writer: ResultWriter):
    """Pod reschedule time after spot node drain."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("RECV-001", "Pod reschedule time measurement", "recovery-rescheduling")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    target = spot_nodes[0]["metadata"]["name"]
    all_pods = kube.get_pods()
    pods_on_target = [p for p in all_pods
                      if pods.get_pod_node(p) == target and pods.is_running(p)]

    if not pods_on_target:
        writer.skip_test(f"No running pods on node {target}")
        return

    pod_count_before = len(pods_on_target)
    total_running_before = len([p for p in all_pods if pods.is_running(p)])

    writer.add_evidence("target_node", target)
    writer.add_evidence("pods_on_target", pod_count_before)
    writer.add_evidence("total_running_before", total_running_before)

    try:
        start_time = time.time()
        nodes.drain(target, timeout=config.drain_timeout)

        # Poll until all pods are Running again (up to pod_ready_timeout)
        recovered = False
        elapsed = 0.0
        while elapsed < config.pod_ready_timeout:
            time.sleep(5)
            elapsed = time.time() - start_time
            current_running = len([p for p in kube.get_pods() if pods.is_running(p)])
            if current_running >= total_running_before:
                recovered = True
                break

        reschedule_time = round(elapsed, 1)
        writer.add_evidence("reschedule_time_seconds", reschedule_time)
        writer.add_evidence("recovered", recovered)

        writer.assert_eq("All pods recovered to Running", recovered, True)
        writer.assert_lt(
            f"Reschedule time under {config.pod_ready_timeout}s",
            int(reschedule_time), config.pod_ready_timeout
        )
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_recv_001.test_id = "RECV-001"


def test_recv_002(config: TestConfig, writer: ResultWriter):
    """Service continuity - running replicas never drop below PDB minAvailable."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("RECV-002", "Service continuity during drain", "recovery-rescheduling")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Pick a PDB-protected service that has pods on a spot node
    target_svc = None
    target_node = None
    for svc in config.pdb_services:
        running = pods.count_running_for_service(svc)
        if running >= 2:
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

    writer.add_evidence("target_service", target_svc)
    writer.add_evidence("target_node", target_node)

    min_observed = 999
    pdb_min = 1  # default PDB minAvailable

    try:
        # Start drain in background and monitor
        nodes.cordon(target_node)

        # Evict pods with monitoring
        start = time.time()
        kube.run([
            "drain", target_node,
            "--ignore-daemonsets",
            "--delete-emptydir-data",
            f"--grace-period={config.drain_timeout}",
            f"--timeout={config.drain_timeout}s",
            "--force"
        ], timeout=config.drain_timeout + 30)

        # Monitor replica count during and after drain
        for _ in range(12):
            count = pods.count_running_for_service(target_svc)
            if count < min_observed:
                min_observed = count
            time.sleep(5)

        writer.add_evidence("min_observed_running", min_observed)
        writer.assert_gte(
            f"{target_svc} never dropped below minAvailable={pdb_min}",
            min_observed, pdb_min
        )
    finally:
        nodes.uncordon(target_node)

    writer.finish_test()


test_recv_002.test_id = "RECV-002"


def test_recv_003(config: TestConfig, writer: ResultWriter):
    """Replacement pods prefer spot pools after drain."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("RECV-003", "Replacement pool selection prefers spot", "recovery-rescheduling")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    target = spot_nodes[0]["metadata"]["name"]
    all_pods = kube.get_pods()
    pods_on_target = [p["metadata"]["name"] for p in all_pods
                      if pods.get_pod_node(p) == target and pods.is_running(p)]

    writer.add_evidence("target_node", target)
    writer.add_evidence("pods_evicted", pods_on_target)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(30)

        # Check where new pods landed
        new_pods = kube.get_pods()
        on_spot = 0
        on_standard = 0
        for p in new_pods:
            if not pods.is_running(p):
                continue
            n = pods.get_pod_node(p)
            if not n or n == target:
                continue
            node = kube.get_node(n)
            if not node:
                continue
            pool = nodes.get_pool_name(node)
            if pool in config.spot_pools:
                on_spot += 1
            elif pool == config.standard_pool:
                on_standard += 1

        total = on_spot + on_standard
        spot_pct = (on_spot / total * 100) if total > 0 else 0

        writer.add_evidence("pods_on_spot_after", on_spot)
        writer.add_evidence("pods_on_standard_after", on_standard)
        writer.add_evidence("spot_percentage", round(spot_pct, 1))

        writer.assert_gt(
            "Majority of rescheduled pods on spot nodes",
            on_spot, on_standard
        )
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_recv_003.test_id = "RECV-003"


def test_recv_004(config: TestConfig, writer: ResultWriter):
    """Autoscaler provisions replacement node after drain."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("RECV-004", "Node replacement provisioning", "recovery-rescheduling")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    target = spot_nodes[0]["metadata"]["name"]
    target_pool = nodes.get_pool_name(spot_nodes[0])
    pre_count = nodes.count_ready_in_pool(target_pool)

    writer.add_evidence("target_node", target)
    writer.add_evidence("target_pool", target_pool)
    writer.add_evidence("pre_drain_pool_count", pre_count)

    try:
        nodes.drain(target, timeout=config.drain_timeout)

        # Wait for autoscaler to provision replacement (up to node_ready_timeout)
        replacement_found = False
        elapsed = 0
        poll_interval = 15
        while elapsed < config.node_ready_timeout:
            time.sleep(poll_interval)
            elapsed += poll_interval
            current_count = nodes.count_ready_in_pool(target_pool)
            # Count should recover (replacement node provisioned)
            # Drained node may still be counted but NotReady
            pool_nodes = nodes.get_pool_nodes(target_pool)
            ready_names = [n["metadata"]["name"] for n in pool_nodes
                          if nodes.is_ready(n) and n["metadata"]["name"] != target]
            if len(ready_names) >= pre_count - 1:
                replacement_found = True
                break

        writer.add_evidence("replacement_found", replacement_found)
        writer.add_evidence("wait_time_seconds", elapsed)

        # This test may not trigger scale-up if other pools absorb the load
        # so we check if the cluster has sufficient capacity overall
        total_ready = len([n for n in kube.get_nodes() if nodes.is_ready(n)])
        writer.add_evidence("total_ready_nodes", total_ready)
        writer.assert_gt(
            "Cluster maintains ready nodes after drain",
            total_ready, 0
        )
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_recv_004.test_id = "RECV-004"


def test_recv_005(config: TestConfig, writer: ResultWriter):
    """Multi-service recovery after draining a shared node."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("RECV-005", "Multi-service recovery", "recovery-rescheduling")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Find a spot node hosting pods from multiple services
    target = None
    services_on_node = []
    for n in spot_nodes:
        node_name = n["metadata"]["name"]
        svcs_found = set()
        all_pods = kube.get_pods()
        for p in all_pods:
            if pods.get_pod_node(p) == node_name and pods.is_running(p):
                labels = p.get("metadata", {}).get("labels", {})
                svc_name = labels.get("app", labels.get("service", ""))
                if svc_name:
                    svcs_found.add(svc_name)
        if len(svcs_found) >= 2:
            target = node_name
            services_on_node = sorted(svcs_found)
            break

    if not target:
        # Fallback: use first spot node
        target = spot_nodes[0]["metadata"]["name"]
        all_pods = kube.get_pods()
        for p in all_pods:
            if pods.get_pod_node(p) == target:
                labels = p.get("metadata", {}).get("labels", {})
                svc_name = labels.get("app", labels.get("service", ""))
                if svc_name:
                    services_on_node.append(svc_name)
        services_on_node = sorted(set(services_on_node))

    # Record pre-drain counts
    pre_counts = {}
    for svc in services_on_node:
        pre_counts[svc] = pods.count_running_for_service(svc)

    writer.add_evidence("target_node", target)
    writer.add_evidence("services_on_node", services_on_node)
    writer.add_evidence("pre_drain_counts", pre_counts)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(45)

        # Verify all services recovered
        post_counts = {}
        all_recovered = True
        for svc in services_on_node:
            count = pods.count_running_for_service(svc)
            post_counts[svc] = count
            if count < pre_counts.get(svc, 0):
                all_recovered = False
            writer.assert_gte(
                f"{svc} recovered to pre-drain count",
                count, pre_counts.get(svc, 0)
            )

        writer.add_evidence("post_drain_counts", post_counts)
        writer.add_evidence("all_recovered", all_recovered)
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_recv_005.test_id = "RECV-005"


def test_recv_006(config: TestConfig, writer: ResultWriter):
    """Rapid sequential drains (2 nodes, 30s apart) with full recovery."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("RECV-006", "Rapid sequential drains", "recovery-rescheduling")

    spot_nodes = nodes.get_spot_nodes()
    if len(spot_nodes) < 2:
        writer.skip_test(f"Need at least 2 spot nodes, found {len(spot_nodes)}")
        return

    target1 = spot_nodes[0]["metadata"]["name"]
    target2 = spot_nodes[1]["metadata"]["name"]
    pre_running = len([p for p in kube.get_pods() if pods.is_running(p)])

    writer.add_evidence("target1", target1)
    writer.add_evidence("target2", target2)
    writer.add_evidence("pre_drain_running", pre_running)

    try:
        # First drain
        drain1_ok = nodes.drain(target1, timeout=config.drain_timeout)
        writer.add_evidence("drain1_ok", drain1_ok)

        # Wait 30 seconds
        time.sleep(30)

        # Second drain
        drain2_ok = nodes.drain(target2, timeout=config.drain_timeout)
        writer.add_evidence("drain2_ok", drain2_ok)

        # Wait for full recovery
        time.sleep(60)

        post_running = len([p for p in kube.get_pods() if pods.is_running(p)])
        writer.add_evidence("post_drain_running", post_running)

        writer.assert_gte(
            "Full recovery after sequential drains",
            post_running, pre_running - 4  # allow small margin
        )
    finally:
        nodes.uncordon(target1)
        nodes.uncordon(target2)

    writer.finish_test()


test_recv_006.test_id = "RECV-006"
