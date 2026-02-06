###############################################################################
# AKS Spot-Optimized Module - RBAC Role Assignments
# Purpose: Grant cluster admin access to Azure AD users/groups
###############################################################################

###############################################################################
# Azure Kubernetes Service RBAC Cluster Admin Role Assignment
# This grants full cluster admin access via Azure RBAC (not Kubernetes RBAC)
###############################################################################

resource "azurerm_role_assignment" "aks_rbac_cluster_admin" {
  for_each = var.enable_rbac && var.azure_ad_enabled ? toset(var.admin_group_object_ids) : []

  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value

  # Skip errors if principal doesn't exist (handles AAD replication delay)
  skip_service_principal_aad_check = true
}
