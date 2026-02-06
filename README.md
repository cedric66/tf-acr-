# Encrypted Repository & AKS DevOps Toolkit

> [!TIP]
> **New to the project?** Start with the **[Consolidated Project Brief](CONSOLIDATED_PROJECT_BRIEF.md)** for a complete overview.

## 🔐 Encrypted Content
This branch contains encrypted content.

### How to Decrypt
The decryption script is included in this branch at `scripts/decrypt-repo.sh`.

```bash
./scripts/decrypt-repo.sh xxxxx
```

## 🛠️ AKS DevOps Toolkit
This branch also contains the AKS DevOps Toolkit for auditing and managing clusters.

**Documentation**: [scripts/README.md](scripts/README.md)

**Quick Start**:
```bash
cd scripts/
pip install -r requirements.txt
python devops_toolkit.py
```

## 🚀 Project Overview: AKS Spot Node Optimization
This project implements a cost-optimization strategy for Azure Kubernetes Service (AKS) by utilizing Spot Virtual Machines for up to 75% of compute capacity, targeting a ~52% reduction in cloud spend.

### What are Spot Node Pools?
Spot Node Pools leverage unused Azure compute capacity at deep discounts (60-90%). The trade-off is that these nodes can be "evicted" (terminated) by Azure with 30 seconds of notice when the capacity is needed elsewhere.

### How It Works
This solution ensures high availability despite the volatility of Spot VMs through:
1.  **Multi-Pool Architecture**: Uses divers VM sizes (e.g., `D4s`, `E4s`) across different availability zones to minimize the impact of a single spot market outage.
2.  **Priority Expander**: A Kubernetes scaler configuration that prefers cheap Spot nodes but automatically falls back to Standard (On-Demand) nodes if Spot capacity is unavailable.
3.  **Chaos Engineering**: Validated resilience against "Simultaneous Eviction" scenarios where entire pools disappear instantly.

### Applying the Configuration
The core logic is encapsulated in the Terraform module: `terraform/modules/aks-spot-optimized`.

**Example Usage**:
To deploy a spot-optimized cluster, reference the module in your environment configuration (e.g., `terraform/environments/prod/main.tf`):

```hcl
module "aks" {
  source = "../../modules/aks-spot-optimized"

  cluster_name            = "aks-spot-prod"
  resource_group_name     = data.azurerm_resource_group.main.name
  location                = "australiaeast"
  kubernetes_version      = "1.30"
  vnet_subnet_id          = data.azurerm_subnet.aks.id
  
  # 1. System Pool (Critical Cluster Services)
  system_pool_config = {
    name      = "system"
    vm_size   = "Standard_D4s_v5"
    min_count = 3
    max_count = 5
    zones     = ["1", "2", "3"]
  }

  # 2. Standard Pools (Fallback & Critical Workloads)
  standard_pool_configs = [{
    name      = "stdworkload"
    vm_size   = "Standard_D4s_v5"
    min_count = 2
    max_count = 10
    zones     = ["1", "2", "3"]
  }]

  # 3. Spot Pools (Diversified Strategy: 1 Zone + 1 SKU per pool)
  spot_pool_configs = [
    { name = "spot-d4-z1", vm_size = "Standard_D4s_v5", zones = ["1"], ... },
    { name = "spot-d8-z2", vm_size = "Standard_D8s_v5", zones = ["2"], ... },
    { name = "spot-e4-z3", vm_size = "Standard_E4s_v5", zones = ["3"], ... }
  ]
}

module "diagnostics" {
  source = "../../modules/diagnostics"
  # Exports Activity Logs & AKS Diagnostics to Log Analytics
  # Critical for post-mortem of spot evictions and scaling events
}
```

**Deployment Workflow**:
1.  Initialize: `terraform init`
2.  Configure: Copy `terraform.tfvars.example` to `terraform.tfvars`
3.  Deploy: `terraform apply`

Reference the [Consolidated Project Brief](CONSOLIDATED_PROJECT_BRIEF.md) for a high-level summary.

## 🎯 Workload Deployment (Isolated)

Workload manifests are **isolated from cluster infrastructure** in the `workloads/` directory.

| Workload | Purpose |
|----------|---------|
| [Robot Shop](workloads/robot-shop/) | E-commerce microservices for spot testing |
| [Descheduler](workloads/descheduler/) | Auto-rebalance after evictions |

**Deployment Order**:
```bash
# 1. Deploy Descheduler (handles rebalancing)
cd workloads/descheduler && ./deploy.sh

# 2. Deploy Robot Shop (test workload)
cd workloads/robot-shop && ./deploy.sh
kubectl apply -f workloads/robot-shop/pdbs.yaml
```

## 📚 Documentation Index

### 🎯 Project Guidance
- [**Consolidated Project Brief**](CONSOLIDATED_PROJECT_BRIEF.md) - Single source of truth
- [Project Summary](docs/PROJECT_SUMMARY.md) - Detailed deliverables & metrics
- [Project Gap Analysis](docs/PROJECT_GAP_ANALYSIS.md) - Identified gaps & improvements
- [300+ Cluster Rollout Strategy](docs/FLEET_ROLLOUT_STRATEGY.md) - Fleet-scale rollout plan

### 🏗️ Technical Architecture
- [AKS Spot Architecture](docs/AKS_SPOT_NODE_ARCHITECTURE.md) - Core technical design
- [Scaled Spot Orchestration](docs/SCALED_SPOT_ORCHESTRATION.md) - Scaling & orchestration logic
- [AKS Network Configuration Guide](docs/AKS_NETWORK_KARPENTER_GUIDE.md) - AKS networking reference (Karpenter sections archived)
- [Terragrunt Analysis](docs/TERRAGRUNT_ANALYSIS.md) - Infrastructure management patterns

### 🛠️ Operations & SRE
- [SRE Operational Runbook](docs/SRE_OPERATIONAL_RUNBOOK.md) - Incident response & procedures
- [DevOps Team Guide](docs/DEVOPS_TEAM_GUIDE.md) - Migration & deployment for app teams
- [Chaos Engineering Tests](docs/CHAOS_ENGINEERING_TESTS.md) - Resilience validation scenarios
- [Spot Eviction Scenarios](docs/SPOT_EVICITION_SCENARIOS.md) - Failover, fallback, & recovery (Descheduler)
- [Robot Shop Spot Testing](docs/ROBOT_SHOP_SPOT_TESTING.md) - End-to-end polyglot microservices test
- [Manual Eviction Test Manifests](tests/manifests/) - Pre-configured YAMLs for testing
- [Kind Spot Testing](docs/KIND_SPOT_TESTING.md) - Local spot simulation guide
- [Kubernetes Upgrade Guide](docs/KUBERNETES_UPGRADE_GUIDE.md) - K8s 1.28 → 1.29+ upgrade path

### 📊 Monitoring
- [Grafana Dashboard Templates](monitoring/dashboards/) - Spot Overview & Autoscaler Status dashboards

### ⚖️ Governance & Business
- [Executive Presentation](docs/EXECUTIVE_PRESENTATION.md) - Business case for leadership
- [Executive One-Slide Summary](docs/EXECUTIVE_SLIDE.md) - High-level executive brief
- [FinOps Cost Analysis](docs/FINOPS_COST_ANALYSIS.md) - Detailed financial modeling
- [Security Assessment](docs/SECURITY_ASSESSMENT.md) - Threat model & compliance
- [Principal Engineer Audit](docs/PRINCIPAL_ENGINEER_AUDIT.md) - Code review & risk assessment

## 🔐 Encrypted Contents
- `image_evaluation/`
- `terraform/`
- `app/`
- `apps/`
- Documentation files (*.md)

## 🤖 Agentic Workflows
This repository includes specialized workflows for AI Agents to effectively contribute to the codebase.

- [Code Review Workflow](.agent/workflows/code-review.md): Instructions for performing rigorous Terraform and Cloud-Init code reviews.
