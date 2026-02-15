# Kubernetes 1.28 → 1.29+ Upgrade Guide for AKS

This document outlines the upgrade path from Kubernetes 1.28 to 1.29+ for our AKS Spot-optimized clusters.

## Overview

| Version | Status | AKS Support End Date | Action Required |
|---------|--------|---------------------|-----------------|
| 1.28 | Current | March 2025 | Upgrade to 1.29 by Feb 2025 |
| 1.29 | Recommended | June 2025 | Target version |
| 1.30 | Latest | TBD | Future target |

## Breaking Changes in 1.29

### 1. API Deprecations

| Deprecated API | Replacement | Impact on This Project |
|----------------|-------------|----------------------|
| `flowcontrol.apiserver.k8s.io/v1beta2` | `v1beta3` | None (not used) |
| `autoscaling/v2beta2` | `autoscaling/v2` | Check HPA manifests |

**Action:** Review any HPA configurations in your workloads.

### 2. Feature Gate Changes

| Feature | Status in 1.29 | Notes |
|---------|---------------|-------|
| `PodDisruptionConditions` | GA | PDBs now set pod conditions |
| `NodeOutOfServiceVolumeDetach` | GA | Faster volume detachment |

**Impact:** Both features are beneficial for Spot node management - no action required.

### 3. Cluster Autoscaler Compatibility

| K8s Version | CA Version Required |
|-------------|-------------------|
| 1.28.x | 1.28.x |
| 1.29.x | 1.29.x |

**Action:** AKS manages the autoscaler version automatically. No manual update needed.

## Pre-Upgrade Checklist

### 1. Validate Current State
```bash
# Check current version
az aks show -g rg-aks-prod -n aks-prod --query kubernetesVersion

# Get available upgrade versions
az aks get-upgrades -g rg-aks-prod -n aks-prod --output table

# Check for deprecated API usage
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
```

### 2. Review Terraform Configuration
Update `kubernetes_version` in `terraform/environments/prod/main.tf`:
```hcl
# Before
kubernetes_version = "1.28"

# After
kubernetes_version = "1.29"
```

### 3. Backup Critical Resources
```bash
# Export all deployments and statefulsets
kubectl get deployments -A -o yaml > deployments-backup.yaml
kubectl get statefulsets -A -o yaml > statefulsets-backup.yaml
kubectl get pdb -A -o yaml > pdb-backup.yaml
```

## Upgrade Procedure

### Option 1: Terraform (Recommended)

1. **Update the version in Terraform:**
   ```hcl
   kubernetes_version = "1.29"
   ```

2. **Plan the change:**
   ```bash
   terraform plan -target=module.aks
   ```

3. **Apply during maintenance window:**
   ```bash
   terraform apply -target=module.aks
   ```

### Option 2: Azure CLI (Manual)

```bash
# Upgrade control plane first
az aks upgrade \
  --resource-group rg-aks-prod \
  --name aks-prod \
  --kubernetes-version 1.29.0 \
  --control-plane-only

# Then upgrade node pools one at a time
az aks nodepool upgrade \
  --resource-group rg-aks-prod \
  --cluster-name aks-prod \
  --name system \
  --kubernetes-version 1.29.0

az aks nodepool upgrade \
  --resource-group rg-aks-prod \
  --cluster-name aks-prod \
  --name stdworkload \
  --kubernetes-version 1.29.0

# Spot pools (can be done in parallel)
az aks nodepool upgrade \
  --resource-group rg-aks-prod \
  --cluster-name aks-prod \
  --name spotgen1 \
  --kubernetes-version 1.29.0 &

az aks nodepool upgrade \
  --resource-group rg-aks-prod \
  --cluster-name aks-prod \
  --name spotgen2 \
  --kubernetes-version 1.29.0 &
```

## Post-Upgrade Validation

### 1. Verify Version
```bash
kubectl version --short
az aks show -g rg-aks-prod -n aks-prod --query kubernetesVersion
```

### 2. Validate Node Pools
```bash
kubectl get nodes -o wide
az aks nodepool list -g rg-aks-prod --cluster-name aks-prod --output table
```

### 3. Check Spot Node Functionality
```bash
# Verify spot nodes are labeled correctly
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot

# Verify spot tolerating pods are scheduled correctly
kubectl get pods -A -o wide | grep spot
```

### 4. Run Integration Tests
```bash
cd tests/
go test -v -timeout 10m -run TestAksSpotNodePoolAttributes
```

## Rollback Procedure

> ⚠️ **AKS does not support automatic rollback**. If issues occur:

1. **Minor Issues:** Cordon affected nodes and wait for autoscaler to replace
2. **Major Issues:** Create a new cluster from Terraform and migrate workloads

## Recommended Timeline

| Date | Action |
|------|--------|
| Week 1 | Test upgrade in dev environment |
| Week 2 | Upgrade staging cluster |
| Week 3 | Monitor staging for issues |
| Week 4 | Upgrade production (maintenance window) |

## Support

- **AKS Upgrade Docs:** https://learn.microsoft.com/en-us/azure/aks/upgrade-cluster
- **K8s 1.29 Changelog:** https://kubernetes.io/blog/2023/12/13/kubernetes-v1-29-release/
- **Internal Contact:** Platform Engineering Team (#platform-engineering)

---
**Last Updated:** 2026-01-27  
**Owner:** Platform Engineering Team
