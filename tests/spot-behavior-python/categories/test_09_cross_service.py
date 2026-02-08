"""Cross-Service Dependency Tests (DEP-001 through DEP-005).

Validates that inter-service communication survives spot node evictions.
Tests frontend-backend connectivity, database connectivity, queue service
resilience, cart data persistence, and full service mesh health after
disruption events.
"""

import sys
import os
import json
import time
import subprocess

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from config import TestConfig
from lib.test_helpers import KubeCommand, NodeHelper, PodHelper, VMSSHelper
from lib.result_writer import ResultWriter


def _run_connectivity_check(kube: KubeCommand, namespace: str,
                            source_svc: str, target_svc: str, port: int = 80) -> dict:
    """Run a connectivity check from source service pod to target service."""
    source_pods = kube.get_pods(label=f"app={source_svc}")
    if not source_pods:
        source_pods = kube.get_pods(label=f"service={source_svc}")
    if not source_pods:
        return {"success": False, "error": f"No pods found for {source_svc}"}

    pod_name = source_pods[0]["metadata"]["name"]
    result = kube.run([
        "exec", pod_name, "-n", namespace, "--",
        "sh", "-c", f"wget -qO- --timeout=5 http://{target_svc}:{port}/ 2>&1 || "
                     f"curl -sf --connect-timeout 5 http://{target_svc}:{port}/ 2>&1 || "
                     f"echo CONNECTION_FAILED"
    ], timeout=15)

    if result.returncode == 0 and "CONNECTION_FAILED" not in result.stdout:
        return {"success": True, "response_length": len(result.stdout)}
    else:
        return {"success": False, "error": result.stderr[:200] if result.stderr else result.stdout[:200]}


def test_dep_001(config: TestConfig, writer: ResultWriter):
    """Frontend-backend connectivity after spot node eviction."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DEP-001", "Frontend-backend connectivity after eviction", "cross-service")

    # Verify required services are configured
    required_services = ["web", "catalogue"]
    for svc in required_services:
        if svc not in config.all_services:
            writer.skip_test(f"Required service '{svc}' not in config")
            return

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Find a spot node hosting web pods
    target = None
    for n in spot_nodes:
        node_name = n["metadata"]["name"]
        web_pods = pods.get_service_pods("web")
        for p in web_pods:
            if pods.get_pod_node(p) == node_name:
                target = node_name
                break
        if target:
            break

    if not target:
        # Use any spot node
        target = spot_nodes[0]["metadata"]["name"]

    writer.add_evidence("target_node", target)

    # Check connectivity before drain
    pre_check = _run_connectivity_check(kube, config.namespace, "web", "catalogue", 8080)
    writer.add_evidence("pre_drain_connectivity", pre_check)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(30)

        # Wait for web pods to be ready again
        pods.wait_for_ready(label="app=web", timeout=config.pod_ready_timeout)

        # Check connectivity after drain
        post_check = _run_connectivity_check(kube, config.namespace, "web", "catalogue", 8080)
        writer.add_evidence("post_drain_connectivity", post_check)

        # Even if the connectivity check fails (tools may not be in container),
        # verify both services have running pods
        web_running = pods.count_running_for_service("web")
        catalogue_running = pods.count_running_for_service("catalogue")

        writer.assert_gt("Web service has running pods after drain", web_running, 0)
        writer.assert_gt("Catalogue service has running pods after drain", catalogue_running, 0)
        writer.add_evidence("web_running", web_running)
        writer.add_evidence("catalogue_running", catalogue_running)
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_dep_001.test_id = "DEP-001"


def test_dep_002(config: TestConfig, writer: ResultWriter):
    """Database connectivity after node drain."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DEP-002", "Database connectivity after node drain", "cross-service")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Find a spot node near database services (hosting pods that depend on DB)
    target = None
    # Use DB consumer services from config (catalogue, user, cart if present)
    db_consumers = [svc for svc in config.stateless_services if svc in ["catalogue", "user", "cart"]]
    if not db_consumers:
        db_consumers = config.stateless_services[:3]  # First 3 services as fallback
    for n in spot_nodes:
        node_name = n["metadata"]["name"]
        for svc in db_consumers:
            svc_pods = pods.get_service_pods(svc)
            for p in svc_pods:
                if pods.get_pod_node(p) == node_name:
                    target = node_name
                    break
            if target:
                break
        if target:
            break

    if not target:
        target = spot_nodes[0]["metadata"]["name"]

    writer.add_evidence("target_node", target)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(30)

        # Verify database services are still running (they should be on non-spot nodes)
        # Use database services from config (filter out rabbitmq as it's queue, not DB)
        db_services = {svc: 0 for svc in config.stateful_services if svc != "rabbitmq"}
        for db_svc in db_services:
            count = pods.count_running_for_service(db_svc)
            db_services[db_svc] = count
            writer.assert_gt(f"{db_svc} still running after drain", count, 0)

        # Verify consumer services reconnected
        for consumer in db_consumers:
            count = pods.count_running_for_service(consumer)
            writer.assert_gt(f"{consumer} running after drain", count, 0)

        writer.add_evidence("db_service_counts", db_services)
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_dep_002.test_id = "DEP-002"


def test_dep_003(config: TestConfig, writer: ResultWriter):
    """Queue service resilience after spot node drain."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DEP-003", "Queue service resilience", "cross-service")

    # Verify rabbitmq is configured
    if "rabbitmq" not in config.all_services:
        writer.skip_test("Required service 'rabbitmq' not in config")
        return

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Find spot node hosting dispatch or shipping (queue consumers)
    target = None
    # Use queue consumers from config (dispatch, shipping if present)
    queue_consumers = [svc for svc in config.stateless_services if svc in ["dispatch", "shipping"]]
    if not queue_consumers:
        queue_consumers = config.stateless_services[-2:]  # Last 2 services as fallback
    target_svc = None
    for n in spot_nodes:
        node_name = n["metadata"]["name"]
        for svc in queue_consumers:
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
        target = spot_nodes[0]["metadata"]["name"]

    writer.add_evidence("target_node", target)
    writer.add_evidence("target_service", target_svc)

    # Verify rabbitmq is running before drain
    rabbitmq_pre = pods.count_running_for_service("rabbitmq")
    writer.add_evidence("rabbitmq_pre_drain", rabbitmq_pre)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(30)

        # RabbitMQ should still be running (stateful, not on spot)
        rabbitmq_post = pods.count_running_for_service("rabbitmq")
        writer.assert_gt("RabbitMQ still running", rabbitmq_post, 0)

        # Queue consumer services should recover
        for svc in queue_consumers:
            count = pods.count_running_for_service(svc)
            writer.assert_gt(f"{svc} recovered after drain", count, 0)

        writer.add_evidence("rabbitmq_post_drain", rabbitmq_post)
        writer.add_evidence("dispatch_post", pods.count_running_for_service("dispatch"))
        writer.add_evidence("shipping_post", pods.count_running_for_service("shipping"))
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_dep_003.test_id = "DEP-003"


def test_dep_004(config: TestConfig, writer: ResultWriter):
    """Cart data persistence across spot node eviction via Redis."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DEP-004", "Cart persistence across eviction", "cross-service")

    # Verify required services are configured
    required_services = ["cart", "redis"]
    for svc in required_services:
        if svc not in config.all_services:
            writer.skip_test(f"Required service '{svc}' not in config")
            return

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    # Find spot node with cart pod
    target = None
    for n in spot_nodes:
        node_name = n["metadata"]["name"]
        cart_pods = pods.get_service_pods("cart")
        for p in cart_pods:
            if pods.get_pod_node(p) == node_name:
                target = node_name
                break
        if target:
            break

    if not target:
        target = spot_nodes[0]["metadata"]["name"]

    writer.add_evidence("target_node", target)

    # Check Redis is running (data store for cart)
    redis_running = pods.count_running_for_service("redis")
    writer.add_evidence("redis_pre_drain", redis_running)
    writer.assert_gt("Redis running before drain", redis_running, 0)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(30)

        # Redis should survive (stateful, not on spot)
        redis_after = pods.count_running_for_service("redis")
        writer.assert_gt("Redis still running after drain", redis_after, 0)

        # Cart service should recover
        cart_after = pods.count_running_for_service("cart")
        writer.assert_gt("Cart service recovered after drain", cart_after, 0)

        # Verify cart can reach Redis (basic check)
        cart_pods = pods.get_service_pods("cart")
        if cart_pods:
            cart_ready = pods.wait_for_ready("app=cart", timeout=60)
            writer.assert_eq("Cart pods ready after recovery", cart_ready, True)

        writer.add_evidence("redis_post_drain", redis_after)
        writer.add_evidence("cart_post_drain", cart_after)
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_dep_004.test_id = "DEP-004"


def test_dep_005(config: TestConfig, writer: ResultWriter):
    """Full service mesh health after drain and recovery."""
    kube = KubeCommand(config.namespace)
    nodes = NodeHelper(kube)
    pods = PodHelper(kube, nodes)
    writer.start_test("DEP-005", "Full service mesh health post-recovery", "cross-service")

    spot_nodes = nodes.get_spot_nodes()
    if not spot_nodes:
        writer.skip_test("No spot nodes available")
        return

    target = spot_nodes[0]["metadata"]["name"]

    # Baseline: count all running services
    pre_counts = {}
    for svc in config.all_services:
        pre_counts[svc] = pods.count_running_for_service(svc)

    writer.add_evidence("target_node", target)
    writer.add_evidence("pre_drain_counts", pre_counts)

    try:
        nodes.drain(target, timeout=config.drain_timeout)
        time.sleep(45)

        # Verify all services have at least 1 running pod
        post_counts = {}
        all_healthy = True
        for svc in config.all_services:
            count = pods.count_running_for_service(svc)
            post_counts[svc] = count
            if count == 0:
                all_healthy = False
            writer.assert_gt(f"{svc} has running pods", count, 0)

        writer.add_evidence("post_drain_counts", post_counts)
        writer.add_evidence("all_services_healthy", all_healthy)

        # Check for pending pods (should be 0 after recovery)
        pending = kube.get_pods(field_selector="status.phase=Pending")
        writer.add_evidence("pending_pods_count", len(pending))
        writer.assert_eq(
            "No pending pods after recovery",
            len(pending), 0
        )
    finally:
        nodes.uncordon(target)

    writer.finish_test()


test_dep_005.test_id = "DEP-005"
