###############################################################################
# AKS Spot-Optimized Module - RBAC Role Assignments
# Purpose: Grant cluster admin access to Azure AD users/groups
###############################################################################

###############################################################################
# Azure Kubernetes Service RBAC Cluster Admin Role Assignment
# This grants full cluster admin access via Azure RBAC (not Kubernetes RBAC)
###############################################################################

locals {
  # Merge new and deprecated variables
  all_admin_principals = concat(
    var.admin_principals,
    [for id in var.admin_group_object_ids : {
      object_id = id
      type      = "Group" # Default to Group for backward compatibility
    }]
  )
}

resource "azurerm_role_assignment" "aks_rbac_cluster_admin" {
  for_each = var.enable_rbac && var.azure_ad_enabled ? {
    for idx, principal in local.all_admin_principals : principal.object_id => principal
  } : {}

  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value.object_id
  principal_type       = each.value.type

  # Skip AAD check only for service principals
  skip_service_principal_aad_check = each.value.type == "ServicePrincipal"
}
