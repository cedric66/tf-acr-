# Azure Deployment Guide - Container Image Evaluation Pipeline

## Overview
This guide walks you through deploying a cloud-native image build and security scanning pipeline using Azure Container Apps.

## Prerequisites
- Azure CLI installed and authenticated (`az login`)
- Terraform >= 1.5 installed
- Sufficient Azure permissions (Contributor + User Access Administrator on subscription)

## 🔧 Critical Fixes Applied

### Fixed Issues:
1. ✅ Scanner authentication now uses managed identity (no Docker config needed)
2. ✅ Build context zip structure corrected for Kaniko
3. ✅ Added `depends_on` for role assignments to prevent race conditions
4. ✅ Created provider.tf with version constraints
5. ✅ Updated report download path in orchestration script

### Remaining Considerations:

#### Internet Access for Scanner Images
**Issue**: The scanner job pulls `anchore/grype:latest` from Docker Hub.
**Options**:
- **A. Allow internet egress** (Easiest): Ensure your ACA Environment allows outbound traffic.
- **B. Import to ACR** (Recommended for production):
  ```bash
  az acr import \
    --name <your-acr-name> \
    --source docker.io/anchore/grype:latest \
    --image anchore/grype:latest
  ```
  Then update `terraform/modules/aca_scanner_job/main.tf` line 41 to use `${var.acr_login_server}/anchore/grype:latest`

#### Base Image Availability
**Issue**: Dockerfiles reference Chainguard images (`cgr.dev/chainguard/...`).
**Solution**: The Kaniko build will pull these during the build phase. Ensure:
- ACA Environment has internet access, OR
- Pre-import base images to your ACR and update Dockerfile `FROM` statements

## 🚀 Deployment Steps

### Step 1: Initialize Terraform
```bash
cd terraform/env/dev
terraform init
```

### Step 2: Review and Apply Infrastructure
```bash
# Review what will be created
terraform plan

# Apply (you'll be prompted to confirm)
terraform apply
```

**Expected Resources**:
- Resource Group
- Azure Container Registry (ACR)
- Storage Account + File Share
- Log Analytics Workspace
- Container Apps Environment
- 8 Container App Jobs (4 builds + 4 scanners)
- 8 Managed Identities with role assignments

### Step 3: Verify Deployment
```bash
# Check resource group
az group show --name rg-aca-build-dev-eus

# List Container App Jobs
az containerapp job list \
  --resource-group rg-aca-build-dev-eus \
  --query "[].{Name:name, Status:properties.provisioningState}" \
  -o table
```

### Step 4: Run the Pipeline
```bash
cd ../../..  # Back to repo root
chmod +x scripts/azure_build_and_scan.sh
./scripts/azure_build_and_scan.sh
```

**What This Does**:
1. Prepares a unified build context with app code + optimized Dockerfiles
2. Uploads `app.zip` to Azure Files
3. Triggers 4 parallel build jobs (Python, Node, Java, Go)
4. Waits for builds to complete (~5-10 minutes)
5. Triggers 4 parallel scan jobs against the newly built images
6. Downloads scan reports to `azure_reports/`

### Step 5: Verify Results
```bash
ls -lh azure_reports/
# Should contain: scan-python.json, scan-node.json, scan-java.json, scan-go.json
```

## 🔍 Monitoring & Debugging

### View Job Execution Logs
```bash
# List recent executions for a job
az containerapp job execution list \
  --name build-python \
  --resource-group rg-aca-build-dev-eus \
  --query "[].{Name:name, Status:properties.status, StartTime:properties.startTime}" \
  -o table

# Get detailed logs for an execution
EXECUTION_NAME=$(az containerapp job execution list \
  --name build-python \
  --resource-group rg-aca-build-dev-eus \
  --query "[0].name" -o tsv)

az containerapp job logs show \
  --name build-python \
  --resource-group rg-aca-build-dev-eus \
  --execution $EXECUTION_NAME
```

### Common Issues & Solutions

#### Build Job Fails: "Dockerfile not found"
**Cause**: Zip structure mismatch
**Solution**: Verify the zip contains `python-app/Dockerfile` (not `build_ctx/python-app/Dockerfile`)
```bash
unzip -l app.zip | head -20
```

#### Scanner Job Fails: "Failed to pull image"
**Cause**: Managed identity doesn't have AcrPull permission yet
**Solution**: Wait 2-3 minutes for role assignment propagation, then retry:
```bash
az containerapp job start --name scan-python --resource-group rg-aca-build-dev-eus
```

#### "Could not find image in registry"
**Cause**: Build job didn't complete successfully or image name mismatch
**Solution**: Check ACR repository list:
```bash
az acr repository list --name <your-acr-name> -o table
```

## 📊 Next Steps: Generate Report

Once you have the scan JSONs, you can generate the comprehensive report:

```bash
# Option 1: Use the local reporting script (adapt as needed)
python image_evaluation/scripts/generate_report.py azure_reports/

# Option 2: Create a dedicated reporting ACA Job (future enhancement)
```

## 🧹 Cleanup

```bash
cd terraform/env/dev
terraform destroy
```

## 🎯 Production Recommendations

1. **Use Remote State**: Configure Azure Storage backend for Terraform state
2. **Parameterize Image Tags**: Replace `:latest` with versioned tags (git commit SHA)
3. **Add VEX Integration**: Extend scanner jobs to apply VEX documents
4. **Implement Notifications**: Add Azure Monitor alerts for job failures
5. **Cost Optimization**: Use spot instances or serverless scale-to-zero for scanner jobs
6. **Import All Images**: Pre-load base images and scanner images into ACR for air-gapped scenarios

## 📝 Variable Customization

Edit `terraform/env/dev/terraform.tfvars` to override defaults:
```hcl
resource_group_name  = "rg-my-custom-name"
location             = "westus2"
budget_alert_emails  = ["your-email@example.com"]
```
