# Encrypted Repository & AKS DevOps Toolkit

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
module "aks_cluster" {
  source = "../../modules/aks-spot-optimized"

  cluster_name = "aks-prod-001"
  location     = "australiaeast"
  
  # Define Spot Pools
  spot_node_pools = {
    "spot_general" = {
      vm_size = "Standard_D4s_v5"
      min_count = 3
      max_count = 20
    }
  }
}
```

Reference the [Project Summary](./docs/PROJECT_SUMMARY.md) for full architectural details.

## Encrypted Contents
- `image_evaluation/`
- `terraform/`
- `app/`
- `apps/`
- Documentation files (*.md)

## 🤖 Agentic Workflows
This repository includes specialized workflows for AI Agents to effectively contribute to the codebase.

- [Code Review Workflow](.agent/workflows/code-review.md): Instructions for performing rigorous Terraform and Cloud-Init code reviews.
