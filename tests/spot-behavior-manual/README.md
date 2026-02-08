# Manual Spot Behavior Test Scenarios

This directory contains **manual testing procedures** for validating AKS spot node behavior, eviction handling, and workload resilience.

## Overview

`TEST_SCENARIOS.md` is a **comprehensive manual testing checklist** with 63 test scenarios across 10 categories. These tests are designed to be executed manually by testers, SREs, or QA engineers to validate spot node behavior before production deployment.

**Use this when:**
- 🧪 Validating a new cluster before production rollout
- 📋 Performing acceptance testing for spot node configuration
- 🔍 Investigating specific behavior or issues
- 📊 Comparing behavior across different cluster configurations
- 🎓 Learning how spot nodes work in practice

**For automated testing**, use:
- `../spot-behavior/` - Bash automated test suite
- `../spot-behavior-python/` - Python/pytest automated test suite

## Prerequisites

1. **Deployed AKS cluster** with spot node pools
2. **kubectl** configured with cluster access
   ```bash
   kubectl cluster-info
   ```
3. **Azure CLI** (for VMSS/infrastructure tests)
   ```bash
   az login
   az account set --subscription <your-subscription>
   ```
4. **Robot Shop workload** deployed
   ```bash
   kubectl apply -f ../../manifests/robot-shop/
   ```
5. **jq** for JSON processing (optional but helpful)
   ```bash
   sudo apt-get install jq  # Ubuntu/Debian
   brew install jq          # macOS
   ```

## Configuration

### Step 1: Set Your Environment Variables

The test scenarios reference specific cluster values. Before running tests, export your cluster configuration:

```bash
# Create a quick reference file
cat > test-env.sh <<'EOF'
#!/bin/bash
# Manual test environment configuration

# Cluster identity
export CLUSTER_NAME="aks-spot-prod"
export RESOURCE_GROUP="rg-aks-spot"
export NAMESPACE="robot-shop"
export LOCATION="australiaeast"

# Azure subscription
export SUBSCRIPTION_ID="your-subscription-id"

# Quick aliases for common commands
alias kns='kubectl -n $NAMESPACE'
alias kget='kubectl get -n $NAMESPACE'
alias kdesc='kubectl describe -n $NAMESPACE'
EOF

# Load the configuration
source test-env.sh
```

### Step 2: Verify Configuration

```bash
# Verify cluster connectivity
kubectl cluster-info

# Verify namespace exists
kubectl get namespace $NAMESPACE

# Verify spot nodes exist
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot

# Verify Robot Shop is deployed
kubectl get pods -n $NAMESPACE
```

### Step 3: Adapt Commands for Your Environment

All kubectl commands in `TEST_SCENARIOS.md` use hardcoded values:
- Namespace: `robot-shop`
- Cluster: `aks-spot-prod`
- Resource Group: `rg-aks-spot`

**Replace these with your actual values** when running commands.

**Example from TEST_SCENARIOS.md:**
```bash
# Original command
kubectl get pods -n robot-shop -l app=web -o wide

# Adapted for your environment
kubectl get pods -n $NAMESPACE -l app=web -o wide
```

**Or use the alias:**
```bash
# After sourcing test-env.sh
kns get pods -l app=web -o wide
```

## Running Manual Tests

### 1. Open TEST_SCENARIOS.md

```bash
# Open in your preferred editor/viewer
code TEST_SCENARIOS.md              # VS Code
cat TEST_SCENARIOS.md | less        # Terminal viewer
open TEST_SCENARIOS.md              # macOS default app
```

### 2. Navigate to a Test Category

The document is organized into 10 categories:

| Category | Tests | Duration | Type |
|----------|-------|----------|------|
| 01 - Pod Distribution | 10 | 5 min | Read-only |
| 02 - Eviction Behavior | 10 | 15 min | Destructive |
| 03 - PDB Enforcement | 6 | 10 min | Destructive |
| 04 - Topology Spread | 5 | 8 min | Destructive |
| 05 - Recovery & Rescheduling | 6 | 12 min | Destructive |
| 06 - Sticky Fallback | 5 | 10 min | Destructive |
| 07 - VMSS & Node Pool | 6 | 5 min | Read-only |
| 08 - Autoscaler | 5 | 15 min | Mixed |
| 09 - Cross-Service | 5 | 10 min | Destructive |
| 10 - Edge Cases | 5 | 15 min | Destructive |

### 3. Execute Test Steps

Each test scenario provides:
- **Objective**: What the test validates
- **Steps**: Commands to run (adapt namespace/cluster names)
- **Expected Results**: Checklist of outcomes
- **Evidence**: What to capture (screenshots, logs, metrics)

**Example: DIST-001 (Stateless services on spot nodes)**

```bash
# Step 1: Load your environment
source test-env.sh

# Step 2: Check web service pods
kubectl get pods -n $NAMESPACE -l app=web -o wide

# Step 3: Get node priority for each pod
for pod in $(kubectl get pods -n $NAMESPACE -l app=web -o name); do
  node=$(kubectl get $pod -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
  priority=$(kubectl get node $node -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}')
  echo "$pod -> $node ($priority)"
done

# Step 4: Verify priority is "spot"
# ✓ Check the box in TEST_SCENARIOS.md if successful
```

### 4. Document Results

For each test, check off the expected results boxes:
- ✅ Pass: `- [x] Expected outcome achieved`
- ❌ Fail: `- [ ] Expected outcome NOT achieved` (add notes)

**Capture evidence:**
```bash
# Create evidence directory
mkdir -p evidence/

# Screenshot of pod distribution
kubectl get pods -n $NAMESPACE -o wide > evidence/DIST-001-pods.txt

# Node labels
kubectl get nodes --show-labels > evidence/DIST-001-nodes.txt
```

## Test Types

### Read-Only Tests (Safe)

Categories: 01 (Pod Distribution), 07 (VMSS/Node Pool)

- ✅ Safe to run in production
- ✅ No disruption to workloads
- ✅ Quick validation

**Run these first** to verify baseline configuration.

### Destructive Tests (Caution)

Categories: 02-06, 08-10

- ⚠️ Drain nodes
- ⚠️ Delete pods
- ⚠️ Trigger autoscaler events
- ⚠️ May cause temporary disruption

**Prerequisites before running:**
- Maintenance window scheduled
- PDBs configured (`minAvailable: 1`)
- Replica count > 1 for critical services
- Monitoring/alerting enabled

## Quick Reference: Common Commands

### Pod Distribution

```bash
# List all pods with node assignments
kubectl get pods -n $NAMESPACE -o wide

# Count pods per node pool
kubectl get pods -n $NAMESPACE -o wide | awk '{print $7}' | sort | uniq -c

# Get spot nodes
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot

# Check pod tolerations
kubectl get pod <pod-name> -n $NAMESPACE -o jsonpath='{.spec.tolerations}' | jq
```

### Node Operations

```bash
# Drain a spot node (simulates eviction)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --grace-period=35

# Cordon a node (prevent new pods)
kubectl cordon <node-name>

# Uncordon a node (allow scheduling)
kubectl uncordon <node-name>
```

### VMSS Operations

```bash
# List VMSS for cluster
az vmss list -g MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION} -o table

# Get VMSS instances
az vmss list-instances -n <vmss-name> -g <vmss-rg> -o table

# Check VMSS priority
az vmss show -n <vmss-name> -g <vmss-rg> --query priority -o tsv
```

### Autoscaler

```bash
# Get cluster autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100

# Get autoscaler configmap
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml

# Check priority expander config
kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o yaml
```

### Service Health

```bash
# Check all Robot Shop services
kubectl get svc -n $NAMESPACE

# Test web frontend connectivity
kubectl port-forward -n $NAMESPACE svc/web 8080:8080
# Open http://localhost:8080

# Check service endpoints
kubectl get endpoints -n $NAMESPACE
```

## Tracking Test Progress

### Option 1: Markdown Checklist

Edit `TEST_SCENARIOS.md` directly and check off boxes:

```markdown
**Expected Results:**
- [x] web has >= 1 pod on a spot node  ✅ PASS
- [x] cart has >= 1 pod on a spot node  ✅ PASS
- [ ] catalogue has >= 1 pod on a spot node  ❌ FAIL - all on standard
```

### Option 2: Spreadsheet Tracking

Create a tracking spreadsheet:

| Test ID | Test Name | Status | Notes | Tester | Date |
|---------|-----------|--------|-------|--------|------|
| DIST-001 | Stateless on spot | PASS | All 8 services verified | Alice | 2026-02-08 |
| DIST-002 | Stateful not on spot | PASS | MongoDB confirmed on standard | Alice | 2026-02-08 |
| EVICT-001 | Pod reschedule < 60s | FAIL | Took 85s, investigating | Bob | 2026-02-08 |

### Option 3: Test Report Template

```markdown
# Spot Behavior Test Report

**Date**: 2026-02-08
**Tester**: Alice Smith
**Cluster**: aks-spot-prod
**Environment**: Production

## Summary
- Total Tests: 63
- Passed: 58
- Failed: 3
- Skipped: 2

## Failed Tests
- EVICT-001: Pod reschedule exceeded 60s (actual: 85s)
- PDB-003: PDB violation during rapid eviction
- RECV-004: Ghost node persisted for 5 minutes

## Recommendations
1. Reduce `scale_down_unready` from 3m to 2m
2. Increase PDB `minAvailable` for critical services
3. Investigate zone 2 spot capacity issues
```

## Troubleshooting

### "Cannot connect to cluster"

```bash
# Re-authenticate
az login
az account set --subscription <subscription-id>

# Get credentials
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --overwrite-existing
```

### "Namespace not found"

```bash
# Create namespace
kubectl create namespace robot-shop

# Deploy Robot Shop
kubectl apply -f ../../manifests/robot-shop/
```

### "No spot nodes found"

```bash
# Verify spot node pools exist
az aks nodepool list \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --query "[?priority=='Spot'].name" -o table

# Check if nodes are ready
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot
```

### "Commands don't match my cluster"

**Problem**: Commands in TEST_SCENARIOS.md reference `robot-shop` namespace

**Solution**: Replace with your namespace:
```bash
# Quick find/replace
sed 's/robot-shop/my-namespace/g' TEST_SCENARIOS.md > my-test-scenarios.md

# Or use environment variables
export NAMESPACE="my-namespace"
kubectl get pods -n $NAMESPACE  # Instead of hardcoded namespace
```

## Best Practices

1. **Start with Read-Only Tests** (Categories 01, 07)
   - Validate baseline configuration
   - No risk of disruption

2. **Run Destructive Tests During Maintenance Windows**
   - Schedule downtime
   - Notify stakeholders
   - Enable verbose logging

3. **Document Everything**
   - Take screenshots
   - Save command outputs to files
   - Note any unexpected behavior

4. **Test in Order**
   - Follow category sequence (01 → 10)
   - Each category builds on previous validation

5. **Verify Prerequisites**
   - Before each category, verify cluster state
   - Ensure all pods are healthy
   - Check autoscaler is not in cooldown

6. **Cleanup After Tests**
   - Uncordon any manually cordoned nodes
   - Verify all pods are running
   - Check for pending pods

## Automated Alternative

If manual testing is too time-consuming, use the automated test suites:

```bash
# Bash automated tests (same scenarios)
cd ../spot-behavior
source .env
./run-all-tests.sh

# Python/pytest automated tests
cd ../spot-behavior-python
export $(cat .env | xargs)
pytest -v
```

See their respective README.md files for setup instructions.

## Related Documentation

- **Automated Tests (Bash)**: `../spot-behavior/README.md`
- **Automated Tests (Python)**: `../spot-behavior-python/README.md`
- **Spot Eviction Scenarios**: `../../docs/SPOT_EVICITION_SCENARIOS.md`
- **SRE Operational Runbook**: `../../docs/SRE_OPERATIONAL_RUNBOOK.md`
- **Project Overview**: `../../CONSOLIDATED_PROJECT_BRIEF.md`

## Contributing

Found an issue with a test scenario? Have suggestions for additional tests?

1. Document the issue in `TEST_SCENARIOS.md`
2. Create a new test scenario using the existing format
3. Update the test count and duration estimates
4. Submit a pull request

## Summary

`spot-behavior-manual/` provides:
- ✅ **63 manual test scenarios** for comprehensive validation
- ✅ **Checklist format** for tracking progress
- ✅ **Evidence templates** for documentation
- ✅ **10 categories** covering all spot node behaviors
- ✅ **Estimated durations** (~105 minutes total)

Perfect for acceptance testing, validation, and learning about AKS spot node behavior!
