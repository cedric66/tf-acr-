# Terratest for tf-acr

This directory contains automated tests for the Terraform modules using [Terratest](https://terratest.gruntwork.io/).

## Test Types

| Type | Description | Duration | Requires Azure |
|------|-------------|----------|----------------|
| **Unit Tests** | Validate syntax, plan generation | ~1-2 min | No |
| **Integration Tests** | Deploy to Azure, validate resources | ~15-20 min | Yes |

## Prerequisites

1. **Go 1.18+**
   ```bash
   go version
   ```

2. **Terraform 1.5+**
   ```bash
   terraform version
   ```

3. **Azure CLI (for integration tests)**
   ```bash
   az login
   az account set --subscription <subscription-id>
   ```

> **Note:** The Karpenter NAP prototype tests will log validation errors because `node_provisioning_mode` is a preview feature not yet in the public azurerm provider. These tests pass by design.

## Running Tests

### Unit Tests (No Azure Required)

```bash
cd tests
go mod tidy
go test -v -timeout 10m ./...
```

### Integration Tests (Deploys to Azure)

```bash
cd tests

# Set Azure credentials
export ARM_SUBSCRIPTION_ID="<your-subscription-id>"
export ARM_TENANT_ID="<your-tenant-id>"

# Enable integration tests
export RUN_INTEGRATION_TESTS=true

# Run all tests
go test -v -timeout 30m ./...
```

### Run Specific Test

```bash
# Run only module validation tests
go test -v -run TestAksSpotModuleValidation

# Run only Karpenter tests
go test -v -run TestKarpenter
```

## Test Structure

```
tests/
├── go.mod                        # Go module definition
├── doc.go                        # Package documentation
├── aks_spot_module_test.go       # Unit tests for aks-spot-optimized
├── aks_spot_integration_test.go  # Integration tests (Azure deployment)
├── karpenter_nap_test.go         # Tests for Karpenter NAP prototype
└── README.md                     # This file
```

## CI/CD Integration

Add to GitHub Actions:

```yaml
jobs:
  terratest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-go@v5
        with:
          go-version: '1.21'
          
      - uses: hashicorp/setup-terraform@v3
      
      - name: Run Unit Tests
        run: |
          cd tests
          go mod tidy
          go test -v -timeout 10m ./...
```

## Writing New Tests

1. Create a new `*_test.go` file
2. Import Terratest modules:
   ```go
   import (
       "github.com/gruntwork-io/terratest/modules/terraform"
       "github.com/stretchr/testify/assert"
   )
   ```
3. Follow the naming convention: `TestModuleName_WhatItTests`

## Troubleshooting

### "Azure credentials not found"
```bash
az login
# or set ARM_* environment variables
```

### "Timeout exceeded"
Increase timeout: `go test -timeout 60m ./...`

### "Resource quota exceeded"
Choose a different Azure region or reduce VM sizes in test variables.
