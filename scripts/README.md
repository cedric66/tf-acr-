# AKS Spot Optimization Toolkit

A collection of Bash scripts to analyze, optimize, and migrate workloads to Spot Node Pools in Azure Kubernetes Service (AKS).

## Overview
This toolkit helps you cost-optimize an existing AKS cluster by:
1.  **Analyzing Eligibility**: Checks if your region/cluster supports Spot pools and Node Autoprovisioning (NAP).
2.  **Adding Spot Pools**: Generates commands to safely add Spot pools with correct eviction policies.
3.  **Migrating Workloads**: Scans existing deployments and generates `kubectl` patches to move eligible workloads to Spot.

## Features
- **Auto-SKU Selection**: Automatically picks the best available Spot-capable SKU in your region.
- **Resilience First**: Recommends 2+ Spot pools for HA and `Delete` eviction policy.
- **Topology Aware**: Injects `topologySpreadConstraints` for high-replica workloads.
- **Configurable**: Define workload distribution percentages and excluded namespaces in `spot-config.yaml`.
- **Dry Run Support**: All scripts include a `--mock` mode for testing without Azure access.

## Prerequisites
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://stedolan.github.io/jq/download/)

## Installation
Clone the repository and make scripts executable:
```bash
chmod +x scripts/*.sh
cd scripts
```

## Configuration
Edit `spot-config.yaml` to customize:
- `distribution`: % of replicas to move to Spot (default: 80% stateless, 0% stateful).
- `excluded_namespaces`: Namespaces to skip (default: kube-system, monitoring).
- `preferred_skus`: List of VM sizes to try for Spot pools.

## Logic & Design
For details on how the scripts decide between NAP vs Cluster Autoscaler, or how workload distribution is calculated, see [DESIGN.md](DESIGN.md).

## Usage

### 1. Check Eligibility
Analyze your cluster network and region capabilities:
```bash
./eligibility-report.sh --resource-group <RG> --name <CLUSTER>
```
*Output: Recommended strategy (NAP vs Manual Pools) and selected SKU.*

### 2. Add Spot Pools
Generate the CLI commands to add the pools:
```bash
./add-spot-pools.sh --resource-group <RG> --name <CLUSTER>
```
To execute immediately:
```bash
./add-spot-pools.sh --resource-group <RG> --name <CLUSTER> --execute
```

### 3. Review Workloads
See which of your deployments are candidates for Spot:
```bash
./workload-report.sh
```

### 4. Migrate Workloads
Generate patches to add `tolerations` and `affinity`:
```bash
./migrate-workloads.sh
```
To apply patches immediately:
```bash
./migrate-workloads.sh --execute
```

## Testing
The toolkit includes a mock based testing suite.
Run the tests locally:
```bash
./test/run-tests.sh
```
This verifies logic against mock JSON data in `test/mocks/`.
