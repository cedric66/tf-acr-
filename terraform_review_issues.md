# Terraform Configuration Review - Issues Found

## Critical Issues

### 1. **Scanner Job Authentication Problem**
**Location**: `terraform/modules/aca_scanner_job/main.tf`
**Issue**: Grype uses managed identity for registry authentication via ACA's registry block, but the init container creates a Docker config.json which won't be used by Grype when scanning `registry:` sources.
**Impact**: Scanner will fail to pull images from private ACR.
**Fix**: Remove DOCKER_CONFIG env and config.json creation. Rely on managed identity.

### 2. **Build Context Path Mismatch**
**Location**: `terraform/modules/aca_job/main.tf` + `scripts/azure_build_and_scan.sh`
**Issue**: 
- Kaniko expects: `/workspace/app/${app_subdirectory}/Dockerfile`
- Script creates: `build_ctx/python-app/...` then zips as `app.zip`
- After unzip: `/workspace/app/build_ctx/python-app/...` (WRONG!)
**Impact**: Kaniko will not find the Dockerfile.
**Fix**: Update script to zip contents directly without the `build_ctx/` wrapper.

### 3. **Missing Outputs in Scanner Module**
**Location**: `terraform/modules/aca_scanner_job/`
**Issue**: No `outputs.tf` file exists.
**Impact**: Cannot reference job details if needed.
**Severity**: Low (not critical for current use case).

### 4. **Hardcoded Image in Scanner Job**
**Location**: `terraform/modules/aca_scanner_job/main.tf:41`
**Issue**: Using `anchore/grype:latest` which may not exist in private registry scenarios.
**Impact**: If internet egress is restricted, job will fail.
**Recommendation**: Import grype to ACR or ensure egress is allowed.

### 5. **Missing Role Assignment Dependencies**
**Location**: Both `aca_job` and `aca_scanner_job` modules
**Issue**: Role assignments (`azurerm_role_assignment.acr_push/pull`) don't have explicit dependency on the job resource.
**Impact**: Terraform may create the job before the role is active, causing runtime failures.
**Fix**: Add `depends_on` to job resource.

### 6. **Unzip Path Issue**
**Location**: `terraform/modules/aca_job/main.tf:76`
**Issue**: `unzip -o /mnt/source/app.zip -d /workspace/app` will create `/workspace/app/build_ctx/...`
**Fix**: Coordinate with script fix #2.

## Medium Priority Issues

### 7. **No Provider Configuration**
**Location**: `terraform/env/dev/`
**Issue**: Missing `provider.tf` or `terraform.tf` block.
**Impact**: Will use default provider settings, may cause issues with backend state.
**Recommendation**: Add explicit provider version constraints.

### 8. **Storage Account Key Exposure**
**Location**: Script uses `az storage file upload` without explicit auth method.
**Issue**: Relies on Azure CLI authentication context.
**Recommendation**: Explicit SAS token or managed identity preferred.

### 9. **Job Parallelism Constraint**
**Location**: All jobs set `parallelism = 1`
**Issue**: Only one execution at a time.
**Impact**: If a job is triggered while another is running, it will queue.
**Recommendation**: Acceptable for PoC, but document this behavior.

## Low Priority Issues

### 10. **No Job Outputs/Monitoring**
**Issue**: No Azure Monitor alerts or structured logging.
**Recommendation**: Add Log Analytics queries for job execution status.

### 11. **Hard-Coded Timeouts**
**Location**: `replica_timeout_in_seconds = 1800`
**Issue**: 30 minutes may be insufficient for large builds.
**Recommendation**: Make this a variable.

### 12. **No Image Tag Strategy**
**Location**: All images use `:latest` tag.
**Issue**: Can't track versions or roll back.
**Recommendation**: Use git commit SHA or build timestamp as tag.
