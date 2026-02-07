"""Pod Distribution Tests (DIST-001 through DIST-010).

Validates that stateless services run on spot nodes, stateful services avoid spot,
tolerations and affinities are correctly configured, and workloads are properly
distributed across pools and zones.
"""

import sys
import os
import json

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_dist_001(config: TestConfig, writer: ResultWriter):
    """Stateless services run on spot nodes."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-001", "Stateless services on spot nodes", "pod-distribution")

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = {"total": 0, "on_spot": 0}
            continue
        on_spot = 0
        for pod in svc_pods:
            node_name = pods.get_pod_node(pod)
            if not node_name:
                continue
            node = kube.get_node(node_name)
            if node and nodes.is_spot(node):
                on_spot += 1
        results[svc] = {"total": len(svc_pods), "on_spot": on_spot}
        writer.assert_gt(
            f"{svc} has pods on spot nodes",
            on_spot, 0
        )

    writer.add_evidence("service_spot_distribution", results)
    writer.finish_test()


test_dist_001.test_id = "DIST-001"


def test_dist_002(config: TestConfig, writer: ResultWriter):
    """Stateful services NOT on spot nodes."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-002", "Stateful services off spot nodes", "pod-distribution")

    results = {}
    for svc in config.stateful_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = {"total": 0, "on_spot": 0}
            continue
        on_spot = 0
        for pod in svc_pods:
            node_name = pods.get_pod_node(pod)
            if not node_name:
                continue
            node = kube.get_node(node_name)
            if node and nodes.is_spot(node):
                on_spot += 1
        results[svc] = {"total": len(svc_pods), "on_spot": on_spot}
        writer.assert_eq(
            f"{svc} has no pods on spot nodes",
            on_spot, 0
        )

    writer.add_evidence("stateful_service_placement", results)
    writer.finish_test()


test_dist_002.test_id = "DIST-002"


def test_dist_003(config: TestConfig, writer: ResultWriter):
    """Spot tolerations present on stateless services."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-003", "Spot tolerations present", "pod-distribution")

    toleration_target = {
        "key": "kubernetes.azure.com/scalesetpriority",
        "value": "spot",
        "effect": "NoSchedule",
    }
    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        tolerations = pod.get("spec", {}).get("tolerations", [])
        found = False
        for t in tolerations:
            if (t.get("key") == toleration_target["key"]
                    and t.get("value") == toleration_target["value"]
                    and t.get("effect") == toleration_target["effect"]):
                found = True
                break
        results[svc] = {"has_spot_toleration": found, "tolerations": tolerations}
        writer.assert_eq(
            f"{svc} has spot toleration",
            found, True
        )

    writer.add_evidence("toleration_check", results)
    writer.finish_test()


test_dist_003.test_id = "DIST-003"


def test_dist_004(config: TestConfig, writer: ResultWriter):
    """Node affinity preference weight 100 for spot."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-004", "Node affinity preference weight 100 for spot", "pod-distribution")

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        affinity = pod.get("spec", {}).get("affinity", {})
        node_affinity = affinity.get("nodeAffinity", {})
        preferred = node_affinity.get("preferredDuringSchedulingIgnoredDuringExecution", [])

        spot_weight = 0
        for pref in preferred:
            match_exprs = pref.get("preference", {}).get("matchExpressions", [])
            for expr in match_exprs:
                if (expr.get("key") == "kubernetes.azure.com/scalesetpriority"
                        and "spot" in expr.get("values", [])):
                    spot_weight = pref.get("weight", 0)
                    break

        results[svc] = {"spot_affinity_weight": spot_weight, "preferred_rules": len(preferred)}
        writer.assert_eq(
            f"{svc} has spot affinity weight 100",
            spot_weight, 100
        )

    writer.add_evidence("node_affinity_weights", results)
    writer.finish_test()


test_dist_004.test_id = "DIST-004"


def test_dist_005(config: TestConfig, writer: ResultWriter):
    """Stateful services have required anti-spot affinity."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-005", "Stateful anti-spot required affinity", "pod-distribution")

    results = {}
    for svc in config.stateful_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        affinity = pod.get("spec", {}).get("affinity", {})
        node_affinity = affinity.get("nodeAffinity", {})
        required = node_affinity.get("requiredDuringSchedulingIgnoredDuringExecution", {})
        node_selectors = required.get("nodeSelectorTerms", [])

        has_anti_spot = False
        for term in node_selectors:
            for expr in term.get("matchExpressions", []):
                if (expr.get("key") == "kubernetes.azure.com/scalesetpriority"
                        and expr.get("operator") == "NotIn"
                        and "spot" in expr.get("values", [])):
                    has_anti_spot = True
                    break

        results[svc] = {"has_anti_spot_required": has_anti_spot}
        writer.assert_eq(
            f"{svc} has required anti-spot affinity",
            has_anti_spot, True
        )

    writer.add_evidence("stateful_anti_spot_affinity", results)
    writer.finish_test()


test_dist_005.test_id = "DIST-005"


def test_dist_006(config: TestConfig, writer: ResultWriter):
    """System pool protected from user workloads."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-006", "System pool protected from user workloads", "pod-distribution")

    system_nodes = nodes.get_pool_nodes(config.system_pool)
    if not system_nodes:
        writer.skip_test("No system pool nodes found")
        return

    system_node_names = {n["metadata"]["name"] for n in system_nodes}
    excluded_namespaces = {"kube-system", "gatekeeper-system", "calico-system", "tigera-operator"}

    all_ns_pods = kube.run_json(["get", "pods", "--all-namespaces"])
    items = all_ns_pods.get("items", []) if all_ns_pods else []

    user_pods_on_system = []
    for pod in items:
        ns = pod.get("metadata", {}).get("namespace", "")
        if ns in excluded_namespaces:
            continue
        node_name = pod.get("spec", {}).get("nodeName", "")
        if node_name in system_node_names:
            pod_name = pod.get("metadata", {}).get("name", "")
            user_pods_on_system.append({"pod": pod_name, "namespace": ns, "node": node_name})

    writer.assert_eq(
        "No user workload pods on system pool",
        len(user_pods_on_system), 0
    )
    writer.add_evidence("system_node_names", list(system_node_names))
    writer.add_evidence("user_pods_on_system", user_pods_on_system)
    writer.finish_test()


test_dist_006.test_id = "DIST-006"


def test_dist_007(config: TestConfig, writer: ResultWriter):
    """Pods distributed across multiple spot pools."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-007", "Pod diversity across spot pools", "pod-distribution")

    pools_with_pods = set()
    pool_pod_counts = {}

    all_pods = kube.get_pods()
    for pod in all_pods:
        node_name = pods.get_pod_node(pod)
        if not node_name:
            continue
        node = kube.get_node(node_name)
        if not node:
            continue
        pool = nodes.get_pool_name(node)
        if pool in config.spot_pools:
            pools_with_pods.add(pool)
            pool_pod_counts[pool] = pool_pod_counts.get(pool, 0) + 1

    writer.assert_gte(
        "Pods spread across at least 2 spot pools",
        len(pools_with_pods), 2
    )
    writer.add_evidence("spot_pools_with_pods", sorted(pools_with_pods))
    writer.add_evidence("pool_pod_counts", pool_pod_counts)
    writer.finish_test()


test_dist_007.test_id = "DIST-007"


def test_dist_008(config: TestConfig, writer: ResultWriter):
    """Pods spread across at least 2 zones, no zone exceeds 60%."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-008", "Zone spread distribution", "pod-distribution")

    zone_counts = {}
    total_pods = 0

    all_pods = kube.get_pods()
    for pod in all_pods:
        if not pods.is_running(pod):
            continue
        node_name = pods.get_pod_node(pod)
        if not node_name:
            continue
        node = kube.get_node(node_name)
        if not node:
            continue
        zone = nodes.get_zone(node)
        if zone:
            zone_counts[zone] = zone_counts.get(zone, 0) + 1
            total_pods += 1

    writer.assert_gte(
        "Pods in at least 2 zones",
        len(zone_counts), 2
    )

    if total_pods > 0:
        max_zone_pct = max(zone_counts.values()) / total_pods * 100
        writer.assert_lt(
            "No zone exceeds 60% of pods",
            int(max_zone_pct), 61
        )
    else:
        writer.add_assertion("No running pods found", "pods > 0", 0, False)

    writer.add_evidence("zone_counts", zone_counts)
    writer.add_evidence("total_pods", total_pods)
    writer.finish_test()


test_dist_008.test_id = "DIST-008"


def test_dist_009(config: TestConfig, writer: ResultWriter):
    """Topology spread constraints present with ScheduleAnyway."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-009", "Topology spread constraints configured", "pod-distribution")

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        tscs = pod.get("spec", {}).get("topologySpreadConstraints", [])

        has_zone_tsc = False
        zone_uses_schedule_anyway = False
        for tsc in tscs:
            if tsc.get("topologyKey") == "topology.kubernetes.io/zone":
                has_zone_tsc = True
                if tsc.get("whenUnsatisfiable") == "ScheduleAnyway":
                    zone_uses_schedule_anyway = True

        results[svc] = {
            "tsc_count": len(tscs),
            "has_zone_tsc": has_zone_tsc,
            "zone_schedule_anyway": zone_uses_schedule_anyway,
        }
        writer.assert_eq(
            f"{svc} has zone topology spread constraint",
            has_zone_tsc, True
        )
        writer.assert_eq(
            f"{svc} zone TSC uses ScheduleAnyway",
            zone_uses_schedule_anyway, True
        )

    writer.add_evidence("topology_spread_constraints", results)
    writer.finish_test()


test_dist_009.test_id = "DIST-009"


def test_dist_010(config: TestConfig, writer: ResultWriter):
    """Spot ratio >= 50% of user workload pods."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DIST-010", "Spot ratio >= 50% of user workload pods", "pod-distribution")

    total_user_pods = 0
    spot_pods = 0

    all_pods = kube.get_pods()
    for pod in all_pods:
        if not pods.is_running(pod):
            continue
        node_name = pods.get_pod_node(pod)
        if not node_name:
            continue
        node = kube.get_node(node_name)
        if not node:
            continue
        pool = nodes.get_pool_name(node)
        if pool == config.system_pool:
            continue
        total_user_pods += 1
        if nodes.is_spot(node):
            spot_pods += 1

    ratio = (spot_pods / total_user_pods * 100) if total_user_pods > 0 else 0
    writer.assert_gte(
        "Spot pods >= 50% of user workload pods",
        int(ratio), 50
    )
    writer.add_evidence("total_user_pods", total_user_pods)
    writer.add_evidence("spot_pods", spot_pods)
    writer.add_evidence("spot_ratio_pct", round(ratio, 1))
    writer.finish_test()


test_dist_010.test_id = "DIST-010"
