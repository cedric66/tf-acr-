"""Cluster state snapshot utilities."""

from datetime import datetime
from typing import Dict
from ..models import ClusterSnapshot
from ..utils import run_kubectl


def capture_snapshot() -> ClusterSnapshot:
    """Capture current cluster state snapshot."""
    nodes = run_kubectl(["get", "nodes"], output_json=True)
    pods = run_kubectl(["get", "pods", "--all-namespaces"], output_json=True)

    if not nodes or not pods:
        return ClusterSnapshot(
            timestamp=datetime.now(),
            total_nodes=0,
            ready_nodes=0,
            spot_nodes=0,
            total_pods=0,
            pending_pods=0
        )

    node_items = nodes.get("items", [])
    pod_items = pods.get("items", [])

    # Count nodes
    total_nodes = len(node_items)
    ready_nodes = sum(1 for n in node_items if is_node_ready(n))
    spot_nodes = sum(1 for n in node_items if is_spot_node(n))

    # Count pods
    total_pods = len(pod_items)
    pending_pods = sum(1 for p in pod_items if p.get("status", {}).get("phase") == "Pending")

    # Node pool distribution
    pool_counts: Dict[str, int] = {}
    for node in node_items:
        pool = node.get("metadata", {}).get("labels", {}).get("agentpool", "unknown")
        pool_counts[pool] = pool_counts.get(pool, 0) + 1

    return ClusterSnapshot(
        timestamp=datetime.now(),
        total_nodes=total_nodes,
        ready_nodes=ready_nodes,
        spot_nodes=spot_nodes,
        total_pods=total_pods,
        pending_pods=pending_pods,
        node_pool_counts=pool_counts
    )


def is_node_ready(node: dict) -> bool:
    """Check if node is in Ready state."""
    for condition in node.get("status", {}).get("conditions", []):
        if condition.get("type") == "Ready":
            return condition.get("status") == "True"
    return False


def is_spot_node(node: dict) -> bool:
    """Check if node is a spot VM."""
    labels = node.get("metadata", {}).get("labels", {})
    return labels.get("kubernetes.azure.com/scalesetpriority") == "spot"
