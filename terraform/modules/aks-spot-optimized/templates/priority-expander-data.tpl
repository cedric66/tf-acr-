# Priority Expander Configuration for AKS Spot Optimization
# 
# Lower numbers = higher priority (scaled first)
# Memory-optimized pools (E-series) are prioritized due to lower eviction rates
# 
# Priority levels:
#   5: Memory-optimized spot pools (E-series) - lowest eviction risk
#  10: General/Compute spot pools (D/F-series) - standard spot
#  20: Standard (on-demand) pools - fallback for availability  
#  30: System pool - never scale for user workloads

# Priority 5: Memory-optimized spot pools (prefer E-series for lower eviction)
5:
%{ for pool in spot_pools ~}
%{ if pool.priority_weight == 5 || (try(pool.priority_weight, 10) == 5) ~}
  - .*${pool.name}.*
%{ endif ~}
%{ endfor ~}

# Priority 10: General purpose spot pools
10:
%{ for pool in spot_pools ~}
%{ if pool.priority_weight != 5 && (try(pool.priority_weight, 10) != 5) ~}
  - .*${pool.name}.*
%{ endif ~}
%{ endfor ~}

# Priority 20: Standard pools (fallback for availability)
20:
%{ for pool in standard_pools ~}
  - .*${pool.name}.*
%{ endfor ~}

# Priority 30: System pool (never scale for user workloads)
30:
  - .*system.*
