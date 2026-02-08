# Test Configuration Guide

This document provides an overview of test configuration across all test suites in this repository.

## Overview

All test suites now use **environment variables** instead of hardcoded values, making them:
- ✅ **Portable** - Run against any cluster without code changes
- ✅ **CI/CD Ready** - Easy integration with GitHub Actions, Azure DevOps
- ✅ **Multi-Environment** - Maintain separate configs for dev/staging/prod
- ✅ **Secure** - `.env` files are gitignored (never commit secrets)

## Test Suites

This repository contains **four test frameworks**:

| Suite | Language | Purpose | Tests | Location |
|-------|----------|---------|-------|----------|
| **Terratest** | Go | Infrastructure validation | 6 | `tests/` |
| **Spot Behavior (Bash)** | Bash | Runtime behavior tests | 50+ | `tests/spot-behavior/` |
| **Spot Behavior (Python)** | Python | Runtime behavior tests (pytest) | 50+ | `tests/spot-behavior-python/` |
| **Manual Tests** | Mixed | Ad-hoc validation | Various | `tests/spot-behavior-manual/` |

## Quick Start

Each test suite follows the same pattern:

```bash
# 1. Navigate to test directory
cd tests/                          # Or tests/spot-behavior/ or tests/spot-behavior-python/

# 2. Copy example configuration
cp .env.example .env

# 3. Edit with your cluster details
nano .env
# Set: CLUSTER_NAME, RESOURCE_GROUP, etc.

# 4. Load configuration
export $(cat .env | xargs)

# 5. Run tests
./run-tests.sh                     # Terratest
# OR
./run-all-tests.sh                 # Bash spot tests
# OR
pytest -v                          # Python spot tests
```

---

## 1. Terratest (Go) - Infrastructure Tests

**Location**: `tests/`

### Purpose
Validates Terraform module syntax, deployment, and resource configuration **without requiring a live cluster**.

### Configuration Variables

| Variable | Default | Used For |
|----------|---------|----------|
| `RUN_INTEGRATION_TESTS` | `false` | Enable Azure deployment tests |
| `TEST_AZURE_LOCATION` | `australiaeast` | Azure region |
| `TEST_TERRAFORM_DIR` | `../terraform/environments/prod` | Terraform environment path |
| `TEST_TERRAFORM_BINARY` | `terraform` | Terraform executable |
| `TEST_MAX_RETRIES` | `3` | Retry count for flaky Azure ops |
| `TEST_RETRY_DELAY` | `5s` | Delay between retries |
| `TEST_DEPLOYMENT_TIMEOUT` | `30m` | Max deployment time |
| `TEST_RG_PREFIX` | `rg-terratest` | Resource group name prefix |
| `TEST_CLUSTER_PREFIX` | `aks-test` | Cluster name prefix |
| `TEST_SKIP_DESTROY` | `false` | Skip cleanup (for debugging) |
| `TEST_VERBOSE` | `false` | Verbose output |

### Quick Start

```bash
cd tests
cp .env.example .env

# Edit .env with your Azure subscription
nano .env

# Run unit tests (no Azure deployment)
./run-tests.sh

# Run integration tests (deploys to Azure)
./run-tests.sh integration
```

### Examples

```bash
# Test in different region
TEST_AZURE_LOCATION=westus2 ./run-tests.sh integration

# Debug failed deployment (skip cleanup)
TEST_SKIP_DESTROY=true ./run-tests.sh TestAksSpotIntegration

# Run specific test
./run-tests.sh TestAksSpotNodePoolAttributes
```

**Documentation**: See `tests/README.md` and `tests/CONFIGURATION_EXAMPLES.md`

---

## 2. Spot Behavior Tests (Bash)

**Location**: `tests/spot-behavior/`

### Purpose
Validates **runtime behavior** of deployed AKS clusters with spot nodes:
- Pod distribution across zones and pools
- Graceful eviction and rescheduling
- PDB enforcement
- Autoscaler behavior
- Service continuity during disruptions

### Configuration Variables

| Variable | Default | Used For |
|----------|---------|----------|
| `CLUSTER_NAME` | `aks-spot-prod` | AKS cluster name |
| `RESOURCE_GROUP` | `rg-aks-spot` | Azure resource group |
| `NAMESPACE` | `robot-shop` | Kubernetes namespace |
| `RESULTS_DIR` | `./results` | JSON results output directory |

### Quick Start

```bash
cd tests/spot-behavior
cp .env.example .env

# Edit with your cluster details
nano .env

# Load configuration
source .env

# Run all tests
./run-all-tests.sh

# Run specific category (read-only, safe)
./run-all-tests.sh --category 01-pod-distribution
```

### Examples

```bash
# List all tests without running
./run-all-tests.sh --dry-run

# Run single test
./run-all-tests.sh --test DIST-001

# Run eviction tests (DESTRUCTIVE - drains nodes)
./run-all-tests.sh --category 02-eviction-behavior

# Test multiple clusters
source .env.dev && ./run-all-tests.sh --category 01-pod-distribution
source .env.prod && ./run-all-tests.sh --category 01-pod-distribution
```

**Documentation**: See `tests/spot-behavior/README.md`

---

## 3. Spot Behavior Tests (Python)

**Location**: `tests/spot-behavior-python/`

### Purpose
**Python/pytest port** of the bash test suite with better IDE support, type hints, and debugging.

### Configuration Variables

Same as bash version:

| Variable | Default | Used For |
|----------|---------|----------|
| `CLUSTER_NAME` | `aks-spot-prod` | AKS cluster name |
| `RESOURCE_GROUP` | `rg-aks-spot` | Azure resource group |
| `NAMESPACE` | `robot-shop` | Kubernetes namespace |
| `RESULTS_DIR` | `./results` | JSON results output directory |

### Quick Start

```bash
cd tests/spot-behavior-python

# Setup virtual environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Configure
cp .env.example .env
nano .env
export $(cat .env | xargs)

# Run all tests
pytest -v

# Run specific category
pytest -v categories/test_01_pod_distribution.py
```

### Examples

```bash
# Run tests matching pattern
pytest -v -k "pdb"

# Generate HTML report
pytest --html=report.html --self-contained-html

# Run in parallel
pip install pytest-xdist
pytest -v -n auto

# Run single test
pytest -v categories/test_01_pod_distribution.py::TestPodDistribution::test_DIST_001_pods_on_spot_nodes
```

**Documentation**: See `tests/spot-behavior-python/README.md`

---

## Multi-Environment Strategy

### Strategy 1: Multiple .env Files

```bash
# Create environment-specific configs
tests/
├── .env.example       # Template (committed)
├── .env.dev           # Dev cluster (gitignored)
├── .env.staging       # Staging cluster (gitignored)
└── .env.prod          # Production cluster (gitignored)

# Switch between environments
cp .env.dev .env && ./run-tests.sh
cp .env.prod .env && ./run-tests.sh
```

### Strategy 2: Inline Environment Variables

```bash
# One-off override
CLUSTER_NAME=aks-dev RESOURCE_GROUP=rg-dev ./run-tests.sh

# Test multiple regions in parallel (Terratest)
TEST_AZURE_LOCATION=eastus ./run-tests.sh integration &
TEST_AZURE_LOCATION=westus2 ./run-tests.sh integration &
```

### Strategy 3: CI/CD Secrets

```yaml
# GitHub Actions
env:
  CLUSTER_NAME: ${{ secrets.AKS_CLUSTER_NAME }}
  RESOURCE_GROUP: ${{ secrets.AKS_RESOURCE_GROUP }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
  RUN_INTEGRATION_TESTS: true

# Azure DevOps
variables:
  - group: aks-test-credentials
  - name: CLUSTER_NAME
    value: $(AKS_CLUSTER_NAME)
```

---

## Security Best Practices

### ✅ DO

- ✅ Use `.env.example` as a template (safe to commit)
- ✅ Copy to `.env` and customize locally
- ✅ Store secrets in CI/CD secret managers
- ✅ Use Azure Managed Identities in CI/CD
- ✅ Rotate test credentials regularly

### ❌ DON'T

- ❌ Commit `.env` files with real credentials
- ❌ Hardcode subscription IDs, tenant IDs, or secrets
- ❌ Share `.env` files via Slack/email
- ❌ Use production credentials in dev environments
- ❌ Commit Azure CLI `~/.azure/` directory

---

## CI/CD Examples

### GitHub Actions (Terratest)

```yaml
name: Terratest

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.21'
      - uses: hashicorp/setup-terraform@v3

      - name: Run Tests
        env:
          ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
          ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
          RUN_INTEGRATION_TESTS: true
          TEST_AZURE_LOCATION: australiaeast
        run: |
          cd tests
          ./run-tests.sh integration
```

### GitHub Actions (Spot Behavior - Bash)

```yaml
name: Spot Behavior Tests

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - uses: azure/aks-set-context@v3
        with:
          resource-group: ${{ secrets.AKS_RESOURCE_GROUP }}
          cluster-name: ${{ secrets.AKS_CLUSTER_NAME }}

      - name: Run Read-Only Tests
        env:
          CLUSTER_NAME: ${{ secrets.AKS_CLUSTER_NAME }}
          RESOURCE_GROUP: ${{ secrets.AKS_RESOURCE_GROUP }}
          NAMESPACE: robot-shop
        run: |
          cd tests/spot-behavior
          ./run-all-tests.sh --category 01-pod-distribution
```

### Azure DevOps (Python Tests)

```yaml
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: UsePythonVersion@0
  inputs:
    versionSpec: '3.11'

- task: AzureCLI@2
  inputs:
    azureSubscription: 'Azure Service Connection'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      cd tests/spot-behavior-python
      python3 -m venv venv
      source venv/bin/activate
      pip install -r requirements.txt
      export CLUSTER_NAME=$(AKS_CLUSTER_NAME)
      export RESOURCE_GROUP=$(AKS_RESOURCE_GROUP)
      pytest -v
```

---

## Troubleshooting

### Problem: "Tests fail with hardcoded cluster name"

**Solution**: Ensure you've loaded the `.env` file:

```bash
# Check if variables are set
echo $CLUSTER_NAME
echo $RESOURCE_GROUP

# If empty, load .env
export $(cat .env | xargs)
```

### Problem: "Can't switch between clusters easily"

**Solution**: Use multiple `.env` files:

```bash
# Create configs
cp .env .env.dev
cp .env .env.prod

# Edit each with cluster-specific values

# Switch and run
export $(cat .env.dev | xargs) && ./run-tests.sh
export $(cat .env.prod | xargs) && ./run-tests.sh
```

### Problem: "CI/CD tests fail with authentication errors"

**Solution**: Use Azure service principals or Managed Identity:

```bash
# GitHub Actions: Use azure/login action
# Azure DevOps: Use AzureCLI task with service connection

# Ensure secrets are set:
# - ARM_SUBSCRIPTION_ID
# - ARM_TENANT_ID
# - ARM_CLIENT_ID (if using service principal)
# - ARM_CLIENT_SECRET (if using service principal)
```

### Problem: ".env file accidentally committed"

**Solution**: Remove from history and re-add to .gitignore:

```bash
# Remove from git history
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch tests/.env" \
  --prune-empty --tag-name-filter cat -- --all

# Ensure .gitignore has it
echo "tests/.env" >> .gitignore
git add .gitignore
git commit -m "Add .env to gitignore"
```

---

## Migration Checklist

If you have existing test scripts with hardcoded values:

- [ ] Create `.env.example` with all required variables
- [ ] Update scripts to read from environment variables
- [ ] Add `.env` and `.env.*` to `.gitignore`
- [ ] Test with multiple clusters to verify portability
- [ ] Update CI/CD pipelines to use secrets
- [ ] Document configuration in README
- [ ] Create example configs for dev/staging/prod

---

## Summary

All test suites now follow a **consistent configuration pattern**:

1. **Template**: `.env.example` (committed, no secrets)
2. **Local Config**: `.env` (gitignored, your settings)
3. **Load**: `export $(cat .env | xargs)` or `source .env`
4. **Run**: Test runner script with no hardcoded values

**Benefits:**
- 🔒 **Security**: No secrets in git
- 🚀 **Portability**: Run against any cluster
- 🤖 **Automation**: Easy CI/CD integration
- 🔄 **Flexibility**: Switch environments instantly
- 📝 **Documentation**: Self-documenting via .env.example

For detailed configuration of each test suite, see the respective README files.
