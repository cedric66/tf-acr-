# Terraform usage for Azure Image Evaluation

This configuration references existing infrastructure:
- Resource Group: `rg121`
- ACR: `acr121`
- AKS: `cluster121`

## 1. Setup
```bash
cd terraform
terraform init
```

## 2. Using ACR Tasks
The `main.tf` defines 25 ACR Build Tasks, one for each image variant.
**Important**: ACR Tasks require a Git context. Update the `context_path` in `main.tf` to point to the Git repository where this code resides.

## 3. Manual Build (CLI)
If you prefer not to set up Git context yet, you can trigger builds directly using Azure CLI (bypassing Terraform for the *exec*, but using the infra):

```bash
# Example Loop to build all
az acr login -n acr121
cd ../image_evaluation

for app in java springboot nodejs go python; do
  for prov in chainguard minimus dhi alpine ubi; do
    echo "Building $app/$prov in Azure..."
    az acr build --registry acr121 \
       --image ${app}-${prov}:latest \
       --file dockerfiles/${app}/Dockerfile.${prov} .
  done
done
```
