# 🤖 Robot Shop Spot Node Testing Guide

This guide describes how to use the [Instana Robot Shop](https://github.com/instana/robot-shop) microservices application to test AKS Spot node eviction, failover, and recovery scenarios.

## ✅ Prerequisites

1. An AKS cluster with:
   - A `System` node pool (for control plane components).
   - At least one `Spot` node pool.
   - At least one `Standard` (On-Demand) node pool.
2. `kubectl` configured to access your cluster.
3. `helm` (v3+) installed locally.

---

## 🚀 Deployment

### 1. Add the Robot Shop Helm Repository
```bash
helm repo add robot-shop https://raw.githubusercontent.com/instana/robot-shop/master/K8s/helm
helm repo update
```

### 2. Deploy with Our Custom Values
Use the pre-configured `values.yaml` from this repository to deploy workloads with the correct Spot/Standard affinity:
```bash
helm install robot-shop robot-shop/robot-shop \
  -n robot-shop --create-namespace \
  -f tests/robot-shop-spot-config/values.yaml
```

### 3. Verify Pod Distribution
After deployment, check that stateless services are on Spot nodes and stateful services are on Standard nodes:
```bash
kubectl get pods -n robot-shop -o wide
```
- `web`, `cart`, `catalogue`, `user`, `payment`, `shipping`, `ratings`, `dispatch` → Should prefer **Spot** nodes.
- `mongodb`, `mysql`, `redis`, `rabbitmq` → Should be on **Standard** nodes only.

---

## 🧪 Test Scenarios

These scenarios correspond to those in [docs/SPOT_EVICITION_SCENARIOS.md](SPOT_EVICITION_SCENARIOS.md).

### Scenario 1: Failover (Spot Pool 1 → Spot Pool 2)
**Goal:** Verify pods reschedule to another Spot pool when one is drained.
```bash
# Drain a single Spot node
kubectl drain <spot-node-name> --ignore-daemonsets --delete-emptydir-data
```
**Expected:** Stateless pods migrate to another Spot node (if available) or Standard nodes.

---

### Scenario 2: Fallback (All Spot → Standard)
**Goal:** Simulate total Spot capacity loss.
```bash
# Drain all Spot nodes
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o name | xargs -I {} kubectl drain {} --ignore-daemonsets --delete-emptydir-data
```
**Expected:** Stateless pods migrate to Standard nodes. Stateful pods (already on Standard) are unaffected.

---

### Scenario 3: Recovery (Standard → Spot)
**Goal:** Verify that the Descheduler moves pods back to Spot nodes when capacity returns.

1.  **Uncordon the Spot nodes:**
    ```bash
    kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o name | xargs -I {} kubectl uncordon {}
    ```
2.  **Apply the Descheduler:** (Requires [Kubernetes Descheduler](https://github.com/kubernetes-sigs/descheduler) to be installed)
    ```bash
    kubectl apply -f tests/manifests/descheduler-policy.yaml
    ```

**Expected:** Stateless pods on Standard nodes are gracefully evicted and rescheduled back to the newly available Spot nodes.

---

## 📊 Load Testing

Robot Shop includes a [Locust-based load generator](https://github.com/instana/robot-shop/tree/master/load-gen) to simulate realistic user traffic during eviction tests.

```bash
# Run load generator (adjust HOST to your web service IP/hostname)
kubectl apply -f https://raw.githubusercontent.com/instana/robot-shop/master/K8s/load-gen.yaml
```

Monitor the `cart` and `payment` Prometheus metrics (on `/metrics`) to measure the impact of evictions on transaction success rates.

---

## 🧹 Cleanup

```bash
helm uninstall robot-shop -n robot-shop
kubectl delete namespace robot-shop
```

---
**Last Updated**: 2026-01-27  
**Status**: ✅ Ready for Testing
