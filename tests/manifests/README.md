# Spot Optimization Supplementary Manifests

This directory contains Kubernetes manifests for advanced spot instance optimization components identified during the [kubernetes/autoscaler](https://github.com/kubernetes/autoscaler) gap analysis.

## Components

### 1. Vertical Pod Autoscaler (VPA)

**File:** `vertical-pod-autoscaler.yaml`

VPA automatically right-sizes pod CPU and memory requests based on actual usage. This is particularly valuable for spot instances because:

- **Reduces waste:** Over-provisioned pods waste expensive spot capacity
- **Improves bin-packing:** Right-sized pods fit more efficiently on nodes
- **Prevents OOM kills:** Under-provisioned pods get automatic memory increases

#### Deployment Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `Off` | Provides recommendations only | Initial evaluation, CI/CD pipelines |
| `Initial` | Sets resources only at pod creation | Production APIs (no restarts) |
| `Auto` | Full automatic updates (restarts pods) | Batch jobs, fault-tolerant workloads |

#### Installation

```bash
# Install VPA components (CRDs, Admission Controller, Recommender, Updater)
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/download/vertical-pod-autoscaler-1.0.0/vpa-v1.0.0.yaml

# Or use Helm
helm repo add cowboysysop https://cowboysysop.github.io/charts/
helm install vpa cowboysysop/vertical-pod-autoscaler --namespace kube-system

# Deploy VPA resources
kubectl apply -f vertical-pod-autoscaler.yaml
```

#### View Recommendations

```bash
kubectl describe vpa <vpa-name> -n <namespace>
```

---

## Integration with Existing Setup

These components complement the existing AKS Spot optimization:

```
┌─────────────────────────────────────────────────────────────┐
│                    AKS Spot Optimization                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐    ┌─────────────┐                          │
│  │   Cluster   │    │    VPA      │                          │
│  │  Autoscaler │    │             │                          │
│  │             │    │  Right-size │                          │
│  │  Node       │    │  Pod        │                          │
│  │  Scaling    │    │  Resources  │                          │
│  └─────────────┘    └─────────────┘                          │
│         │                  │                                 │
│         └──────────────────┼─────────────────────────────────┘
│                            │                                 │
│                  ┌─────────▼─────────┐                       │
│                  │   Spot Nodes      │                       │
│                  │  (E-series, D-series)                     │
│                  └───────────────────┘                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Related Documentation

- [Gap Analysis Report](/docs/gap-analysis/kubernetes_autoscaler_gap_analysis.md)
- [AKS Spot Node Architecture](/docs/AKS_SPOT_NODE_ARCHITECTURE.md)
- [Principal Engineer Audit](/docs/PRINCIPAL_ENGINEER_AUDIT.md)

---

## References

- [Kubernetes VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Microsoft AKS Spot Node Pool Documentation](https://learn.microsoft.com/en-us/azure/aks/spot-node-pool)
