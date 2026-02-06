# Grafana Dashboards for AKS Spot Optimization

This directory contains Grafana dashboard JSON templates for monitoring AKS Spot node performance.

## Dashboards

| Dashboard | File | Description |
|-----------|------|-------------|
| **Spot Overview** | `aks-spot-overview.json` | Eviction rates, pod distribution, node counts |
| **Autoscaler Status** | `aks-autoscaler-status.json` | Scaling activity, health checks, pending pods |

## Prerequisites

These dashboards require:
- **kube-state-metrics** deployed in your cluster
- **Prometheus** scraping Kubernetes metrics
- **Grafana** with a Prometheus data source configured

## Installation

### Option 1: Grafana UI Import
1. Open Grafana → Dashboards → Import
2. Upload the JSON file or paste its contents
3. Select your Prometheus data source
4. Click Import

### Option 2: ConfigMap (GitOps)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  aks-spot-overview.json: |
    # Paste contents of aks-spot-overview.json
```

### Option 3: Terraform
```hcl
resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "grafana-spot-dashboards"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "aks-spot-overview.json"     = file("${path.module}/dashboards/aks-spot-overview.json")
    "aks-autoscaler-status.json" = file("${path.module}/dashboards/aks-autoscaler-status.json")
  }
}
```

## Key Metrics Tracked

### Spot Overview Dashboard
- **Evictions/hour**: Rate of pod evictions from spot nodes
- **Pods on Spot %**: Percentage of pods running on spot nodes (target: 70-80%)
- **Pending Pods**: Pods waiting to be scheduled
- **Active Spot Nodes**: Current count of spot instance nodes
- **Node Count Over Time**: Historical spot vs standard node counts
- **Pod Distribution**: Pie chart of pods by node type

### Autoscaler Status Dashboard
- **Autoscaler Health**: Binary health check status
- **Scale-ups/downs**: Scaling activity in the last hour
- **Unschedulable Pods**: Pods that can't be scheduled (triggers scale-up)
- **Scaling Activity Over Time**: Rate of scaling operations
- **Node Count by Pool**: Per-pool node counts

## Alert Rules

Consider adding these alert rules to accompany the dashboards:

```yaml
groups:
  - name: aks-spot-alerts
    rules:
      - alert: HighEvictionRate
        expr: sum(rate(kube_pod_status_reason{reason="Evicted"}[1h])) > 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High spot eviction rate ({{ $value }} evictions/hour)"
          
      - alert: LowSpotUtilization
        expr: |
          sum(kube_pod_info * on(node) group_left() 
          kube_node_labels{label_kubernetes_azure_com_scalesetpriority="spot"}) 
          / sum(kube_pod_info) < 0.5
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Less than 50% of pods on spot nodes"
          
      - alert: AutoscalerUnhealthy
        expr: cluster_autoscaler_health_check == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Cluster autoscaler is unhealthy"
```

## Customization

The dashboards use a `${datasource}` template variable. If your Prometheus data source has a different name, update the variable after import.

For Azure-specific metrics, ensure your cluster has:
- Container Insights enabled (Azure Monitor)
- OR kube-prometheus-stack deployed
