###############################################################################
# Cluster Autoscaler Priority Expander ConfigMap
# 
# Purpose: Configures the cluster autoscaler to prefer spot node pools
#          over standard pools when scaling up, ensuring cost optimization
#          while maintaining fallback capability.
#
# How it works:
# - Lower priority numbers are preferred (10 before 20)
# - When pods need to be scheduled and new nodes are required, the autoscaler
#   will first try to scale spot pools (priority 10)
# - If spot pools fail to scale (capacity unavailable), it falls back to 
#   standard pools (priority 20)
###############################################################################
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
  labels:
    app: cluster-autoscaler
    managed-by: terraform
data:
  priorities: |-
    # Priority 10: Spot pools (preferred for cost savings)
    10:
%{ for pool in spot_pools ~}
      - .*${pool.name}.*
%{ endfor ~}
    
    # Priority 20: Standard pools (fallback for availability)
    20:
%{ for pool in standard_pools ~}
      - .*${pool.name}.*
%{ endfor ~}
    
    # Priority 30: System pool (never scale for user workloads)
    30:
      - .*system.*
