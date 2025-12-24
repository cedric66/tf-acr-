# Azure Container Apps Build Pipeline

This repository contains Terraform code to provision an Azure infrastructure for building custom base images using Chainguard images. It supports building Java, Go, Python, and Node.js applications. The build process runs inside Azure Container Apps Jobs using Kaniko.

## Repository Structure

- `app/`: Contains sample applications and Dockerfiles.
  - `java/`: Spring Boot sample.
  - `go/`: Go sample.
  - `python/`: Python sample.
  - `node/`: Node.js sample.
- `terraform/`: Contains Terraform configuration.
  - `modules/`: Reusable Terraform modules.
    - `acr`: Azure Container Registry.
    - `aca_env`: Azure Container Apps Environment.
    - `aca_job`: Generic Azure Container Apps Job for building images.
    - `storage`: Azure Storage Account and File Share.
    - `log_analytics`: Log Analytics Workspace.
    - `budget`: Resource Group Budget.
  - `env/dev/`: Environment-specific configuration (Development).
- `scripts/`: Utility scripts.

## Usage

### Prerequisites
- [Terraform](https://www.terraform.io/) installed.
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and logged in (`az login`).
- [Infracost](https://www.infracost.io/) (Optional, for cost estimation).

### Running Terraform

1. Navigate to the development environment directory:
   ```bash
   cd terraform/env/dev
   ```

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Review the plan:
   ```bash
   terraform plan
   ```

4. Apply the configuration:
   ```bash
   terraform apply
   ```

### Triggering Builds

The Container Apps Jobs are configured for manual triggering. You can trigger them using the Azure CLI:

**Java:**
```bash
az containerapp job start --name caj-dev-build-image-java --resource-group rg-dev-aca-build
```

**Go:**
```bash
az containerapp job start --name caj-dev-build-image-go --resource-group rg-dev-aca-build
```

**Python:**
```bash
az containerapp job start --name caj-dev-build-image-python --resource-group rg-dev-aca-build
```

**Node:**
```bash
az containerapp job start --name caj-dev-build-image-node --resource-group rg-dev-aca-build
```

### Cost Estimation

A script is provided to estimate costs using Infracost. You need an Infracost API key.

```bash
export INFRACOST_API_KEY=your_api_key
./scripts/estimate_cost.sh
```

## Resources Created

| Resource Type | Resource Name (Default) | Description |
| :--- | :--- | :--- |
| **Resource Group** | `rg-dev-aca-build` | Container for all resources. |
| **Container Registry** | `acrdevbuild001` | Stores the built Docker images. |
| **Storage Account** | `stdevbuild001` | Stores the source code zip file. |
| **File Share** | `build-context` | Mounted by the build jobs to access source code. |
| **Container Apps Environment** | `cae-dev-build` | Hosting environment for the build jobs. |
| **Log Analytics Workspace** | `cae-dev-build-law` | Centralized logging for ACA environment. |
| **Container Apps Jobs** | `caj-dev-build-image-*` | 4 Jobs (Java, Go, Python, Node) to run builds. |
| **Budget Alert** | `budget-rg-10usd` | Alerts admin@example.com if cost > $10/mo. |

## Estimated Cost (Monthly)

*Note: These are rough estimates based on East US pricing. Actual costs may vary.*

| Resource | SKU / Config | Estimated Cost |
| :--- | :--- | :--- |
| **Azure Container Registry** | Basic | ~$5.00 / month |
| **Azure Storage Account** | Standard LRS (File Share) | ~$0.06 / GB / month (Usage dependent) |
| **Container Apps Environment** | Consumption | Free for first 180k vCPU-s & 360k GiB-s |
| **Log Analytics Workspace** | PerGB2018 | Pay-as-you-go ($2.30/GB ingestion) |
| **Container Apps Jobs** | 0.5 vCPU, 1 GiB Mem | Free (unless heavy usage > free tier) |
| **Bandwidth** | Outbound Data Transfer | First 100 GB / month free |
| **Total Estimated** | | **~$5.50 + Logs Ingestion / month** |
