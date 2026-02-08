"""Stuck node detection and removal."""

from datetime import datetime, timedelta
from typing import List
from ..models import RemediationAction
from ..utils import run_kubectl, run_command


def detect_and_remediate(min_age_minutes: int = 5) -> List[RemediationAction]:
    """Detect and delete NotReady nodes stuck for > min_age_minutes."""
    actions = []

    nodes = run_kubectl(["get", "nodes"], output_json=True)
    if not nodes:
        return actions

    for node in nodes.get("items", []):
        node_name = node.get("metadata", {}).get("name", "")

        # Check if NotReady
        is_ready = False
        for condition in node.get("status", {}).get("conditions", []):
            if condition.get("type") == "Ready":
                is_ready = condition.get("status") == "True"
                break

        if not is_ready:
            # Check age of NotReady condition
            for condition in node.get("status", {}).get("conditions", []):
                if condition.get("type") == "Ready" and condition.get("status") == "False":
                    last_transition = condition.get("lastTransitionTime")
                    if last_transition:
                        try:
                            transition_time = datetime.fromisoformat(last_transition.replace('Z', '+00:00'))
                            age_minutes = (datetime.now(transition_time.tzinfo) - transition_time).total_seconds() / 60

                            if age_minutes >= min_age_minutes:
                                # Delete stuck node
                                result = run_command(["kubectl", "delete", "node", node_name])
                                success = result.returncode == 0

                                actions.append(RemediationAction(
                                    timestamp=datetime.now(),
                                    action_type="delete_stuck_node",
                                    target=node_name,
                                    success=success,
                                    details=f"Node NotReady for {age_minutes:.1f} minutes"
                                ))
                        except Exception as e:
                            actions.append(RemediationAction(
                                timestamp=datetime.now(),
                                action_type="delete_stuck_node",
                                target=node_name,
                                success=False,
                                details=f"Error: {str(e)}"
                            ))

    return actions
