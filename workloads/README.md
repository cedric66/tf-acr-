# Workloads Directory

Isolated workload deployments for AKS cluster testing.

## Directory Structure

```
workloads/
├── robot-shop/           # E-commerce microservices demo
│   ├── values-prod.yaml  # Helm overrides for prod
│   └── README.md         # Deployment instructions
├── descheduler/          # Auto-rebalancing for spot evictions
│   ├── values.yaml       # Descheduler config
│   └── README.md
└── README.md             # This file
```

## Deployment Order

1. **Deploy Descheduler first** (handles spot evictions)
2. **Deploy Robot Shop** (test workload)

## Quick Start

```bash
# 1. Descheduler
cd descheduler && ./deploy.sh

# 2. Robot Shop
cd robot-shop && ./deploy.sh
```

## Verification

After deployment, verify workload distribution:

```bash
# Check pod distribution across nodes
kubectl get pods -n robot-shop -o wide

# Check zone distribution
kubectl get pods -n robot-shop -o custom-columns=\
'NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.spec.nodeName'
```
