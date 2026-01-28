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

### 2. Azure Node Termination Handler (NTH)

**File:** `node-termination-handler.yaml`

NTH proactively drains nodes before Azure evicts them, providing graceful shutdown for applications. Without NTH, pods only get 30 seconds notice.

#### Features

- Polls Azure Scheduled Events API every 5 seconds
- Cordons and drains nodes on termination notice
- Sends webhook notifications to Slack/Teams
- Runs with `system-node-critical` priority

#### Installation

```bash
# Create webhook secret (optional - for Slack/Teams notifications)
kubectl create secret generic nth-webhook-secret \
  --from-literal=webhook-url='YOUR_SLACK_OR_TEAMS_WEBHOOK_URL' \
  -n node-termination-handler

# Deploy NTH
kubectl apply -f node-termination-handler.yaml
```

#### Verification

```bash
# Check DaemonSet status
kubectl get daemonset -n node-termination-handler

# View logs for a specific node
kubectl logs -n node-termination-handler -l app.kubernetes.io/name=node-termination-handler
```

---

## Integration with Existing Setup

These components complement the existing AKS Spot optimization:

```
┌─────────────────────────────────────────────────────────────┐
│                    AKS Spot Optimization                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
│  │   Cluster   │    │    VPA      │    │    NTH      │      │
│  │  Autoscaler │    │             │    │             │      │
│  │             │    │  Right-size │    │  Graceful   │      │
│  │  Node       │    │  Pod        │    │  Eviction   │      │
│  │  Scaling    │    │  Resources  │    │  Handling   │      │
│  └─────────────┘    └─────────────┘    └─────────────┘      │
│         │                  │                  │              │
│         └──────────────────┼──────────────────┘              │
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
- [Azure Node Termination Handler](https://github.com/microsoft/node-termination-handler)
- [Microsoft AKS Spot Node Pool Documentation](https://learn.microsoft.com/en-us/azure/aks/spot-node-pool)
