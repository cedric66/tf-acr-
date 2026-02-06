# Descheduler Deployment

Kubernetes Descheduler for automatic pod rebalancing after spot evictions.

## Purpose

When spot nodes are evicted, pods may become unevenly distributed. The Descheduler:
1. Detects topology spread violations
2. Evicts pods from overloaded nodes
3. Allows kube-scheduler to rebalance

## Deployment

```bash
# Add Helm repo
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
helm repo update

# Deploy
helm upgrade --install descheduler descheduler/descheduler \
  -n kube-system \
  -f values.yaml
```

## Uninstall

```bash
helm uninstall descheduler -n kube-system
```

## Policies Enabled

| Policy | Purpose |
|--------|---------|
| RemovePodsViolatingTopologySpreadConstraint | Rebalance after zone loss |
| RemovePodsViolatingNodeAffinity | Move pods when affinity breaks |
| LowNodeUtilization | Balance underutilized nodes |
