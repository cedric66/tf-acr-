"""PDB Enforcement Tests (PDB-001 through PDB-006).

Validates that Pod Disruption Budgets exist for critical services, have correct
minAvailable settings, are healthy, and properly block or allow node drains
depending on replica headroom.
"""

import sys
import os
import json
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def test_pdb_001(config: TestConfig, writer: ResultWriter):
    """PDBs exist for all PDB-protected services."""
    kube = KubeCommand(config.namespace)
    writer.start_test("PDB-001", "PDBs exist for required services", "pdb-enforcement")

    pdbs = kube.get_pdbs()
    pdb_names = [pdb.get("metadata", {}).get("name", "") for pdb in pdbs]

    found_services = []
    missing_services = []

    for svc in config.pdb_services:
        # PDB name may contain the service name or match via labels
        pdb_found = False
        for pdb in pdbs:
            pdb_name = pdb.get("metadata", {}).get("name", "")
            selector_labels = pdb.get("spec", {}).get("selector", {}).get("matchLabels", {})
            # Check if service name appears in PDB name or selector labels
            if svc in pdb_name or svc in str(selector_labels):
                pdb_found = True
                break
        if pdb_found:
            found_services.append(svc)
        else:
            missing_services.append(svc)

        writer.assert_eq(f"PDB exists for {svc}", pdb_found, True)

    writer.add_evidence("pdb_names", pdb_names)
    writer.add_evidence("found_services", found_services)
    writer.add_evidence("missing_services", missing_services)
    writer.assert_eq(
        f"All {len(config.pdb_services)} PDBs found",
        len(found_services), len(config.pdb_services)
    )
    writer.finish_test()


test_pdb_001.test_id = "PDB-001"


def test_pdb_002(config: TestConfig, writer: ResultWriter):
    """All PDBs have minAvailable=1."""
    kube = KubeCommand(config.namespace)
    writer.start_test("PDB-002", "PDB minAvailable=1 for all services", "pdb-enforcement")

    pdbs = kube.get_pdbs()
    results = {}

    for pdb in pdbs:
        pdb_name = pdb.get("metadata", {}).get("name", "")
        spec = pdb.get("spec", {})
        min_available = spec.get("minAvailable")
        max_unavailable = spec.get("maxUnavailable")

        results[pdb_name] = {
            "minAvailable": min_available,
            "maxUnavailable": max_unavailable,
        }
        writer.assert_eq(
            f"PDB {pdb_name} minAvailable=1",
            min_available, 1
        )

    writer.add_evidence("pdb_settings", results)
    writer.finish_test()


test_pdb_002.test_id = "PDB-002"


def test_pdb_003(config: TestConfig, writer: ResultWriter):
    """PDB status is healthy (allowedDisruptions > 0)."""
    kube = KubeCommand(config.namespace)
    writer.start_test("PDB-003", "PDB status healthy - allowedDisruptions > 0", "pdb-enforcement")

    pdbs = kube.get_pdbs()
    results = {}

    for pdb in pdbs:
        pdb_name = pdb.get("metadata", {}).get("name", "")
        status = pdb.get("status", {})
        allowed = status.get("disruptionsAllowed", 0)
        current = status.get("currentHealthy", 0)
        desired = status.get("desiredHealthy", 0)
        expected = status.get("expectedPods", 0)

        results[pdb_name] = {
            "disruptionsAllowed": allowed,
            "currentHealthy": current,
            "desiredHealthy": desired,
            "expectedPods": expected,
        }
        writer.assert_gt(
            f"PDB {pdb_name} allows disruptions",
            allowed, 0
        )

    writer.add_evidence("pdb_status", results)
    writer.finish_test()


test_pdb_003.test_id = "PDB-003"


def test_pdb_004(config: TestConfig, writer: ResultWriter):
    """PDB blocks drain when service is at minimum replicas."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("PDB-004", "PDB blocks drain when at minimum replicas", "pdb-enforcement")

    # Find a PDB-protected service with pods on spot nodes
    target_svc = None
    target_node = None
    for svc in config.pdb_services:
        svc_pods = pods.get_service_pods(svc)
        running = [p for p in svc_pods if pods.is_running(p)]
        if len(running) < 2:
            continue
        for p in running:
            node_name = pods.get_pod_node(p)
            node = kube.get_node(node_name) if node_name else None
            if node and nodes.is_spot(node):
                target_svc = svc
                target_node = node_name
                break
        if target_svc:
            break

    if not target_svc:
        writer.skip_test("No PDB-protected service with >=2 replicas on spot nodes")
        return

    writer.add_evidence("target_service", target_svc)
    writer.add_evidence("target_node", target_node)

    # Scale to 1 replica
    deployments = kube.run_json(["get", "deployments", "-n", config.namespace,
                                  "-l", f"app={target_svc}"])
    deploy_items = deployments.get("items", []) if deployments else []

    if not deploy_items:
        # Try statefulset
        sts = kube.run_json(["get", "statefulsets", "-n", config.namespace,
                              "-l", f"app={target_svc}"])
        deploy_items = sts.get("items", []) if sts else []

    if not deploy_items:
        writer.skip_test(f"No deployment/statefulset found for {target_svc}")
        return

    resource_name = deploy_items[0]["metadata"]["name"]
    resource_kind = deploy_items[0].get("kind", "Deployment").lower()
    original_replicas = deploy_items[0].get("spec", {}).get("replicas", 1)

    try:
        # Scale to 1 so PDB minAvailable=1 blocks drain
        kube.run(["scale", f"{resource_kind}/{resource_name}",
                  "--replicas=1", "-n", config.namespace])
        time.sleep(20)

        # Attempt drain with a short timeout - should be blocked or very slow
        result = kube.run([
            "drain", target_node,
            "--ignore-daemonsets",
            "--delete-emptydir-data",
            "--grace-period=10",
            "--timeout=15s",
        ], timeout=30)

        # When PDB blocks drain, kubectl returns non-zero
        drain_blocked = result.returncode != 0
        writer.assert_eq(
            "Drain blocked by PDB at minimum",
            drain_blocked, True
        )
        writer.add_evidence("drain_stderr", result.stderr[:500] if result.stderr else "")
    finally:
        # Restore original replicas
        kube.run(["scale", f"{resource_kind}/{resource_name}",
                  f"--replicas={original_replicas}", "-n", config.namespace])
        nodes.uncordon(target_node)

    writer.finish_test()


test_pdb_004.test_id = "PDB-004"


def test_pdb_005(config: TestConfig, writer: ResultWriter):
    """PDB allows drain with sufficient headroom."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("PDB-005", "PDB allows drain with headroom", "pdb-enforcement")

    # Find a service with >=2 running replicas on spot
    target_svc = None
    target_node = None
    for svc in config.pdb_services:
        running = pods.count_running_for_service(svc)
        if running >= 2:
            svc_pods = pods.get_service_pods(svc)
            for p in svc_pods:
                node_name = pods.get_pod_node(p)
                node = kube.get_node(node_name) if node_name else None
                if node and nodes.is_spot(node):
                    target_svc = svc
                    target_node = node_name
                    break
        if target_svc:
            break

    if not target_svc:
        writer.skip_test("No PDB-protected service with >=2 replicas on spot")
        return

    pre_count = pods.count_running_for_service(target_svc)
    writer.add_evidence("target_service", target_svc)
    writer.add_evidence("target_node", target_node)
    writer.add_evidence("pre_drain_replica_count", pre_count)

    try:
        drain_ok = nodes.drain(target_node, timeout=config.drain_timeout)
        writer.assert_eq("Drain succeeds with headroom", drain_ok, True)

        time.sleep(15)
        post_count = pods.count_running_for_service(target_svc)
        writer.assert_gte(
            f"{target_svc} maintains >=1 running replica",
            post_count, 1
        )
        writer.add_evidence("post_drain_replica_count", post_count)
    finally:
        nodes.uncordon(target_node)

    writer.finish_test()


test_pdb_005.test_id = "PDB-005"


def test_pdb_006(config: TestConfig, writer: ResultWriter):
    """PDB label selectors match actual pod labels."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("PDB-006", "PDB selector matches pods", "pdb-enforcement")

    pdbs = kube.get_pdbs()
    results = {}

    for pdb in pdbs:
        pdb_name = pdb.get("metadata", {}).get("name", "")
        selector = pdb.get("spec", {}).get("selector", {})
        match_labels = selector.get("matchLabels", {})

        if not match_labels:
            results[pdb_name] = {"match_labels": {}, "matched_pods": 0, "issue": "no matchLabels"}
            continue

        # Build label selector string
        label_parts = [f"{k}={v}" for k, v in match_labels.items()]
        label_str = ",".join(label_parts)

        matched_pods = kube.get_pods(label=label_str)
        running_matched = [p for p in matched_pods if pods.is_running(p)]

        results[pdb_name] = {
            "match_labels": match_labels,
            "matched_pods": len(matched_pods),
            "running_matched": len(running_matched),
        }
        writer.assert_gt(
            f"PDB {pdb_name} selector matches running pods",
            len(running_matched), 0
        )

    writer.add_evidence("pdb_selector_matches", results)
    writer.finish_test()


test_pdb_006.test_id = "PDB-006"
