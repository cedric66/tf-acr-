# Azure Container Apps Build Pipeline

This repository contains Terraform code to provision an Azure infrastructure for building secure, custom base images using Chainguard images and Docker Hardened Images (DHI). It supports building Java, Go, Python, and Node.js applications. The build process runs inside Azure Container Apps Jobs using Kaniko and enforces a secure supply chain by using only private base images.

## Repository Structure

- `app/`: Contains sample applications and Dockerfiles.
  - `java/`: Spring Boot sample (Chainguard).
  - `go/`: Go sample (Chainguard).
  - `python/`: Python sample (Chainguard).
  - `node/`: Node.js sample (Chainguard).
  - `dhi-java/`: Spring Boot sample (Distroless/Hardened).
  - `dhi-go/`: Go sample (Alpine/Distroless).
  - `dhi-python/`: Python sample (Alpine).
  - `dhi-node/`: Node.js sample (Alpine).
- `terraform/`: Contains Terraform configuration.
  - `modules/`: Reusable Terraform modules.
    - `acr`: Azure Container Registry (Private).
    - `aca_env`: Azure Container Apps Environment.
    - `aca_job`: Generic Azure Container Apps Job for building images.
    - `aca_job_import`: Job to import public images to private ACR.
    - `storage`: Azure Storage Account and File Share.
    - `log_analytics`: Log Analytics Workspace (Cost Optimized).
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

### Supply Chain Security: Importing Images

Before running any build jobs, you must populate your private ACR with the required base images. The Terraform configuration creates a dedicated job for this:

```bash
az containerapp job start --name caj-aca-build-dev-eus-import --resource-group rg-aca-build-dev-eus
```

This job uses `crane` to copy images defined in `terraform.tfvars` (e.g., Maven, Chainguard, Alpine, Distroless) from public registries to your private ACR. This ensures all builds consume trusted, private artifacts.

### Triggering Builds

Once images are imported, you can trigger the build jobs. These jobs are configured to pull base images *only* from your private ACR.

**Chainguard Stack:**
```bash
az containerapp job start --name caj-aca-build-dev-eus-java --resource-group rg-aca-build-dev-eus
az containerapp job start --name caj-aca-build-dev-eus-go --resource-group rg-aca-build-dev-eus
az containerapp job start --name caj-aca-build-dev-eus-python --resource-group rg-aca-build-dev-eus
az containerapp job start --name caj-aca-build-dev-eus-node --resource-group rg-aca-build-dev-eus
```

**Docker Hardened Images (DHI) Stack:**
```bash
az containerapp job start --name caj-aca-build-dev-eus-dhi-java --resource-group rg-aca-build-dev-eus
az containerapp job start --name caj-aca-build-dev-eus-dhi-go --resource-group rg-aca-build-dev-eus
az containerapp job start --name caj-aca-build-dev-eus-dhi-python --resource-group rg-aca-build-dev-eus
az containerapp job start --name caj-aca-build-dev-eus-dhi-node --resource-group rg-aca-build-dev-eus
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
| **Container Apps Jobs** | `caj-<app>-<env>-<region>-<type>` | Jobs (Import, Java, Go, Python, Node, DHI-*) to run builds. |
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
*   **Private Supply Chain**: All base images are imported to a private ACR. Builds do not pull from public registries.
*   **TLS 1.2 Enforcement**: Storage Accounts are configured to require `min_tls_version = "TLS1_2"`.
*   **Managed Identity**: Azure Container Apps Jobs use User Assigned Managed Identities to push images to ACR.
*   **Role-Based Access Control (RBAC)**: Least privilege access using `AcrPush` role assignment.
*   **Log Analytics Cost Optimization**: `ContainerLog` table is configured to use the `Basic` plan to reduce retention costs.
*   **Budget Alerts**: A consumption budget is set on the Resource Group to prevent cost overruns.
*   **Non-Root Users**: The application Dockerfiles use Chainguard or Distroless/Alpine images which run as non-root users.
*   **Kubernetes Ready**: All sample apps are configured as long-running servers exposing port 8080.

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
