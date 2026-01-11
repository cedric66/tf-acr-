# AKS Spot Node Cost Optimization

## Branch: `feature/aks-spot-node-cost-optimization`

This branch contains the architectural plan and Terraform implementation for reducing AKS cluster costs using Azure Spot VM instances while maintaining workload availability.

## Quick Start

1. Review the [Architecture Document](docs/AKS_SPOT_NODE_ARCHITECTURE.md)
2. Deploy using Terraform in `terraform/environments/prod/`
3. Apply Kubernetes manifests from `terraform/modules/aks-spot-optimized/templates/`

## Key Components

| Component | Description |
|-----------|-------------|
| [Architecture Doc](docs/AKS_SPOT_NODE_ARCHITECTURE.md) | Full technical design and failure analysis |
| [Terraform Module](terraform/modules/aks-spot-optimized/) | Reusable AKS module with spot optimization |
| [Prod Environment](terraform/environments/prod/) | Production deployment example |
| [K8s Templates](terraform/modules/aks-spot-optimized/templates/) | Deployment manifests with topology spread |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    AKS Cluster                              │
├─────────────────────────────────────────────────────────────┤
│  System Pool     │  Standard Pool   │  Spot Pools (3x)     │
│  (Always-On)     │  (Fallback)      │  (Cost Optimized)    │
│                  │                  │                       │
│  • CoreDNS       │  • Critical      │  • General workloads │
│  • kube-proxy    │    workloads     │  • Batch jobs        │
│  • CNI           │  • Overflow      │  • Dev/Test          │
└─────────────────────────────────────────────────────────────┘
```

## Expected Savings

| Configuration | Monthly Cost | Savings |
|---------------|--------------|---------|
| 100% Standard | $10,000 | - |
| 70% Spot + 30% Standard | $5,000 | **50%** |
| 80% Spot + 20% Standard | $4,200 | **58%** |

## Key Failure Cases Addressed

1. **Simultaneous Multi-Pool Eviction** → Standard pool auto-scaling
2. **Autoscaler Delay** → Overprovisioned placeholder pods
3. **Spot Unavailability** → Priority expander fallback
4. **Topology Spread Failures** → `whenUnsatisfiable: ScheduleAnyway`
5. **Stateful Workload Risk** → Hard anti-affinity from spot pools
6. **30-Second Eviction Window** → Pre-stop hooks + graceful shutdown

## Usage

```bash
# Initialize Terraform
cd terraform/environments/prod
terraform init

# Plan changes
terraform plan -out=plan.tfplan

# Apply
terraform apply plan.tfplan

# Get kubeconfig
az aks get-credentials --resource-group rg-aks-prod --name aks-prod

# Apply priority expander
kubectl apply -f - <<< "$(terraform output -raw priority_expander_manifest)"
```

## Document Status

| Role | Status |
|------|--------|
| Platform Architect | ⏳ Pending Review |
| SRE Lead | ⏳ Pending Review |
| FinOps Lead | ⏳ Pending Review |
| Security Reviewer | ⏳ Pending Review |
