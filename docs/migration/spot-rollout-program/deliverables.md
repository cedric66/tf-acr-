# DevOps Architect - Key Deliverables

**Program:** AKS Spot Node Pool Implementation (200+ Non-Prod Clusters)
**Role:** DevOps Architect (Technical Lead + Cross-Team Coordinator)
**Date:** 2026-02-09

---

## Deliverables Summary

| # | Deliverable | Phase | Consumers | Format |
|---|-------------|-------|-----------|--------|
| 1 | Cloud Ops Migration Script Kit (`az` CLI) | 0 | Cloud Ops | Shell scripts + .env + README |
| 2 | App Team Workload Modification Kit | 0 | App/DevOps Teams | YAML templates + checklist |
| 3 | Pilot Assessment + Results Report | 0-1 | All teams + leadership | Document |
| 4 | Market-Specific Configuration Matrix | 2 | Cloud Ops | CSV + per-market .env files |
| 5 | Batch Migration Automation with Dry-Run | 2 | Cloud Ops | Shell script |
| 6 | Azure Governance Policies | 2 | Platform team | Azure Policy JSON |
| 7 | Fleet Observability (Dashboards + Alerts + KPIs) | 2 | FinOps + SRE | Azure Workbook + Alert rules |
| 8 | Training Materials (3 audiences) | 2 | All teams | Slide decks + runbooks |
| 9 | Terraform Module Handoff + Review | 2 | Automation Team | Module + integration guide |
| 10 | Wave Rollout Schedule + Go/No-Go Criteria | 3 | All teams | Document + CSV |

---

## Deliverable Details

### 1. Cloud Ops Migration Script Kit (`az` CLI)

**Why this matters:** Cloud Ops manages existing clusters via `az` CLI / portal only. They need tested, rollback-capable scripts - not Terraform.

**Contents:**
```
runbooks/cloudops-migration-kit/
├── README.md                         # Step-by-step usage guide
├── .env.example                      # All configurable parameters
├── add-spot-pools.sh                 # az aks nodepool add (parameterized)
├── update-autoscaler-profile.sh      # az aks update (priority expander + tuned settings)
├── deploy-priority-expander.sh       # kubectl apply ConfigMap
├── validate-spot-setup.sh            # Health checks: pools / nodes / labels / autoscaler
└── rollback-spot-pools.sh            # Drain + delete spot pools + revert autoscaler
```

**Key requirements:**
- All values via environment variables (`${VAR:-default}` pattern)
- Idempotent (safe to re-run)
- Dry-run mode (`--dry-run`) on every script
- Exit codes for automation (0=pass, 1=fail)

---

### 2. App Team Workload Modification Kit

**Why this matters:** App teams need copy-paste YAML to make workloads spot-ready. Low friction = faster adoption.

**Contents:**
```
runbooks/app-team-kit/
├── CHECKLIST.md                      # Spot-ready workload checklist
├── spot-tolerations.yaml             # Toleration + node affinity snippet
├── pdb-template.yaml                 # PodDisruptionBudget (minAvailable: 50%)
├── topology-spread.yaml              # Zone + pool-type + node spread constraints
└── helm-spot-values.yaml             # Helm values overlay for spot scheduling
```

**Key requirements:**
- Works with existing deployments (add to existing manifests, don't replace)
- Checklist covers: graceful shutdown, health probes, statelessness, preStop hooks
- All `whenUnsatisfiable: ScheduleAnyway` (no scheduling deadlocks)

---

### 3. Pilot Assessment + Results Report

**Contents:**
- Pre-migration assessment of 2 pilot clusters (compatibility, quotas, workload classification)
- Post-pilot results: cost savings vs baseline, pod recovery times, eviction behavior, incidents
- Lessons learned and script/runbook adjustments

**Audience:** All teams + leadership (for go/no-go decision on Wave 1)

---

### 4. Market-Specific Configuration Matrix

**Why this matters:** 18 markets, different regions, different spot availability. HK + AU have higher cluster density = higher cannibalization risk.

**Contents:**
```
config/
├── market-region-map.csv             # Market → Azure region mapping
├── region-spot-matrix.csv            # Per-region: SKU availability, quotas, eviction rates
└── markets/
    ├── hk.env                        # HK-specific pool config (extra VM diversity)
    ├── au.env                        # AU-specific pool config (extra VM diversity)
    ├── sg.env                        # ...
    └── <market>.env                  # Per-market .env template
```

---

### 5. Batch Migration Automation

**Why this matters:** Cloud Ops cannot run individual scripts on 200+ clusters. Needs batch execution with safety controls.

**Script:** `scripts/batch-migrate.sh`

**Features:**
- Input: CSV of cluster names + resource groups
- Pre-flight checks per cluster (quota, K8s version, existing pool conflicts)
- Pause between batches (configurable interval)
- Dry-run mode (`--dry-run`)
- Progress logging and failure isolation (one cluster failure doesn't stop the batch)

---

### 6. Azure Governance Policies

**Contents:**
| Policy | Effect | Purpose |
|--------|--------|---------|
| PDB enforcement | Audit | Deployments with replicas > 1 must have a PDB |
| StatefulSet protection | Deny | StatefulSets must have anti-affinity to spot nodes |

**Format:** Azure Policy JSON definitions, ready for `az policy definition create`

---

### 7. Fleet Observability

**Contents:**
- Azure Monitor Workbook with aggregated spot metrics across all clusters
- KPI definitions: savings rate per market, eviction rate, fallback %, pod recovery P95
- Alert rules: >20 evictions/hour, all spot pools empty, pods pending >5 min

**Consumers:** FinOps (cost reporting), SRE (operational health), Leadership (savings dashboards)

---

### 8. Training Materials

| Audience | Topics |
|----------|--------|
| Cloud Ops | Running migration scripts, troubleshooting spot pools, rollback procedures |
| App Teams | Spot-ready workload patterns, graceful shutdown, testing tolerations |
| FinOps | Reading spot dashboards, cost attribution, monthly reporting |

**Format:** Slide deck + hands-on runbook per audience

---

### 9. Terraform Module Handoff

**What:** Hand off existing `terraform/modules/aks-spot-optimized/` to Automation Team so new clusters are created with spot pools from day 1.

**Contents:**
- Module integration guide (how to call the module from their pipeline)
- Variable reference and recommended defaults
- Version pinning policy
- PR review of their pipeline integration

---

### 10. Wave Rollout Schedule

**Structure:**
| Wave | Scope | Duration | Gate |
|------|-------|----------|------|
| 0 (Pilot) | 2 clusters from volunteer app team | 3 weeks | Results report + sign-off |
| 1 (Small markets) | Markets with fewest clusters | 2-3 weeks | No P1/P2 incidents |
| 1 (Medium markets) | Mid-size markets | 2-3 weeks | No P1/P2 incidents |
| 1 (HK + AU) | Highest density markets | 2 weeks | Extra SKU diversity + staggered rollout |

**Go/no-go criteria between batches:**
- Zero P1 incidents from previous batch
- Cost savings within expected range (40-50%)
- Pod recovery P95 < 5 minutes
- No quota exhaustion warnings

---

## Team Responsibility Matrix (RACI)

| Activity | DevOps Architect | Cloud Ops | App Teams | Automation | FinOps |
|----------|:---:|:---:|:---:|:---:|:---:|
| Migration scripts | **R/A** | C | - | - | - |
| Add spot pools (existing) | C | **R** | - | - | - |
| Add spot pools (new) | C | - | - | **R** | - |
| Workload modifications | C | - | **R** | - | - |
| Azure Policy | **R/A** | I | I | I | - |
| Fleet observability | **R** | - | - | - | **A** |
| Cost reporting | I | - | - | - | **R/A** |
| Training | **R/A** | I | I | I | I |
| Wave go/no-go decisions | **R/A** | C | C | I | C |

R = Responsible, A = Accountable, C = Consulted, I = Informed

---

## Timeline Overview

```
W1-2    ████████  Phase 0: Pilot Preparation (scripts, kits, assessments)
W3-5    ██████████████  Phase 1: Pilot Execution (2 clusters, test, validate)
W6-8    ██████████████  Phase 2: Standardize (batch scripts, market configs, training)
W9-16   ████████████████████████████████  Phase 3: Wave 1 Rollout (200+ clusters)
W16+    ████████████████████→  Phase 4: Ongoing Operations
```

**Total estimated duration:** ~16 weeks to full non-prod rollout + ongoing operations
