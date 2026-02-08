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

## Configuration

Tests are configured via environment variables. Create a `.env` file (not committed) from the template:

```bash
cd tests
cp .env.example .env
# Edit .env with your settings
```

### Available Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| `RUN_INTEGRATION_TESTS` | `false` | Set to `true` to enable Azure deployment tests |
| `TEST_AZURE_LOCATION` | `australiaeast` | Azure region for test resources |
| `TEST_TERRAFORM_DIR` | `../terraform/environments/prod` | Path to Terraform environment |
| `TEST_TERRAFORM_BINARY` | `terraform` | Terraform binary to use |
| `TEST_MAX_RETRIES` | `3` | Retries for flaky Azure operations |
| `TEST_RETRY_DELAY` | `5s` | Delay between retries |
| `TEST_DEPLOYMENT_TIMEOUT` | `30m` | Max deployment time |
| `TEST_RG_PREFIX` | `rg-terratest` | Prefix for test resource groups |
| `TEST_CLUSTER_PREFIX` | `aks-test` | Prefix for test cluster names |
| `TEST_SKIP_DESTROY` | `false` | Skip `terraform destroy` (for debugging) |
| `TEST_VERBOSE` | `false` | Enable verbose test output |

### Loading Configuration

**Option 1: Load from .env file**
```bash
export $(cat .env | xargs)
go test -v -timeout 30m ./...
```

**Option 2: Set inline**
```bash
RUN_INTEGRATION_TESTS=true TEST_AZURE_LOCATION=eastus go test -v ./...
```

**Option 3: Export individually**
```bash
export RUN_INTEGRATION_TESTS=true
export TEST_AZURE_LOCATION=westeurope
export ARM_SUBSCRIPTION_ID="your-sub-id"
go test -v -timeout 30m ./...
```

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
cp .env.example .env
# Edit .env with your Azure subscription details

# Load configuration and run
export $(cat .env | xargs)
go test -v -timeout 30m ./...
```

### Run Specific Test

```bash
# Run only module validation tests
go test -v -run TestAksSpotModuleValidation

# Run specific integration test with custom region
TEST_AZURE_LOCATION=westus2 go test -v -run TestAksSpotIntegration
```

### Debug Failed Tests (Skip Cleanup)

```bash
# Keep Azure resources after test failure for investigation
TEST_SKIP_DESTROY=true go test -v -run TestAksSpotIntegration

# Manually clean up later
az group delete --name rg-terratest-<unique-id> --yes
```

## Test Structure

```
tests/
├── go.mod                        # Go module definition
├── doc.go                        # Package documentation
├── config.go                     # Test configuration loader
├── .env.example                  # Configuration template (commit this)
├── .env                          # Your local config (DO NOT commit)
├── aks_spot_module_test.go       # Unit tests for aks-spot-optimized
├── aks_spot_integration_test.go  # Integration tests (Azure deployment)
└── README.md                     # This file
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Terratest

on: [push, pull_request]

jobs:
  unit-tests:
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

  integration-tests:
    runs-on: ubuntu-latest
    # Only run on main branch or manual trigger
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-go@v5
        with:
          go-version: '1.21'

      - uses: hashicorp/setup-terraform@v3

      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Run Integration Tests
        env:
          RUN_INTEGRATION_TESTS: true
          ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
          ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
          TEST_AZURE_LOCATION: australiaeast
          TEST_MAX_RETRIES: 5
        run: |
          cd tests
          go mod tidy
          go test -v -timeout 60m ./...
```

### Azure DevOps Example

```yaml
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

stages:
- stage: UnitTests
  jobs:
  - job: Terratest
    steps:
    - task: GoTool@0
      inputs:
        version: '1.21'

    - task: TerraformInstaller@0
      inputs:
        terraformVersion: '1.5.0'

    - script: |
        cd tests
        go mod tidy
        go test -v -timeout 10m ./...
      displayName: 'Run Unit Tests'

- stage: IntegrationTests
  dependsOn: UnitTests
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - job: DeployAndTest
    steps:
    - task: AzureCLI@2
      inputs:
        azureSubscription: 'Azure Service Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          cd tests
          export RUN_INTEGRATION_TESTS=true
          export TEST_AZURE_LOCATION=australiaeast
          go mod tidy
          go test -v -timeout 60m ./...
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
