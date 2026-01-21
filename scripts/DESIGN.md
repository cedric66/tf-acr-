# Toolkit Design & Architecture

This document explains the decision logic "brains" behind the scripts.

## 1. Network Auto-Discovery (NAP vs Spot Pools)
The `eligibility-report.sh` script inspects `networkProfile` to determine if Node Autoprovisioning (NAP) is supported.

| Network Plugin | Network Mode | Verdict | Rationale |
|---|---|---|---|
| `azure` | `overlay` | **NAP Compatible** | Native support. Recommended. |
| `cilium` | - | **NAP Compatible** | Native support. Recommended. |
| `azure` | - (legacy) | **Incompatible** | Lacks overlay. Must use Manual Pools. |
| `kubenet` | - | **Incompatible** | Lacks overlay. Must use Manual Pools. |

**Why?** NAP (Karpenter) manages Spot heavily rely on specific CNI capabilities. Incompatible clusters fallback to standard **Cluster Autoscaler (CAS)**.

## 2. SKU Selection Heuristic
The scripts do not hardcode VM sizes. Instead, they dynamically query `az vm list-skus` in the cluster's region.
1. Load `preferred_skus` from `spot-config.yaml`.
2. Filter region SKUs for `LowPriorityCapable == True`.
3. Check `restrictions` array (must be empty).
4. Iterate through preferences and select the **first available, unrestricted** SKU.

## 3. Workload Distribution Logic
Workload migration patches are generated based on `kind` and `replicas`:

| Workload Kind | Default Spot % | Logic |
|---|---|---|
| **Deployment** | 80% | `replicas * 0.8` get Spot affinity, rest Regular. |
| **StatefulSet** | 0% | Excluded to prevent data loss during eviction. |
| **CronJob** | 100% | Ephemeral jobs are perfect candidates. |

**Topology Spread**:
For any deployment with `replicas >= 3`, the script injects a `topologySpreadConstraint` with `maxSkew: 1` on `topology.kubernetes.io/zone`. This prevents all 3+ replicas from landing on a single Spot node/zone.

## 4. Testing Strategy
We use `mock` JSON files to simulate Azure API responses.
- `add-spot-pools.sh --mock file.json` reads local JSON instead of calling `az`.
- `test/run-tests.sh` asserts that the script produces the expected commands for various mock scenarios (e.g., Legacy Network -> Generates CAS commands, NAP Network -> Recommends NAP).
