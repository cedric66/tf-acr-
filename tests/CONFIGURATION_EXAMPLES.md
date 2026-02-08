# Test Configuration Examples

This document provides common test configuration scenarios for different use cases.

## Quick Start

```bash
# 1. Copy the example configuration
cp .env.example .env

# 2. Edit with your settings (minimal required changes)
# - Set ARM_SUBSCRIPTION_ID
# - Set ARM_TENANT_ID
# - Set RUN_INTEGRATION_TESTS=true (if running integration tests)

# 3. Run tests
./run-tests.sh
```

## Common Scenarios

### Scenario 1: Local Development (Unit Tests Only)

**Purpose:** Validate Terraform syntax and module structure without Azure deployment.

**Configuration (.env):**
```bash
# Azure credentials - not needed for unit tests
# ARM_SUBSCRIPTION_ID=
# ARM_TENANT_ID=

# Disable integration tests
RUN_INTEGRATION_TESTS=false

# Optional: customize paths
TEST_TERRAFORM_DIR=../terraform/modules/aks-spot-optimized
```

**Run:**
```bash
./run-tests.sh
# OR
go test -v -timeout 10m ./...
```

---

### Scenario 2: Full Integration Tests (Australia East)

**Purpose:** Deploy and test AKS cluster in Australia East region.

**Configuration (.env):**
```bash
# Azure credentials (required)
ARM_SUBSCRIPTION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ARM_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Enable integration tests
RUN_INTEGRATION_TESTS=true

# Azure region
TEST_AZURE_LOCATION=australiaeast

# Resource naming
TEST_RG_PREFIX=rg-terratest
TEST_CLUSTER_PREFIX=aks-test

# Timeouts for slower regions
TEST_MAX_RETRIES=3
TEST_DEPLOYMENT_TIMEOUT=30m
```

**Run:**
```bash
./run-tests.sh integration
# OR
go test -v -timeout 60m ./...
```

---

### Scenario 3: Multi-Region Testing (West Europe)

**Purpose:** Test deployment in a different Azure region.

**Configuration (.env):**
```bash
ARM_SUBSCRIPTION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ARM_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
RUN_INTEGRATION_TESTS=true

# Test in West Europe instead
TEST_AZURE_LOCATION=westeurope

# Adjust timeouts for region with slower provisioning
TEST_MAX_RETRIES=5
TEST_DEPLOYMENT_TIMEOUT=45m
```

**Run:**
```bash
./run-tests.sh integration
```

---

### Scenario 4: Debugging Failed Tests

**Purpose:** Keep Azure resources after test failure for manual investigation.

**Configuration (.env):**
```bash
ARM_SUBSCRIPTION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ARM_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
RUN_INTEGRATION_TESTS=true
TEST_AZURE_LOCATION=australiaeast

# Skip destroy to inspect resources
TEST_SKIP_DESTROY=true

# Enable verbose output
TEST_VERBOSE=true
```

**Run:**
```bash
./run-tests.sh TestAksSpotIntegration
```

**Cleanup later:**
```bash
# List test resource groups
az group list --query "[?starts_with(name, 'rg-terratest')].name" -o table

# Delete specific test resources
az group delete --name rg-terratest-abc123 --yes --no-wait
```

---

### Scenario 5: CI/CD Pipeline (GitHub Actions)

**Purpose:** Run tests in GitHub Actions with secrets.

**GitHub Secrets:**
- `ARM_SUBSCRIPTION_ID`
- `ARM_TENANT_ID`
- `ARM_CLIENT_ID` (if using service principal)
- `ARM_CLIENT_SECRET` (if using service principal)

**Workflow (.github/workflows/test.yml):**
```yaml
name: Integration Tests

on:
  push:
    branches: [main]
  pull_request:

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
          TEST_MAX_RETRIES: 5
          TEST_DEPLOYMENT_TIMEOUT: 60m
        run: |
          cd tests
          go mod tidy
          go test -v -timeout 90m ./...
```

---

### Scenario 6: Testing Different Terraform Directories

**Purpose:** Test against a custom Terraform environment or module.

**Configuration (.env):**
```bash
ARM_SUBSCRIPTION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ARM_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
RUN_INTEGRATION_TESTS=true

# Test against dev environment instead of prod
TEST_TERRAFORM_DIR=../terraform/environments/dev

# OR test the module directly
# TEST_TERRAFORM_DIR=../terraform/modules/aks-spot-optimized
```

**Run:**
```bash
./run-tests.sh integration
```

---

### Scenario 7: Running Specific Test Suites

**Purpose:** Run only spot node pool tests, not the full suite.

**Configuration (.env):**
```bash
ARM_SUBSCRIPTION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ARM_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
RUN_INTEGRATION_TESTS=true
TEST_AZURE_LOCATION=australiaeast
```

**Run specific tests:**
```bash
# Only node pool tests
./run-tests.sh TestAksSpotNodePools

# Only diversity tests
./run-tests.sh TestAksNodePoolDiversity

# All spot-related tests
./run-tests.sh "TestAksSpot*"
```

---

## Environment Variable Reference

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `RUN_INTEGRATION_TESTS` | bool | `false` | `true` |
| `TEST_AZURE_LOCATION` | string | `australiaeast` | `westeurope`, `eastus` |
| `TEST_TERRAFORM_DIR` | path | `../terraform/environments/prod` | `../terraform/environments/dev` |
| `TEST_TERRAFORM_BINARY` | path | `terraform` | `/usr/local/bin/terraform` |
| `TEST_MAX_RETRIES` | int | `3` | `5` |
| `TEST_RETRY_DELAY` | duration | `5s` | `10s`, `1m` |
| `TEST_DEPLOYMENT_TIMEOUT` | duration | `30m` | `60m`, `90m` |
| `TEST_RG_PREFIX` | string | `rg-terratest` | `rg-ci-test` |
| `TEST_CLUSTER_PREFIX` | string | `aks-test` | `aks-ci` |
| `TEST_SKIP_DESTROY` | bool | `false` | `true` |
| `TEST_VERBOSE` | bool | `false` | `true` |

## Tips

### 1. Override Single Variables

Don't edit `.env` for one-off changes:

```bash
# Test in a different region just once
TEST_AZURE_LOCATION=eastus ./run-tests.sh integration
```

### 2. Multiple Configurations

Create environment-specific files:

```bash
# Development config
.env.dev

# CI/CD config
.env.ci

# Production validation config
.env.prod
```

Load with:
```bash
cp .env.dev .env
./run-tests.sh integration
```

### 3. Parallel Testing

Run multiple test suites in parallel with different configs:

```bash
# Terminal 1: Test Australia East
TEST_AZURE_LOCATION=australiaeast ./run-tests.sh integration

# Terminal 2: Test West Europe
TEST_AZURE_LOCATION=westeurope ./run-tests.sh integration
```

### 4. Cost Optimization

Skip cleanup only for failed tests:

```bash
# Add to .env or export
TEST_SKIP_DESTROY=true

# Only keep resources if test fails
if ! ./run-tests.sh integration; then
    echo "Test failed - resources preserved for debugging"
    echo "Clean up manually when done"
else
    echo "Test passed - resources cleaned up automatically"
fi
```
