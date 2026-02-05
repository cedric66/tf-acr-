# CLAUDE.md - AI Assistant Guide for tf-acr

## Project Overview

This is an **Infrastructure as Code (IaC) project** for optimizing Azure Kubernetes Service (AKS) costs using Spot Virtual Machines. The goal is to achieve 50-58% cloud spend reduction while maintaining 99.9% availability through multi-pool spot VM orchestration with intelligent fallback to on-demand nodes.

**License:** Apache 2.0
**Cloud Platform:** Microsoft Azure
**Primary IaC Tool:** Terraform (>=1.5.0) with AzureRM provider (>=3.80.0)
**Approach:** Cluster Autoscaler with Priority Expander and diversified VMSS-backed spot node pools. Karpenter/NAP is **not** in scope (prototype archived under `terraform/prototypes/_archived/aks-nap/`).

## Repository Structure

```
tf-acr-/
├── .agent/                          # AI agent workflows and skills
│   ├── skills/terraform_skill/      # Terraform dry-run and Kind simulation guide
│   └── workflows/                   # Code review and maintenance workflows
├── docs/                            # Comprehensive project documentation (~20 docs)
├── monitoring/dashboards/           # Grafana JSON dashboards
├── scripts/                         # Python DevOps toolkit and bash utilities
├── terraform/
│   ├── environments/prod/           # Production environment configuration
│   ├── modules/aks-spot-optimized/  # Core reusable Terraform module
│   └── prototypes/_archived/        # Archived prototypes (Karpenter NAP - not in scope)
├── tests/                           # Go + Terratest test suite
├── CONSOLIDATED_PROJECT_BRIEF.md    # Single source of truth for project status
├── kind-config.yaml                 # Local Kind cluster config for testing
└── spot-deployment.yaml             # Example spot-tolerant K8s deployment
```

## Key Technologies & Versions

| Component | Version | Notes |
|-----------|---------|-------|
| Terraform | >=1.5.0 | IaC orchestration |
| AzureRM Provider | >=3.80.0 | Azure resource management |
| Kubernetes | 1.28+ | Default cluster version, 1.29+ supported |
| Go | 1.21+ (toolchain 1.24.3) | Test framework runtime |
| Terratest | 0.46.7 | Infrastructure testing library |
| Python | 3.x | DevOps toolkit scripts |
| Kind | latest | Local Kubernetes simulation |

## Build & Test Commands

### Terraform Validation (no Azure credentials needed)

```bash
cd terraform/modules/aks-spot-optimized
terraform init
terraform validate
```

### Unit Tests (no Azure credentials needed)

```bash
cd tests
go mod tidy
go test -v -timeout 10m ./...
```

### Integration Tests (requires Azure credentials)

```bash
cd tests
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export ARM_TENANT_ID="<tenant-id>"
export RUN_INTEGRATION_TESTS=true
go test -v -timeout 30m ./...
```

### Run Specific Test

```bash
cd tests
go test -v -run TestAksSpotModuleValidation   # Module unit tests
```

### Local Spot Simulation with Kind

```bash
kind create cluster --config kind-config.yaml --name spot-sim
kubectl apply -f spot-deployment.yaml
# Simulate eviction with scripts/simulate_spot_contention.sh
kind delete cluster --name spot-sim
```

## Core Terraform Module: `aks-spot-optimized`

**Location:** `terraform/modules/aks-spot-optimized/`

This is the main deliverable. It provisions an AKS cluster with:

- **System pool:** Always on-demand, 3+ nodes, D4s_v5 (runs control-plane components)
- **Standard pools:** On-demand fallback, 2-15 nodes (absorbs spot evictions)
- **Spot pools:** 5 diversified pools across D/E/F VM families and 3 availability zones
- **Priority Expander:** Cost-optimized autoscaler pool selection via ConfigMap
- **Cluster Autoscaler:** Tuned for bursty/spot workloads (20s scan interval, 60s graceful termination)

### Key Files

| File | Purpose |
|------|---------|
| `main.tf` | AKS cluster resource definition |
| `node-pools.tf` | Spot and standard node pool definitions |
| `priority-expander.tf` | Autoscaler priority expander ConfigMap |
| `variables.tf` | All input variables with defaults |
| `outputs.tf` | Module outputs (cluster info, pool details, cost estimates) |
| `templates/` | YAML templates for K8s deployments and ConfigMaps |

### Priority Expander Tiers

Lower number = higher priority (preferred first):
- **5:** Memory-optimized spot pools (E-series) - lowest eviction risk
- **10:** General/compute spot pools (D/F-series)
- **20:** Standard on-demand pools (fallback)
- **30:** System pool (never used for user workloads)

## Spot Eviction Handling

This section describes the complete lifecycle of a spot node eviction and how the system responds.

### What Happens When a Spot Node is Evicted

1. **Azure sends eviction notice** (~30 seconds before termination)
2. **Eviction policy is `Delete`** (`node-pools.tf`) - the node is destroyed, not deallocated
3. **Spot max price is `-1`** (default) - pay up to on-demand price, minimizing price-based evictions
4. **Pods receive SIGTERM** via preStop hook, get 35 seconds for graceful shutdown (`terminationGracePeriodSeconds: 35` in spot-tolerant-deployment template)
5. **Pod is removed from service endpoints immediately** (traffic stops before container stops)
6. **Cluster Autoscaler detects pending pods** and provisions replacement capacity

### Graceful Shutdown Sequence (per pod)

Defined in `templates/spot-tolerant-deployment.yaml.tpl`:
```
T+0s:   Pod marked NotReady, removed from Service endpoints
T+0s:   preStop hook fires: sends SIGTERM to PID 1, sleeps 25s for connection draining
T+25s:  preStop completes
T+35s:  Container killed (SIGKILL) if still running
```

### Autoscaler Response Timeline

Configured in `variables.tf` (autoscaler profile):

| Setting | Value | Purpose |
|---------|-------|---------|
| `expander` | `priority` | Selects pools by priority weight |
| `scan_interval` | `20s` | How often autoscaler checks for pending pods |
| `max_graceful_termination_sec` | `60` | Max time for pod drains during scale-down |
| `scale_down_delay_after_delete` | `10s` | Quick reaction after node deletion/eviction |
| `scale_down_unneeded` | `5m` | Time before removing underutilized nodes |
| `skip_nodes_with_system_pods` | `true` | Protects system pool from scale-down |

### Multi-Layer Resilience

**Layer 1 - Pool diversity** (`node-pools.tf`): 5 spot pools across D/E/F VM families and 3 availability zones reduce the probability of simultaneous eviction across all pools.

**Layer 2 - Priority Expander** (`priority-expander.tf`): Memory-optimized E-series pools (lowest historical eviction rate) are preferred at priority 5. If unavailable, falls back through compute spot (10) → standard on-demand (20).

**Layer 3 - Pod Disruption Budgets** (`templates/spot-tolerant-deployment.yaml.tpl`): `minAvailable: 50%` ensures at least half of replicas survive any disruption event.

**Layer 4 - Topology Spread** (`templates/spot-tolerant-deployment.yaml.tpl`): Three spread constraints distribute pods across zones, pool types (spot vs on-demand), and individual nodes. All use `whenUnsatisfiable: ScheduleAnyway` to avoid scheduling deadlocks.

**Layer 5 - Node Affinity with fallback** (`templates/spot-tolerant-deployment.yaml.tpl`): Pods prefer spot nodes (weight 100) but accept on-demand (weight 50). This is `preferredDuringScheduling` so pods always land somewhere.

### The "Sticky Fallback" Problem and Descheduler Solution

After spot eviction, pods land on standard on-demand nodes. When spot capacity recovers, pods **do not** automatically move back - the Kubernetes scheduler is "one-shot."

**Solution:** Deploy the Kubernetes Descheduler with `RemovePodsViolatingNodeAffinity` strategy. It runs every 5-10 minutes, identifies pods on standard nodes that prefer spot, evicts them, and lets the scheduler place them back on cheaper spot capacity. See `docs/SPOT_EVICITION_SCENARIOS.md` for full details and test manifests.

### Eviction Scenarios Summary

| Scenario | What Happens | Outcome |
|----------|-------------|---------|
| Single spot pool evicted | Pods reschedule to other spot pools | Handled by Cluster Autoscaler |
| All spot pools evicted | Pods fall back to standard on-demand pool | Autoscaler scales up standard pool |
| Spot capacity recovers | Pods stay on standard (sticky fallback) | Descheduler moves pods back to spot |
| Regional capacity event | PDBs limit disruption, standard pools absorb | Multi-zone spread reduces blast radius |

### Monitoring Evictions

Grafana dashboards in `monitoring/dashboards/`:

- **aks-spot-overview.json**: Eviction rate (per hour), pod distribution (spot vs on-demand), pending pods, active spot node count
- **aks-autoscaler-status.json**: Autoscaler health, scale-up/down events, unschedulable pod count, pool-level node counts

Key alerts (from `docs/SRE_OPERATIONAL_RUNBOOK.md`):

| Alert | Severity | Threshold |
|-------|----------|-----------|
| High eviction rate | P2 | >20 evictions/hour |
| All spot pools empty | P1 | 0 spot nodes |
| Pods pending >5 min | P2 | >5 pods |
| PDB violations | P1 | Any violation |

## Code Conventions

### Terraform Naming

- Resources: `{type}-{environment}-{descriptor}` (e.g., `rg-aks-prod`, `vnet-aks-prod`)
- Node pools: Type-based names (e.g., `system`, `spotgen1`, `spotmemory1`, `stdworkload`)
- Variables: `snake_case`, booleans use `enable_*` or `*_enabled` prefix
- Complex variables: Use `object({})` types with `optional()` defaults
- Tags: Always include `Environment`, `Project`, `ManagedBy`, `CostCenter`, `LastUpdated`

### Terraform Template Escaping

In files processed by `templatefile()` or `templatestring()`:
- Bash variables `${var}` MUST be escaped as `$${var}`
- Terraform interpolation `${var}` stays unescaped
- `awk '{print $1}'` becomes `awk '{print $$1}'`

### Node Pool Labels

```hcl
managed-by       = "terraform"
cost-optimization = "spot-enabled"
node-pool-type   = "system" | "user"
workload-type    = "standard" | "spot"
priority         = "on-demand" | "spot" | "system"
vm-family        = "general" | "compute" | "memory"
```

### Test Naming

Go test functions follow: `TestModuleName_WhatItTests` (e.g., `TestAksSpotModuleValidation`)

## Agent Workflows

### Code Review (`.agent/workflows/code-review.md`)

When reviewing Terraform or cloud-init changes, check for:
1. Template string escaping (bash `$${var}` vs Terraform `${var}`)
2. Deprecated Azure resources (use `azurerm_linux_virtual_machine`, not `azurerm_virtual_machine`)
3. Cloud-init ordering (users before runcmd, mounts before services)
4. Identity best practices (prefer Managed Identity over keys/secrets)
5. Timezone format correctness per Azure resource type

### Maintenance (`.agent/workflows/maintenance.md`)

After completing changes that affect scope, architecture, metrics, or roadmap:
1. Update `CONSOLIDATED_PROJECT_BRIEF.md` with current state
2. Update the "Last Updated" date
3. Ensure all doc links are valid
4. Use relative paths only (never absolute/system-specific paths)
5. Verify the brief still provides a clear high-level overview

## Documentation Map

| Document | Purpose |
|----------|---------|
| `CONSOLIDATED_PROJECT_BRIEF.md` | Start here - single source of truth |
| `docs/AKS_SPOT_NODE_ARCHITECTURE.md` | Core technical design |
| `docs/SPOT_EVICITION_SCENARIOS.md` | Eviction scenarios, sticky fallback, and Descheduler solution |
| `docs/SRE_OPERATIONAL_RUNBOOK.md` | Incident response procedures |
| `docs/DEVOPS_TEAM_GUIDE.md` | Migration and deployment guide |
| `docs/CHAOS_ENGINEERING_TESTS.md` | Resilience validation scenarios (5 failure modes) |
| `docs/FINOPS_COST_ANALYSIS.md` | Financial modeling and ROI |
| `docs/SECURITY_ASSESSMENT.md` | Threat model and compliance |
| `docs/KUBERNETES_UPGRADE_GUIDE.md` | K8s 1.28 to 1.29+ upgrade path |
| `docs/FLEET_ROLLOUT_STRATEGY.md` | 300+ cluster rollout plan |
| `docs/KIND_SPOT_TESTING.md` | Local Kind-based spot simulation results |
| `docs/SCALED_SPOT_ORCHESTRATION.md` | Multi-cluster spot orchestration at scale |
| `tests/README.md` | Test suite usage guide |

## Important Patterns & Gotchas

1. **Spot pool `spot_max_price = -1`** means "up to on-demand price" - this is the default and recommended setting
2. **Eviction policy is `Delete`** (not `Deallocate`) for spot nodes - nodes are destroyed on eviction
3. **Integration tests** are gated behind `RUN_INTEGRATION_TESTS=true` env var to prevent accidental Azure deployments
4. **`.encrypted/` directory** contains sensitive content; use `scripts/decrypt-repo.sh` to access
5. **No GitHub Actions CI** is configured yet - the `tests/README.md` contains a recommended workflow template
6. **`.terraform.lock.hcl` files** are committed to pin provider versions - do not delete them
7. **Pod Disruption Budgets** should maintain >=50% availability for spot workloads
8. **Karpenter/NAP is archived** - prototype lives in `terraform/prototypes/_archived/aks-nap/` for reference only; do not develop against it
9. **Sticky fallback** - pods do not auto-return to spot nodes after eviction recovery; requires Descheduler (see `docs/SPOT_EVICITION_SCENARIOS.md`)

## Security Considerations

- Never commit `.tfvars`, credentials, or secrets (enforced by `.gitignore`)
- Use `SystemAssigned` Managed Identity (default) over service principal keys
- Azure AD RBAC integration is enabled by default
- Network isolation via Azure VNet with private subnets
- Calico network policy is the default CNI policy

## Scripts Reference

| Script | Language | Purpose |
|--------|----------|---------|
| `scripts/devops_toolkit.py` | Python | Multi-subscription cluster discovery and ACR audit |
| `scripts/discover.py` | Python | Cluster discovery utility |
| `scripts/simulate_spot_contention.sh` | Bash | Kind-based spot eviction chaos testing |
| `scripts/convert_docs_for_word.py` | Python | Convert markdown docs to Word-compatible format |
| `scripts/decrypt-repo.sh` | Bash | Decrypt sensitive repository content |
