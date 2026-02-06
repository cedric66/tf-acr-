# AKS Spot-Optimized Infrastructure (Bicep)

This directory contains the [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview) implementation of the AKS spot-optimized architecture. It serves as a faster, native alternative to the Terraform implementation.

## 🚀 Key Features

- **Cost Optimization**: Mixed usage of System (On-Demand) and User (Spot) node pools.
- **Resilience**: 
  - Standard (On-Demand) fallback pool for critical workloads.
  - Diversified Spot pools across multiple Availability Zones (1, 2, 3) and VM families (D, E, F series) to minimize eviction impact.
- **Autoscaling**: Cluster Autoscaler optimized for spot workloads (priority expander).
- **Security**: Azure AD RBAC integration and Managed Identity.

## 📂 Project Structure

```
bicep/
├── main.bicep                          # Main orchestration template
├── modules/
│   └── aks-spot-optimized/
│       ├── aks.bicep                   # AKS cluster, system pool, & autoscaler
│       └── node-pools.bicep            # Configurable node pool module
└── environments/
    └── prod/
        ├── main.bicepparam             # Production configuration parameters
        └── deploy.sh                   # Helper script for deployment
```

## 🛠️ Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (version 2.20.0 or later)
- Bicep CLI (automatically installed with Azure CLI)

## ⚡ Quick Start

1. **Navigate to the production environment:**
   ```bash
   cd environments/prod
   ```

2. **Configure Parameters:**
   Open `main.bicepparam` and update the `vnetSubnetId` with your existing Subnet Resource ID:
   ```bicep
   param vnetSubnetId = '/subscriptions/YOUR-SUB-ID/resourceGroups/YOUR-RG/providers/Microsoft.Network/virtualNetworks/YOUR-VNET/subnets/YOUR-SUBNET'
   ```

3. **Deploy:**
   Use the included helper script to validate and deploy:

   ```bash
   # Validate syntax
   ./deploy.sh validate

   # Preview changes (What-If)
   ./deploy.sh what-if

   # Deploy to Azure
   # Defaults to resource group 'rg-aks-prod' in 'australiaeast'
   ./deploy.sh deploy
   ```

   *To specify a custom resource group or location:*
   ```bash
   RESOURCE_GROUP=my-rg LOCATION=eastus ./deploy.sh deploy
   ```

## ⚙️ Configuration

The infrastructure is customized via `main.bicepparam`. Key configurations include:

| Parameter | Description |
|-----------|-------------|
| `systemPoolConfig` | Configuration for the primary system node pool. |
| `standardPoolConfigs` | List of on-demand user pools (fallback capacity). |
| `spotPoolConfigs` | List of spot pools. By default, includes 4 pools separated by Zone and VM Family for maximum availability. |
| `autoscalerProfile` | Fine-tuned settings for spot eviction handling (e.g., `expander: priority`). |

## 🆚 Bicep vs. Terraform

| Feature | Bicep | Terraform |
|---------|-------|-----------|
| **State** | Stateless (Azure is the source of truth) | State file (requires locking/backend) |
| **Speed** | 🚀 Fast (Parallel native deployment) | Slower (Client-side dependency graph) |
| **Syntax** | Azure-specific domain language | HCL (Provider agnostic concepts) |
| **Drift** | `what-if` command | `terraform plan` |
