# Cloud Ops AKS Spot Migration Kit

Add spot node pools to existing AKS clusters using `az` CLI. Designed for Cloud Ops teams managing 200+ clusters without Terraform.

## Prerequisites

- **Azure CLI** (`az`) >= 2.50 — [Install](https://aka.ms/install-azure-cli)
- **kubectl** — [Install](https://kubernetes.io/docs/tasks/tools/)
- **jq** — for JSON processing in validation scripts
- Azure subscription with AKS cluster access (Contributor role)
- `az login` completed

## Quick Start

```bash
# 1. Configure
cp .env.example .env
# Edit .env — at minimum set CLUSTER_NAME, RESOURCE_GROUP, LOCATION

# 2. Load config
export $(cat .env | xargs)

# 3. Run (use --dry-run first!)
./add-spot-pools.sh --dry-run            # Preview spot pool creation
./update-autoscaler-profile.sh --dry-run  # Preview autoscaler changes
./deploy-priority-expander.sh --dry-run   # Preview ConfigMap
./validate-spot-setup.sh                  # Check everything
```

## Configuration

Copy `.env.example` to `.env` and edit. Required fields:

| Variable | Description | Example |
|----------|-------------|---------|
| `CLUSTER_NAME` | AKS cluster name | `aks-nonprod-team1` |
| `RESOURCE_GROUP` | Resource group containing the cluster | `rg-aks-nonprod` |
| `LOCATION` | Azure region | `australiaeast` |

All other settings have sensible defaults matching the Terraform module. See `.env.example` for the complete list with inline documentation.

### Customizing Pools

Override individual pool settings via environment variables:

```bash
# Change VM size for a specific pool
POOL_VM_SIZE_spotgeneral1=Standard_D8s_v5

# Change zone assignment
POOL_ZONES_spotmemory1=1

# Change max node count
POOL_MAX_spotcompute=15

# Use completely different pool names
SPOT_POOLS=myspot1,myspot2,myspot3
POOL_VM_SIZE_myspot1=Standard_D4s_v5
POOL_ZONES_myspot1=1
POOL_VM_FAMILY_myspot1=general
POOL_PRIORITY_myspot1=10
# ... etc for each pool
```

## Step-by-Step Migration

### Step 1: Add Spot Pools

```bash
# Preview what will be created
./add-spot-pools.sh --dry-run

# Add all configured spot pools
./add-spot-pools.sh

# Or add a single pool first to test
./add-spot-pools.sh --pool spotmemory1
```

The script is **idempotent** — it skips pools that already exist.

### Step 2: Update Autoscaler Profile

```bash
# Preview autoscaler settings
./update-autoscaler-profile.sh --dry-run

# Apply settings (shows current profile for rollback reference)
./update-autoscaler-profile.sh
```

This changes the autoscaler expander from `random` (default) to `priority`, and tunes timeouts for spot workloads.

### Step 3: Deploy Priority Expander

```bash
# Preview the ConfigMap that will be applied
./deploy-priority-expander.sh --dry-run

# Apply the ConfigMap
./deploy-priority-expander.sh
```

The priority expander tells the autoscaler which pools to prefer:
- **Priority 5:** Memory-optimized spot pools (E-series) — lowest eviction risk
- **Priority 10:** General/compute spot pools (D/F-series)
- **Priority 20:** Standard on-demand pools — fallback
- **Priority 30:** System pool — never used for user workloads

### Step 4: Validate

```bash
# Run all 6 validation checks
./validate-spot-setup.sh

# Get machine-readable output
./validate-spot-setup.sh --json
```

Checks performed:
1. Spot pools exist and are in `Succeeded` state
2. Spot nodes are `Ready` (if any are running)
3. Node labels (`workload-type=spot`, `priority=spot`) are correct
4. Spot taint (`kubernetes.azure.com/scalesetpriority=spot:NoSchedule`) applied
5. Autoscaler profile has `expander=priority`, correct scan interval and timeouts
6. Priority expander ConfigMap exists in `kube-system`

## Rollback

To completely reverse the migration:

```bash
# Preview rollback
./rollback-spot-pools.sh --dry-run

# Full rollback: drain nodes, delete pools, revert autoscaler
./rollback-spot-pools.sh

# Rollback a single pool
./rollback-spot-pools.sh --pool spotgeneral1
```

The rollback script:
1. Cordons and drains all nodes in each spot pool (respects PDBs)
2. Deletes spot node pools via `az aks nodepool delete`
3. Removes the priority expander ConfigMap
4. Reverts the autoscaler expander to `random`

## All Script Options

Every script supports:

| Flag | Description |
|------|-------------|
| `--dry-run` | Print commands without executing |
| `--yes`, `-y` | Skip confirmation prompts |
| `--help`, `-h` | Show help |

Additional flags per script:

| Script | Flag | Description |
|--------|------|-------------|
| `add-spot-pools.sh` | `--pool NAME` | Add only one pool |
| `rollback-spot-pools.sh` | `--pool NAME` | Remove only one pool |
| `validate-spot-setup.sh` | `--json` | JSON output |

## Troubleshooting

### "Pool already exists" when adding

This is expected — the script is idempotent. It logs a warning and skips existing pools.

### Pool stuck in "Creating" state

AKS pool creation can take 5-10 minutes. Run `validate-spot-setup.sh` after a few minutes. If stuck longer than 15 minutes, check:

```bash
az aks nodepool show -g $RESOURCE_GROUP --cluster-name $CLUSTER_NAME -n <pool-name> --query provisioningState
```

### "VM size not available in this region"

The default VM sizes may not be available in every Azure region. Check availability:

```bash
az vm list-sizes --location $LOCATION --query "[?name=='Standard_D4s_v5']" -o table
```

Override with available sizes in `.env`:

```bash
POOL_VM_SIZE_spotgeneral1=Standard_D4ds_v5  # Use Dds instead of Ds
```

### Nodes not scheduling pods after migration

Ensure your workloads have the spot toleration:

```yaml
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule
```

### Autoscaler not preferring spot pools

Verify the priority expander ConfigMap exists and the autoscaler is set to `priority`:

```bash
kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o yaml
az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query autoScalerProfile.expander
```

### Rollback taking too long

Node drain respects Pod Disruption Budgets. If PDBs block the drain, the `--timeout` (default 60s) will expire and the drain will proceed with `--force`. Check for tight PDBs:

```bash
kubectl get pdb -A
```

## FAQ

**Q: Do I need to modify my application deployments?**
A: Yes — add spot tolerations and preferably node affinity to workloads that should run on spot nodes. See `docs/DEVOPS_TEAM_GUIDE.md` for templates.

**Q: What happens if all spot nodes get evicted?**
A: The autoscaler will scale up the standard (on-demand) pool to absorb the workload. This is Layer 2 of the resilience design.

**Q: Will pods automatically move back to spot when capacity recovers?**
A: No — this is the "sticky fallback" problem. Deploy the Kubernetes Descheduler to periodically rebalance pods back to spot nodes. See `docs/SPOT_EVICITION_SCENARIOS.md`.

**Q: Can I use different pool configurations for different clusters?**
A: Yes — every setting is configurable via `.env`. Create one `.env` per cluster.

**Q: Is this compatible with future Terraform adoption?**
A: Yes. Pools are labeled `managed-by=az-migration` to distinguish them from Terraform-managed resources. When ready for Terraform, import them with `terraform import`.
