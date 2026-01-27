###############################################################################
# Priority Expander ConfigMap Deployment
#
# This file deploys the cluster-autoscaler-priority-expander ConfigMap
# required when using `expander = "priority"` in the autoscaler profile.
#
# Without this ConfigMap, the autoscaler silently falls back to `random`.
###############################################################################

resource "kubernetes_config_map" "priority_expander" {
  count = var.deploy_priority_expander ? 1 : 0

  metadata {
    name      = "cluster-autoscaler-priority-expander"
    namespace = "kube-system"
    labels = {
      "app"        = "cluster-autoscaler"
      "managed-by" = "terraform"
    }
  }

  data = {
    priorities = templatefile("${path.module}/templates/priority-expander-data.tpl", {
      spot_pools     = var.spot_pool_configs
      standard_pools = var.standard_pool_configs
    })
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}
