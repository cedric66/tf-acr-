###############################################################################
# Sample KQL Queries for Observability Review
# Use these in Azure Portal > Log Analytics > Logs
###############################################################################

# =============================================================================
# 1. VMSS Scaling Failures (Spot pool issues)
# =============================================================================
# Find all VMSS write operations that failed
AzureActivity
| where CategoryValue == "Administrative"
| where OperationNameValue contains "virtualMachineScaleSets"
| where ActivityStatusValue == "Failed"
| project TimeGenerated, OperationNameValue, ResourceGroup, _ResourceId, 
          ActivityStatusValue, Properties
| order by TimeGenerated desc

# =============================================================================
# 2. Cluster Autoscaler Events
# =============================================================================
# See what the autoscaler decided and why
AzureDiagnostics
| where Category == "cluster-autoscaler"
| project TimeGenerated, log_s
| order by TimeGenerated desc

# =============================================================================
# 3. Node Pool Scaling Activity
# =============================================================================
# Track node additions and removals
AzureActivity
| where CategoryValue == "Administrative"
| where OperationNameValue contains "agentPools"
| project TimeGenerated, OperationNameValue, ActivityStatusValue, 
          Caller, Properties
| order by TimeGenerated desc

# =============================================================================
# 4. Spot Instance Evictions
# =============================================================================
# Find spot eviction events (look for Delete operations on spot pools)
AzureActivity
| where CategoryValue == "Administrative"
| where OperationNameValue contains "virtualMachineScaleSets/delete" 
     or OperationNameValue contains "virtualMachines/delete"
| where _ResourceId contains "spot"
| project TimeGenerated, OperationNameValue, _ResourceId, ActivityStatusValue
| order by TimeGenerated desc

# =============================================================================
# 5. All AKS Control Plane Events (Summary)
# =============================================================================
# Overview of AKS cluster events by category
AzureDiagnostics
| where ResourceType == "MANAGEDCLUSTERS"
| summarize Count=count() by Category, bin(TimeGenerated, 1h)
| render timechart

# =============================================================================
# 6. Failed Pod Scheduling (kube-scheduler)
# =============================================================================
AzureDiagnostics
| where Category == "kube-scheduler"
| where log_s contains "Failed" or log_s contains "error"
| project TimeGenerated, log_s
| order by TimeGenerated desc

# =============================================================================
# 7. Autoscale Actions (Subscription Level)
# =============================================================================
# Track Azure Autoscale engine decisions
AzureActivity
| where CategoryValue == "Autoscale"
| project TimeGenerated, OperationNameValue, Description, Properties
| order by TimeGenerated desc
