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
