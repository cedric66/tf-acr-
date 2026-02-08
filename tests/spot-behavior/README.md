# AKS Spot Behavior Tests (Bash)

Comprehensive test suite validating AKS spot node behavior, eviction handling, autoscaling, and workload resilience.

## Overview

This test suite contains **50+ tests** organized into 10 categories:

1. **Pod Distribution** (DIST-001..010) - Validate pod placement across spot pools and zones
2. **Eviction Behavior** (EVICT-001..010) - Test graceful shutdown and pod rescheduling
3. **PDB Enforcement** (PDB-001..006) - Verify Pod Disruption Budget compliance
4. **Topology Spread** (TOPO-001..005) - Validate zone and node anti-affinity
5. **Recovery & Rescheduling** (RECV-001..006) - Test pod recovery after eviction
6. **Sticky Fallback** (STICK-001..005) - Verify descheduler moves pods back to spot
7. **VMSS & Node Pool** (VMSS-001..006) - Validate VMSS configuration and zone mapping
8. **Autoscaler** (AUTO-001..005) - Test cluster autoscaler behavior with spot
9. **Cross-Service** (DEP-001..005) - Validate service-to-service connectivity during disruption
10. **Edge Cases** (EDGE-001..005) - Stress tests and failure scenarios

## Prerequisites

1. **Deployed AKS cluster** with spot node pools (use `terraform apply` from `terraform/environments/prod`)
2. **kubectl** configured to connect to the cluster
3. **Azure CLI** (for VMSS tests)
4. **jq** for JSON processing
5. **Robot Shop** deployed in the cluster:
   ```bash
   kubectl apply -f ../../manifests/robot-shop/
   ```

## Configuration

### Step 1: Create Configuration File

```bash
cp .env.example .env
```

### Step 2: Edit .env

```bash
# Match these to your deployed cluster
CLUSTER_NAME=aks-spot-prod
RESOURCE_GROUP=rg-aks-spot
NAMESPACE=robot-shop
```

### Step 3: Load Configuration

```bash
source .env
# OR
export $(cat .env | xargs)
```

## Running Tests

### Run All Tests

```bash
./run-all-tests.sh
```

### Run Specific Category

```bash
# Run only pod distribution tests (read-only, safe)
./run-all-tests.sh --category 01-pod-distribution

# Run eviction behavior tests (destructive - drains nodes)
./run-all-tests.sh --category 02-eviction-behavior
```

### Run Single Test

```bash
./run-all-tests.sh --test DIST-001
./run-all-tests.sh --test EVICT-002
```

### Dry Run (List Tests Without Executing)

```bash
./run-all-tests.sh --dry-run
./run-all-tests.sh --category 05-recovery-rescheduling --dry-run
```

## Test Types

| Category | Test Type | Impact |
|----------|-----------|--------|
| Pod Distribution (01) | Read-only | Safe |
| Eviction Behavior (02) | Destructive | Drains nodes |
| PDB Enforcement (03) | Destructive | Drains nodes |
| Topology Spread (04) | Destructive | Drains nodes |
| Recovery (05) | Destructive | Drains nodes |
| Sticky Fallback (06) | Destructive | Drains nodes |
| VMSS/Node Pool (07) | Read-only | Safe (az CLI) |
| Autoscaler (08) | Mixed | Some read-only, some drains |
| Cross-Service (09) | Destructive | Drains nodes |
| Edge Cases (10) | Destructive | Drains nodes, deletes pods |

**⚠️ DESTRUCTIVE TESTS**: Tests that drain nodes will temporarily disrupt workloads. Ensure:
- PDBs are configured correctly
- Replicas > 1 for critical services
- Run during maintenance windows for production clusters

## Results

Results are written as JSON files to `./results/`:

```bash
ls results/
# DIST-001.json  DIST-002.json  EVICT-001.json  ...

# View summary
cat results/test_summary.json | jq '.summary'
```

### Example Result Structure

```json
{
  "test_id": "DIST-001",
  "test_name": "Pods distributed across spot pools",
  "category": "pod-distribution",
  "status": "pass",
  "duration_seconds": 12,
  "assertions": [
    {
      "description": "At least 3 spot pools have pods",
      "expected": ">=3",
      "actual": "5",
      "passed": true
    }
  ],
  "evidence": {
    "spot_pool_distribution": {"spotgeneral1": 8, "spotmemory1": 6, ...}
  },
  "environment": {
    "cluster_name": "aks-spot-prod",
    "resource_group": "rg-aks-spot",
    "kubernetes_version": "v1.28.5"
  }
}
```

## Customizing Configuration

The test framework reads configuration from `config.sh`, which sources environment variables. You can:

### Option 1: Edit .env File

```bash
# Edit .env
CLUSTER_NAME=my-cluster
RESOURCE_GROUP=my-rg

# Load and run
source .env
./run-all-tests.sh
```

### Option 2: Export Variables Inline

```bash
CLUSTER_NAME=my-cluster RESOURCE_GROUP=my-rg ./run-all-tests.sh
```

### Option 3: Multiple Cluster Configs

```bash
# Create multiple config files
cp .env .env.dev
cp .env .env.prod

# Edit each file with cluster-specific values

# Run against dev
export $(cat .env.dev | xargs)
./run-all-tests.sh

# Run against prod
export $(cat .env.prod | xargs)
./run-all-tests.sh
```

## Advanced Usage

### Run Tests in CI/CD

```yaml
# GitHub Actions example
- name: Run Spot Behavior Tests
  env:
    CLUSTER_NAME: ${{ secrets.AKS_CLUSTER_NAME }}
    RESOURCE_GROUP: ${{ secrets.AKS_RESOURCE_GROUP }}
    NAMESPACE: robot-shop
  run: |
    cd tests/spot-behavior
    ./run-all-tests.sh --category 01-pod-distribution
```

### Filter Results

```bash
# Show only failed tests
jq '.tests[] | select(.status == "fail")' results/test_summary.json

# Count passed/failed
jq '.summary' results/test_summary.json
```

### Clean Up

```bash
# Remove old results
rm -rf results/*.json

# Uncordon any manually cordoned nodes
kubectl get nodes -o name | xargs -I {} kubectl uncordon {}
```

## Troubleshooting

### "Cannot connect to cluster"

```bash
# Verify kubectl context
kubectl cluster-info

# Get credentials
az aks get-credentials --resource-group <rg> --name <cluster>
```

### "No pods found in namespace"

```bash
# Deploy Robot Shop
kubectl apply -f ../../manifests/robot-shop/

# Wait for pods to be ready
kubectl get pods -n robot-shop
```

### "VMSS not found"

Ensure the `LOCATION` variable matches your cluster's location:

```bash
# Get cluster location
az aks show -g <rg> -n <cluster> --query location -o tsv

# Export it
export LOCATION=eastus
```

### Tests Timing Out

Increase timeout values in `config.sh`:

```bash
POD_READY_TIMEOUT=300
NODE_READY_TIMEOUT=600
```

## Project Structure

```
spot-behavior/
├── run-all-tests.sh           # Main test runner
├── config.sh                  # Configuration (sources .env)
├── .env.example               # Configuration template
├── .env                       # Your local config (DO NOT COMMIT)
├── lib/
│   ├── common.sh              # Test framework, assertions, kubectl wrappers
│   └── test_runner.sh         # Test discovery and execution
├── categories/
│   ├── 01-pod-distribution/   # 10 tests
│   ├── 02-eviction-behavior/  # 10 tests
│   ├── 03-pdb-enforcement/    # 6 tests
│   ├── 04-topology-spread/    # 5 tests
│   ├── 05-recovery-rescheduling/ # 6 tests
│   ├── 06-sticky-fallback/    # 5 tests
│   ├── 07-vmss-node-pool/     # 6 tests
│   ├── 08-autoscaler/         # 5 tests
│   ├── 09-cross-service/      # 5 tests
│   └── 10-edge-cases/         # 5 tests
└── results/                   # JSON test results (gitignored)
```

## Related Documentation

- **Project Overview**: See `../../CONSOLIDATED_PROJECT_BRIEF.md`
- **Spot Eviction Scenarios**: See `../../docs/SPOT_EVICITION_SCENARIOS.md`
- **SRE Runbook**: See `../../docs/SRE_OPERATIONAL_RUNBOOK.md`
- **Python Test Suite**: See `../spot-behavior-python/README.md` (alternative implementation)
