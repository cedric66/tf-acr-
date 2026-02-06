# Robot Shop Deployment

Instana Robot Shop - polyglot microservices demo for testing AKS spot pool resilience.

## Prerequisites

- AKS cluster deployed with spot and standard node pools
- `kubectl` configured
- `helm` v3 installed

## Deployment

```bash
# Add Helm repo
helm repo add robot-shop https://instana.github.io/robot-shop/
helm repo update

# Create namespace
kubectl create namespace robot-shop

# Deploy with custom values
helm upgrade --install robot-shop robot-shop/robot-shop \
  --namespace robot-shop \
  -f values-prod.yaml

# Verify
kubectl get pods -n robot-shop -o wide
```

## Uninstall

```bash
helm uninstall robot-shop -n robot-shop
kubectl delete namespace robot-shop
```

## Workload Distribution

| Component | Target Pool | Replicas | Spread |
|-----------|-------------|----------|--------|
| web | Spot | 3 | Zone spread |
| cart, catalogue | Spot | 2 | Zone spread |
| mongodb, mysql | Standard | 1 | Dedicated |
| redis | Standard | 1 | Dedicated |
| rabbitmq | Standard | 1 | Dedicated |

## Verify Distribution

```bash
# Check pods per zone
kubectl get pods -n robot-shop -o json | \
  jq -r '.items[] | "\(.metadata.name) \(.spec.nodeName)"'

# Check node pool distribution
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot
kubectl get nodes -l kubernetes.azure.com/scalesetpriority!=spot
```
