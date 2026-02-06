# Production Environment - AKS Spot-Optimized

This environment deploys an AKS cluster optimized for cost savings using Azure Spot VMs.

## Prerequisites

Before deploying, update the following placeholder values in `main.tf`:

| Placeholder | Description |
|-------------|-------------|
| `subscription_id` | Your Azure subscription ID |
| `rg-xxxxxx` | Existing resource group name |
| `vnet-xxxxxx` | Existing virtual network name |
| `snet-xxxxxx` | Existing subnet name |

## Architecture

- **Backend**: Local state (for development/testing)
- **Resource Group**: Uses existing RG via data source
- **Networking**: Uses existing VNet and subnet via data sources
- **AKS Cluster**: Spot-optimized with:
  - System node pool (always-on)
  - Standard workload pool (fallback)
  - 3 Spot node pools (diversified VM sizes)

## Usage

```bash
# Initialize Terraform
terraform init

# Plan changes
terraform plan

# Apply configuration
terraform apply
```

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | AKS cluster name |
| `cluster_id` | AKS cluster resource ID |
| `kube_config_command` | kubectl configuration command |
| `node_pools_summary` | Summary of all node pools |
| `priority_expander_manifest` | Priority expander ConfigMap YAML |
