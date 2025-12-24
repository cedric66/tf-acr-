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
az containerapp job start --name caj-aca-build-dev-eus-java --resource-group rg-aca-build-dev-eus
```

**Go:**
```bash
az containerapp job start --name caj-aca-build-dev-eus-go --resource-group rg-aca-build-dev-eus
```

**Python:**
```bash
az containerapp job start --name caj-aca-build-dev-eus-python --resource-group rg-aca-build-dev-eus
```

**Node:**
```bash
az containerapp job start --name caj-aca-build-dev-eus-node --resource-group rg-aca-build-dev-eus
```

### Cost Estimation

A script is provided to estimate costs using Infracost. You need an Infracost API key.

```bash
export INFRACOST_API_KEY=your_api_key
./scripts/estimate_cost.sh
```

## Resources Created

| Resource Type | Resource Name Pattern | Description |
| :--- | :--- | :--- |
| **Resource Group** | `rg-<app>-<env>-<region>` | Container for all resources. |
| **Container Registry** | `acr<app><env><region>` | Stores the built Docker images (alphanumeric). |
| **Storage Account** | `st<app><env><region>` | Stores the source code zip file (lowercase alphanumeric). |
| **File Share** | `share-<app>-<env>` | Mounted by the build jobs to access source code. |
| **Container Apps Environment** | `cae-<app>-<env>-<region>` | Hosting environment for the build jobs. |
| **Log Analytics Workspace** | `log-<app>-<env>-<region>` | Centralized logging for ACA environment (Cost Optimized). |
| **Container Apps Jobs** | `caj-<app>-<env>-<region>-<lang>` | Jobs (Java, Go, Python, Node) to run builds. |
| **Budget Alert** | `budget-rg-10usd` | Alerts admin if cost > $10/mo. |

## Naming Conventions

This project follows Azure Naming Conventions:
*   **Resource Group**: `rg-<app>-<env>-<region>`
*   **ACR**: `acr<app><env><region>` (alphanumeric only)
*   **Storage Account**: `st<app><env><region>` (lowercase alphanumeric, 3-24 chars)
*   **ACA Environment**: `cae-<app>-<env>-<region>`
*   **ACA Job**: `caj-<app>-<env>-<region>`
*   **Log Analytics**: `log-<app>-<env>-<region>`
*   **File Share**: `share-<app>-<env>`

## Security Best Practices

The following security practices are implemented in this Terraform configuration:
*   **TLS 1.2 Enforcement**: Storage Accounts are configured to require `min_tls_version = "TLS1_2"`.
*   **Managed Identity**: Azure Container Apps Jobs use User Assigned Managed Identities to push images to ACR.
*   **Role-Based Access Control (RBAC)**: Least privilege access using `AcrPush` role assignment.
*   **Log Analytics Cost Optimization**: `ContainerLog` table is configured to use the `Basic` plan to reduce retention costs.
*   **Budget Alerts**: A consumption budget is set on the Resource Group to prevent cost overruns.
*   **Non-Root Users**: The application Dockerfiles use Chainguard images which typically run as non-root users by default (verified for runtime stages).

## Estimated Cost (Monthly)

*Note: These are rough estimates based on East US pricing. Actual costs may vary.*

| Resource | SKU / Config | Estimated Cost |
| :--- | :--- | :--- |
| **Azure Container Registry** | Basic | ~$5.00 / month |
| **Azure Storage Account** | Standard LRS (File Share) | ~$0.06 / GB / month (Usage dependent) |
| **Container Apps Environment** | Consumption | Free for first 180k vCPU-s & 360k GiB-s |
| **Log Analytics Workspace** | PerGB2018 (Basic Logs) | Ingestion costs (Basic Logs are cheaper than Analytics) |
| **Container Apps Jobs** | 0.5 vCPU, 1 GiB Mem | Free (unless heavy usage > free tier) |
| **Bandwidth** | Outbound Data Transfer | First 100 GB / month free |
| **Total Estimated** | | **~$5.50 + Logs Ingestion / month** |
