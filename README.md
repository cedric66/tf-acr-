# Azure Container Apps Build Pipeline

This repository contains Terraform code to provision an Azure infrastructure for building a custom Java base image (using Chainguard images) with a sample Spring Boot application. The build process runs inside an Azure Container Apps Job using Kaniko.

## Repository Structure

- `app/`: Contains the sample Spring Boot application source code and Dockerfile.
- `terraform/`: Contains Terraform configuration.
  - `modules/`: Reusable Terraform modules.
    - `acr`: Azure Container Registry.
    - `aca`: Azure Container Apps Environment and Build Job.
    - `storage`: Azure Storage Account and File Share.
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

### Triggering the Build

The Container Apps Job is configured for manual triggering. You can trigger it using the Azure CLI:

```bash
az containerapp job start \
  --name caj-dev-build-image \
  --resource-group rg-dev-aca-build
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
| **File Share** | `build-context` | Mounted by the build job to access source code. |
| **Container Apps Environment** | `cae-dev-build` | Hosting environment for the build job. |
| **Container Apps Job** | `caj-dev-build-image` | Runs the Kaniko build process. |
| **User Assigned Identity** | `caj-dev-build-image-identity` | Identity for the job to push to ACR. |

## Estimated Cost (Monthly)

*Note: These are rough estimates based on East US pricing. Actual costs may vary.*

| Resource | SKU / Config | Estimated Cost |
| :--- | :--- | :--- |
| **Azure Container Registry** | Basic | ~$5.00 / month |
| **Azure Storage Account** | Standard LRS (File Share) | ~$0.06 / GB / month (Usage dependent) |
| **Container Apps Environment** | Consumption | Free for first 180k vCPU-s & 360k GiB-s |
| **Container Apps Job** | 0.5 vCPU, 1 GiB Mem | Free (unless heavy usage > free tier) |
| **Bandwidth** | Outbound Data Transfer | First 100 GB / month free |
| **Total Estimated** | | **~$5.50 / month** |

*The Container Apps Environment and Job often fall within the free tier for low-frequency build tasks.*
