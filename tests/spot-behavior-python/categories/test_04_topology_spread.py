"""Topology Spread Tests (TOPO-001 through TOPO-005).

Validates that topology spread constraints are correctly configured on workloads
to distribute pods across zones, priority types, and individual nodes.
"""

import sys
import os
import json
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_topo_001(config: TestConfig, writer: ResultWriter):
    """Zone spread constraint present - 3 TSCs on stateless pods."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("TOPO-001", "Zone spread constraint present (3 TSCs)", "topology-spread")

    expected_keys = [
        "topology.kubernetes.io/zone",
        "kubernetes.azure.com/scalesetpriority",
        "kubernetes.io/hostname",
    ]

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        tscs = pod.get("spec", {}).get("topologySpreadConstraints", [])
        tsc_keys = [tsc.get("topologyKey", "") for tsc in tscs]

        found_keys = []
        for ek in expected_keys:
            if ek in tsc_keys:
                found_keys.append(ek)

        results[svc] = {
            "tsc_count": len(tscs),
            "topology_keys": tsc_keys,
            "expected_found": found_keys,
        }
        writer.assert_eq(
            f"{svc} has 3 topology spread constraints",
            len(tscs), 3
        )
        writer.assert_eq(
            f"{svc} has all 3 expected topology keys",
            len(found_keys), 3
        )

    writer.add_evidence("topology_constraints", results)
    writer.finish_test()


test_topo_001.test_id = "TOPO-001"


def test_topo_002(config: TestConfig, writer: ResultWriter):
    """Zone maxSkew=1 enforced."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("TOPO-002", "Zone maxSkew=1 enforced", "topology-spread")

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        tscs = pod.get("spec", {}).get("topologySpreadConstraints", [])

        zone_max_skew = None
        for tsc in tscs:
            if tsc.get("topologyKey") == "topology.kubernetes.io/zone":
                zone_max_skew = tsc.get("maxSkew")
                break

        results[svc] = {"zone_maxSkew": zone_max_skew}
        writer.assert_eq(
            f"{svc} zone TSC maxSkew=1",
            zone_max_skew, 1
        )

    writer.add_evidence("zone_max_skew", results)
    writer.finish_test()


test_topo_002.test_id = "TOPO-002"


def test_topo_003(config: TestConfig, writer: ResultWriter):
    """Priority type spread maxSkew=2."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("TOPO-003", "Priority type spread maxSkew=2", "topology-spread")

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        tscs = pod.get("spec", {}).get("topologySpreadConstraints", [])

        priority_max_skew = None
        for tsc in tscs:
            if tsc.get("topologyKey") == "kubernetes.azure.com/scalesetpriority":
                priority_max_skew = tsc.get("maxSkew")
                break

        results[svc] = {"priority_maxSkew": priority_max_skew}
        writer.assert_eq(
            f"{svc} priority TSC maxSkew=2",
            priority_max_skew, 2
        )

    writer.add_evidence("priority_max_skew", results)
    writer.finish_test()


test_topo_003.test_id = "TOPO-003"


def test_topo_004(config: TestConfig, writer: ResultWriter):
    """Hostname spread maxSkew=1."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("TOPO-004", "Hostname spread maxSkew=1", "topology-spread")

    results = {}
    for svc in config.stateless_services:
        svc_pods = pods.get_service_pods(svc)
        if not svc_pods:
            results[svc] = "no_pods"
            continue
        pod = svc_pods[0]
        tscs = pod.get("spec", {}).get("topologySpreadConstraints", [])

        hostname_max_skew = None
        for tsc in tscs:
            if tsc.get("topologyKey") == "kubernetes.io/hostname":
                hostname_max_skew = tsc.get("maxSkew")
                break

        results[svc] = {"hostname_maxSkew": hostname_max_skew}
        writer.assert_eq(
            f"{svc} hostname TSC maxSkew=1",
            hostname_max_skew, 1
        )

    writer.add_evidence("hostname_max_skew", results)
    writer.finish_test()


test_topo_004.test_id = "TOPO-004"


def test_topo_005(config: TestConfig, writer: ResultWriter):
    """Spread approximately maintained after disruption."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("TOPO-005", "Spread after disruption", "topology-spread")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    target = spot_nodes[0]["metadata"]["name"]
    svc = config.stateless_services[0]

    # Measure zone distribution before
    pre_zones = pods.get_pod_zones(svc)
    writer.add_evidence("target_node", target)
    writer.add_evidence("service", svc)
    writer.add_evidence("pre_drain_zones", pre_zones)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(30)

        # Measure zone distribution after
        post_zones = pods.get_pod_zones(svc)
        writer.add_evidence("post_drain_zones", post_zones)

        # After drain and rescheduling, pods should still be in >=1 zone
        # (ideally close to original spread)
        svc_pods = pods.get_service_pods(svc)
        running = [p for p in svc_pods if pods.is_running(p)]
        zone_counts = {}
        for p in running:
            node_name = pods.get_pod_node(p)
            if node_name:
                node = kube.get_node(node_name)
                if node:
                    z = nodes.get_zone(node)
                    if z:
                        zone_counts[z] = zone_counts.get(z, 0) + 1

        writer.add_evidence("post_drain_zone_counts", zone_counts)

        if len(zone_counts) > 0 and sum(zone_counts.values()) > 0:
            total = sum(zone_counts.values())
            max_pct = max(zone_counts.values()) / total * 100
            # After disruption, topology should be approximately maintained
            # Allow up to 80% in one zone (relaxed check)
            writer.assert_lt(
                "No zone has more than 80% of pods after drain",
                int(max_pct), 81
            )
        else:
            writer.add_assertion("Pods found in zones after drain", ">0 zones", 0, False)

        writer.assert_gte(
            "Pods in at least 1 zone after drain",
            len(post_zones), 1
        )
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_topo_005.test_id = "TOPO-005"
