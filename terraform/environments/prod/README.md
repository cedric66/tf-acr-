# Production Environment - AKS Spot-Optimized

Deploy an AKS cluster optimized for cost savings using Azure Spot VMs.

## Quick Start

```bash
# 1. Copy and configure tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Initialize and deploy
terraform init
terraform plan
terraform apply
```

## Required Variables

| Variable | Description |
|----------|-------------|
| `subscription_id` | Azure subscription ID |
| `resource_group_name` | Existing resource group for AKS |
| `vnet_name` | Existing virtual network name |
| `subnet_name` | Existing subnet name for AKS nodes |

## Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `vnet_resource_group_name` | (same as RG) | VNet's resource group if different |
| `environment` | `prod` | Environment name |
| `location` | `australiaeast` | Azure region |
| `kubernetes_version` | `1.34` | Kubernetes version |
| `cluster_name_prefix` | `aks-spot` | Cluster name prefix |
| `os_sku` | `Ubuntu` | Node OS (Ubuntu, Ubuntu2404, AzureLinux) |
| `host_encryption_enabled` | `false` | Enable host-based encryption |
| `log_analytics_retention_days` | `30` | Log Analytics retention |
| `extra_tags` | `{}` | Additional resource tags |

## Architecture

- **Backend**: Local state (for development/testing)
- **Networking**: Uses existing VNet and subnet via data sources
- **AKS Cluster**: Spot-optimized with:
  - System node pool (always-on, 3 AZs)
  - Standard workload pool (fallback)
  - 3 Spot node pools (diversified VM sizes across zones)

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | AKS cluster name |
| `cluster_id` | AKS cluster resource ID |
| `kube_config_command` | kubectl configuration command |
| `node_pools_summary` | Summary of all node pools |
| `priority_expander_manifest` | Priority expander ConfigMap YAML |

## Features

- ✅ Kubernetes 1.34 (latest)
- ✅ Ubuntu 24.04 LTS (auto-selected for K8s 1.35+)
- ✅ `scale_down_mode=Delete` for spot pools
- ✅ Priority expander for autoscaler
- ✅ Azure Monitor integration
- ✅ Azure AD RBAC enabled
