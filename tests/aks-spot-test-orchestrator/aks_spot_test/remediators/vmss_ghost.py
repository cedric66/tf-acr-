"""VMSS ghost instance detection and removal."""

from datetime import datetime, timedelta
from typing import List
from ..models import RemediationAction
from ..utils import run_az


def detect_and_remediate(resource_group: str, cluster_name: str, location: str, min_age_minutes: int = 5) -> List[RemediationAction]:
    """Detect and delete VMSS ghost instances."""
    actions = []
    mc_rg = f"MC_{resource_group}_{cluster_name}_{location}"

    # Get all VMSS in managed cluster resource group
    vmss_list = run_az(["vmss", "list", "-g", mc_rg])
    if not vmss_list:
        return actions

    for vmss in vmss_list:
        vmss_name = vmss.get("name", "")

        # Get instances
        instances = run_az(["vmss", "list-instances", "-n", vmss_name, "-g", mc_rg])
        if not instances:
            continue

        for instance in instances:
            instance_id = instance.get("instanceId", "")
            provisioning_state = instance.get("provisioningState", "")

            # Check if ghost (Failed/Unknown state)
            if provisioning_state in ["Failed", "Unknown"]:
                # Check age (only delete if stuck for > min_age_minutes)
                created_time_str = instance.get("timeCreated")
                if created_time_str:
                    try:
                        created_time = datetime.fromisoformat(created_time_str.replace('Z', '+00:00'))
                        age_minutes = (datetime.now(created_time.tzinfo) - created_time).total_seconds() / 60

                        if age_minutes >= min_age_minutes:
                            # Delete ghost instance
                            result = run_az([
                                "vmss", "delete-instances",
                                "-n", vmss_name,
                                "-g", mc_rg,
                                "--instance-ids", instance_id
                            ], output_json=False)

                            success = result is not None
                            actions.append(RemediationAction(
                                timestamp=datetime.now(),
                                action_type="delete_vmss_ghost",
                                target=f"{vmss_name}/{instance_id}",
                                success=success,
                                details=f"Instance in {provisioning_state} state for {age_minutes:.1f} minutes"
                            ))
                    except Exception as e:
                        actions.append(RemediationAction(
                            timestamp=datetime.now(),
                            action_type="delete_vmss_ghost",
                            target=f"{vmss_name}/{instance_id}",
                            success=False,
                            details=f"Error: {str(e)}"
                        ))

    return actions
