# Azure Implementation Plan: Cloud-Native Build & Scan Pipeline

## Objective
Replicate the local "Container Image Evaluation" workflow (Build, Scan, Report) using Azure Container Apps (ACA) and Azure Storage.

## Current State (Feature Branch)
- **Infrastructure**: ACA Environment, ACR, Storage (File Share), Log Analytics.
- **Build Method**: ACA Jobs running `kaniko` to build/push images from a zipped source in Azure Storage.
- **Current Limits**: 
  - Hardcoded app paths (`python`, `node`) don't match our `apps/` structure.
  - No scanning (Trivy/Grype) or reporting logic.
  - No orchestration script.

## Proposed Architecture
1.  **Source Management**:
    - Script `deploy_source.sh` to zip `apps/` and `image_evaluation/dockerfiles` and upload to Azure File Share.
2.  **Build Jobs** (Existing, Modified):
    - Update `aca_job` definitions in Terraform to map to `apps/java-app`, `apps/python-app` etc.
    - Use `Kaniko` to build and push to ACR (`aca_acr`).
3.  **Scanner Jobs** (New):
    - New ACA Job definitions using `anchore/grype` and `aquasec/trivy` images.
    - Mounts Azure File Share to write JSON results.
4.  **Reporting Job** (New):
    - A specialized Job (Python/Bash) that reads the JSONs from the File Share and generates `ARCHITECTURAL_REPORT.md`.
5.  **AKS/ACA Deployment** (Runtime Test):
    - Optional: Deploy the built images to ACA execution environments to verify startup.

## Implementation Steps
1.  **Refactor Terraform**:
    - Update `env/dev/main.tf` to reflect correct `apps/*` paths.
    - Add `scanner_job` modules for each language.
2.  **Develop Orchestration Scripts**:
    - `scripts/azure_build_and_scan.sh`: Automates zipping, uploading, and triggering jobs via `az containerapp job start`.
3.  **Validation**:
    - Execute the pipeline and retrieve the report from Azure Storage.

## Decision on "AKS":
The user mentioned "reporting to be done in AKS". Given the branch context (`aca-java-build`), valid "No CI/CD" constraints, and the suitability of ACA Jobs for batch tasks (Build/Scan), **we will proceed with ACA Jobs for the Pipeline**. If runtime validation is required, we can add a deployment step to AKS or ACA. For now, the priority is the *Evaluation Report* parity.
