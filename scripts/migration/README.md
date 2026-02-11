# AKS Spot Migration Scripts

This directory contains standalone bash scripts to assist with the migration of an existing AKS cluster to use Spot node pools.

## Prerequisites

- **Azure CLI** (v2.50.0+)
- **kubectl** (matched to cluster version)
- **jq** (for JSON processing)
- **bash** (v4.0+)
- Active Azure subscription and permissions to:
  - Read/Write AKS cluster
  - List VM SKUs and Usage (Quota)

## Configuration

The scripts use a centralized configuration pattern. You can configure them using environment variables or by modifying `config.sh`.

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Export variables from `.env` (using your preferred method, e.g., `source .env` if you format it as exports, or use a tool like `dotenv`).
3. Alternatively, the scripts will fallback to defaults defined in `config.sh`.

## Quick Start

### 1. Check SKU Availability
Verify that your chosen VM sizes are available for Spot in your target region:
```bash
./check-spot-availability.sh
```

### 2. Validate Quota
Ensure your subscription has enough vCPU quota to support the planned Spot pools:
```bash
./validate-quota.sh
```

### 3. Audit Workload Readiness
Scan a specific namespace for workloads that are ready for Spot:
```bash
./spot-readiness-audit.sh my-namespace
```

### 4. Run Full Cluster Report
Generate a comprehensive readiness report for the entire cluster:
```bash
./cluster-spot-readiness.sh
```

### 5. Track Migration Progress
Monitor the percentage of pods running on Spot nodes:
```bash
./migration-progress.sh
```

## Troubleshooting

### "Permission Denied"
Ensure scripts are executable:
```bash
chmod +x *.sh
```

### "jq: command not found" or "any() not found"
Ensure `jq` is installed (v1.6+ recommended). Older versions may not support all filter functions used in the audit scripts.

### "Empty results" or "Resource not found"
- Verify your Azure CLI login: `az account show`
- Ensure the `LOCATION` in `.env` or `config.sh` is the short name (e.g., `australiaeast`, not `Australia East`).
- For `kubectl` errors, verify your context: `kubectl config current-context`

### Spot Labels
The scripts rely on the standard AKS label `kubernetes.azure.com/scalesetpriority=spot`. If you are using custom labels for spot nodes, update `cluster-spot-readiness.sh` and `migration-progress.sh` accordingly.

## Safety Mandates
- All scripts use `set -euo pipefail` for safety.
- No scripts perform destructive write operations (delete/update) on the cluster; they are primarily for audit and validation.
- Deployment changes (Phase 1, 3, 4, 5) should be performed via Terraform or manual `az aks` / `kubectl` commands as documented in the [MIGRATION_GUIDE.md](../../docs/MIGRATION_GUIDE.md).
