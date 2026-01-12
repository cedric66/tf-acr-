# Chaos Engineering Test Scenarios for AKS Spot Node Optimization

**Document Version:** 1.0  
**Created:** 2026-01-12  
**Purpose:** Validate resilience of spot node architecture through controlled failure injection

---

## Test Framework Setup

```bash
# Install Chaos Mesh
kubectl create ns chaos-testing
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh -n chaos-testing

# Install LitmusChaos (alternative)
kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v2.0.0.yaml
```

---

## Failure Case 1: Simultaneous Multi-Pool Spot Eviction

### Scenario Description
**Risk:** Azure evicts multiple spot pools simultaneously during high-demand periods  
**Probability:** 0.5-2% during major Azure capacity events  
**Impact:** Mass pod rescheduling, potential service degradation

### Test Objectives
- Verify standard pool can absorb evicted workloads
- Validate PodDisruptionBudgets maintain minimum availability
- Measure time-to-recovery (TTR)
- Confirm no request failures during eviction

### Test 1.1: Coordinated Spot Pool Node Deletion

```yaml
# chaos-spot-multi-eviction.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: spot-multi-pool-eviction
  namespace: chaos-testing
spec:
  action: pod-kill
  mode: all
  duration: "30s"
  selector:
    namespaces:
      - production
    labelSelectors:
      "kubernetes.azure.com/scalesetpriority": "spot"
  scheduler:
    cron: "@every 1h"
```

**Execution:**
```bash
# Deploy test workload with 12 replicas
kubectl apply -f test-workloads/spot-tolerant-app.yaml

# Verify initial distribution
kubectl get pods -o wide | grep -E "spotgen|stdworkload"

# Inject chaos - kill all spot nodes simultaneously
kubectl apply -f chaos-spot-multi-eviction.yaml

# Monitor rescheduling
watch "kubectl get pods -o wide | grep -E 'Pending|ContainerCreating|Running'"

# Check PDB status
kubectl get pdb -o wide

# Measure recovery time
kubectl get events --sort-by='.lastTimestamp' | grep -E "Scheduled|Started"
```

**Success Criteria:**
- ✅ Zero pods remain Pending >2 minutes
- ✅ Standard pool scales up within 90 seconds
- ✅ PDB maintains minAvailable throughout
- ✅ Application maintains >95% success rate (via metrics)

**Expected Behavior:**
```
T+0s:   Spot pods evicted (6 pods on spot, 6 on standard)
T+5s:   Pods marked Pending, scheduler places on standard nodes
T+15s:  Standard pool autoscaler triggers scale-up
T+90s:  New standard nodes ready
T+120s: All pods Running on standard nodes
```

### Test 1.2: Gradual Spot Pool Degradation

```yaml
# chaos-gradual-spot-loss.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NodeChaos
metadata:
  name: gradual-spot-drain
  namespace: chaos-testing
spec:
  action: node-drain
  mode: fixed-percent
  value: "33"  # Drain 33% of spot nodes every iteration
  duration: "10m"
  selector:
    labelSelectors:
      "kubernetes.azure.com/scalesetpriority": "spot"
  scheduler:
    cron: "@every 5m"
```

**Success Criteria:**
- ✅ Workloads redistribute smoothly across remaining capacity
- ✅ No more than 1 pod disrupted per 30-second window
- ✅ Standard pool gradually absorbs load

---

## Failure Case 2: Autoscaler Delay During Rapid Eviction

### Scenario Description
**Risk:** Standard pool cannot scale fast enough to absorb sudden spot evictions  
**Probability:** 10-15% during rapid eviction events  
**Impact:** Pods stuck in Pending state, capacity shortage

### Test Objectives
- Identify autoscaler response time bottlenecks
- Validate overprovisioning strategy effectiveness
- Test placeholder pod eviction mechanism

### Test 2.1: Instant Capacity Demand Spike

```yaml
# chaos-instant-demand-spike.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: instant-demand-spike
  namespace: chaos-testing
spec:
  mode: all
  selector:
    namespaces:
      - production
    labelSelectors:
      "kubernetes.azure.com/scalesetpriority": "spot"
  stressors:
    cpu:
      workers: 4
      load: 100
  duration: "5m"
---
# Simultaneously, kill spot nodes to force rescheduling
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: spot-instant-kill
  namespace: chaos-testing
spec:
  action: pod-kill
  mode: all
  selector:
    namespaces:
      - production
    labelSelectors:
      "kubernetes.azure.com/scalesetpriority": "spot"
  duration: "10s"
```

**Execution with Measurement:**
```bash
# Deploy overprovisioner pods (low priority)
kubectl apply -f cluster-overprovisioner.yaml

# Monitor autoscaler logs
kubectl logs -f -n kube-system -l app=cluster-autoscaler

# Inject chaos
kubectl apply -f chaos-instant-demand-spike.yaml

# Track pod scheduling latency
kubectl get events -w --field-selector reason=FailedScheduling

# Measure time from Pending to Running
for pod in $(kubectl get pods -l app=test -o name); do
  kubectl get $pod -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].lastTransitionTime}'
done
```

**Success Criteria:**
- ✅ Overprovisioner pods evicted immediately (<5s)
- ✅ Real workloads schedule into freed capacity instantly
- ✅ Autoscaler provisions additional nodes within 2 minutes
- ✅ Maximum pending duration: <30 seconds

### Test 2.2: Autoscaler Performance Under Load

```bash
# Stress test the autoscaler decision loop
# Deploy 100 pods simultaneously to trigger scaling
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: autoscaler-stress-test
spec:
  replicas: 100
  selector:
    matchLabels:
      app: autoscaler-test
  template:
    metadata:
      labels:
        app: autoscaler-test
    spec:
      tolerations:
        - key: kubernetes.azure.com/scalesetpriority
          value: spot
          effect: NoSchedule
      containers:
        - name: pause
          image: gcr.io/google_containers/pause:3.1
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
EOF

# Measure autoscaler scan intervals and decision time
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | grep "scale up"
```

---

## Failure Case 3: Spot VM Unavailability at Scale-Up Time

### Scenario Description
**Risk:** No spot capacity available when autoscaler tries to provision nodes  
**Probability:** 5-10% during peak demand hours  
**Impact:** Pods remain pending, workloads run on expensive standard nodes

### Test Objectives
- Verify priority expander fallback mechanism
- Test multiple VM size diversity strategy
- Validate cost alerts trigger appropriately

### Test 3.1: Simulated Spot Capacity Exhaustion

```bash
# Manually cordon all spot nodes to simulate unavailability
for node in $(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o name); do
  kubectl cordon $node
done

# Mark spot nodes as unschedulable
kubectl annotate nodes -l kubernetes.azure.com/scalesetpriority=spot \
  cluster-autoscaler.kubernetes.io/scale-down-disabled=true

# Deploy workload requiring spot
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-spot-capacity
spec:
  replicas: 50
  selector:
    matchLabels:
      app: test-capacity
  template:
    metadata:
      labels:
        app: test-capacity
    spec:
      tolerations:
        - key: kubernetes.azure.com/scalesetpriority
          value: spot
          effect: NoSchedule
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.azure.com/scalesetpriority
                    operator: In
                    values: [spot]
      containers:
        - name: nginx
          image: nginx:alpine
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
EOF

# Monitor where pods actually schedule
watch "kubectl get pods -o wide | awk '{print \$7}' | sort | uniq -c"
```

**Success Criteria:**
- ✅ Pods schedule to standard nodes within 60 seconds
- ✅ No pods remain Pending for >90 seconds
- ✅ Cost monitoring alert fires for high standard usage
- ✅ Autoscaler logs show priority expander fallback

**Expected Logs:**
```
I0112 08:00:15 priority_expander.go:142] Priority expander: spot-general-1 (priority 10) - skip, no capacity
I0112 08:00:15 priority_expander.go:142] Priority expander: spot-general-2 (priority 10) - skip, no capacity
I0112 08:00:16 priority_expander.go:148] Priority expander: standard-workload (priority 20) - selected
```

### Test 3.2: VM Size Diversity Validation

```bash
# Verify different VM sizes reduce eviction correlation
# Get eviction events for each spot pool
kubectl get events --all-namespaces \
  --field-selector reason=Evicted \
  -o custom-columns=NODE:.source.host,TIME:.lastTimestamp | \
  grep -E "spotgen1|spotgen2|spotcomp" | \
  sort -k2

# Analyze correlation (should be independent)
# Expected: No timestamp clustering across different VM sizes
```

---

## Failure Case 4: Topology Spread Impossible Under Constraints

### Scenario Description
**Risk:** `maxSkew` requirements cannot be satisfied due to capacity/zone constraints  
**Probability:** 2-5% during zone capacity issues  
**Impact:** Pods pending if using `DoNotSchedule`, or imbalanced distribution

### Test Objectives
- Validate `whenUnsatisfiable: ScheduleAnyway` prevents deadlock
- Test topology spread behavior under zone outage
- Verify maxSkew violations trigger alerts

### Test 4.1: Zone Failure Simulation

```yaml
# chaos-zone-failure.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: zone-partition
  namespace: chaos-testing
spec:
  action: partition
  mode: all
  selector:
    labelSelectors:
      "topology.kubernetes.io/zone": "australiaeast-1"
  direction: both
  duration: "10m"
```

**Execution:**
```bash
# Deploy workload with strict zone spread
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zone-spread-test
spec:
  replicas: 9  # 3 zones × 3 pods
  selector:
    matchLabels:
      app: zone-test
  template:
    metadata:
      labels:
        app: zone-test
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway  # CRITICAL: Don't block
          labelSelector:
            matchLabels:
              app: zone-test
      containers:
        - name: nginx
          image: nginx:alpine
EOF

# Inject zone failure
kubectl apply -f chaos-zone-failure.yaml

# Monitor distribution imbalance
kubectl get pods -o wide | \
  awk '{print $7}' | grep australiaeast | sort | uniq -c

# Check for skew violations
kubectl get events | grep "FailedScheduling.*topology spread"
```

**Success Criteria:**
- ✅ Pods schedule despite zone outage (no Pending)
- ✅ Distribution skews to available zones (6-3-0 instead of 3-3-3)
- ✅ Alert fires for topology imbalance
- ✅ When zone recovers, pods rebalance automatically

### Test 4.2: Impossible Constraints Deadlock Test

```yaml
# Test with DoNotSchedule to prove it blocks scheduling
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deadlock-test
spec:
  replicas: 6
  selector:
    matchLabels:
      app: deadlock
  template:
    metadata:
      labels:
        app: deadlock
    spec:
      topologySpreadConstraints:
        - maxSkew: 0  # Impossible to satisfy
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule  # BLOCKS scheduling
          labelSelector:
            matchLabels:
              app: deadlock
      containers:
        - name: nginx
          image: nginx:alpine
```

**Expected Result:**
```
Events:
  Type     Reason            Message
  ----     ------            -------
  Warning  FailedScheduling  0/15 nodes available: 15 node(s) didn't match pod topology spread constraints
```

**Remediation Test:**
```bash
# Change to ScheduleAnyway
kubectl patch deployment deadlock-test -p '
spec:
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 0
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: deadlock
'

# Pods should immediately schedule
kubectl get pods -l app=deadlock -o wide
```

---

## Failure Case 5: Graceful Shutdown Failure (30-Second Window)

### Scenario Description
**Risk:** Application cannot complete graceful shutdown within Azure's 30-second eviction notice  
**Probability:** 100% for long-running transactions or slow shutdown processes  
**Impact:** Request failures, data inconsistency, poor user experience

### Test Objectives
- Validate preStop hook execution
- Test terminationGracePeriodSeconds configuration
- Measure actual shutdown time
- Verify zero request failures during shutdown

### Test 5.1: Abrupt Pod Termination Test

```yaml
# chaos-abrupt-termination.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: abrupt-termination
  namespace: chaos-testing
spec:
  action: pod-kill
  mode: fixed
  value: "1"
  selector:
    namespaces:
      - production
    labelSelectors:
      "app": "api-service"
  duration: "1m"
  gracePeriod: 5  # Shorter than app needs
```

**Test Application (Slow Shutdown):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slow-shutdown-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: slow-shutdown
  template:
    metadata:
      labels:
        app: slow-shutdown
    spec:
      containers:
        - name: app
          image: nginxdemos/hello
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - |
                    echo "Starting graceful shutdown..."
                    # Simulate slow connection draining
                    sleep 40
                    echo "Shutdown complete"
          readinessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 1
      terminationGracePeriodSeconds: 45  # Longer than preStop
```

**Execution:**
```bash
# Deploy slow shutdown app
kubectl apply -f slow-shutdown-app.yaml

# Monitor with load
kubectl run -it --rm load-generator --image=busybox -- sh -c \
  "while true; do wget -q -O- http://slow-shutdown; sleep 0.1; done"

# In another terminal, inject chaos
kubectl apply -f chaos-abrupt-termination.yaml

# Watch shutdown process
kubectl get events -w | grep -E "Killing|Stopped"

# Check if termination completes within grace period
kubectl logs -f <pod-name> --timestamps
```

**Success Criteria:**
- ✅ preStop hook executes completely
- ✅ Pod marked NotReady immediately (removed from service endpoints)
- ✅ No new connections routed to terminating pod
- ✅ Existing connections complete before SIGKILL
- ✅ Load generator experiences <0.1% error rate

### Test 5.2: Load Balancer Synchronization Test

```bash
# Verify pod removed from endpoints before shutdown
watch -n 0.5 "kubectl get endpoints slow-shutdown -o json | jq '.subsets[].addresses | length'"

# In parallel, kill a pod
kubectl delete pod <pod-name> --grace-period=30

# Expected: Endpoint count drops immediately, then pod terminates
```

**Test Script:**
```bash
#!/bin/bash
# shutdown-timing-test.sh

POD_NAME=$(kubectl get pod -l app=slow-shutdown -o jsonpath='{.items[0].metadata.name}')

echo "Starting shutdown timing test for $POD_NAME"

# Mark start time
START=$(date +%s)

# Trigger deletion
kubectl delete pod $POD_NAME --grace-period=45 &

# Monitor readiness
while kubectl get pod $POD_NAME 2>/dev/null | grep -q Running; do
  READY=$(kubectl get pod $POD_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  echo "Pod ready status: $READY"
  sleep 1
done

END=$(date +%s)
DURATION=$((END - START))

echo "Total shutdown time: ${DURATION}s"
[ $DURATION -lt 50 ] && echo "✅ PASS" || echo "❌ FAIL: Exceeded grace period"
```

### Test 5.3: Connection Draining Validation

```python
# connection-draining-test.py
import requests
import time
import threading
from kubernetes import client, config

def make_requests(url, results):
    """Continuously make requests and track failures"""
    while True:
        try:
            r = requests.get(url, timeout=2)
            results['success'] += 1
        except:
            results['failure'] += 1
        time.sleep(0.05)

def kill_pod(pod_name):
    """Delete pod after 10 seconds"""
    time.sleep(10)
    config.load_kube_config()
    v1 = client.CoreV1Api()
    v1.delete_namespaced_pod(pod_name, "production", grace_period_seconds=30)

# Start load
results = {'success': 0, 'failure': 0}
load_thread = threading.Thread(target=make_requests, args=("http://slow-shutdown", results))
load_thread.daemon = True
load_thread.start()

# Kill pod after warmup
kill_thread = threading.Thread(target=kill_pod, args=("slow-shutdown-12345",))
kill_thread.start()

# Monitor for 60 seconds
for i in range(60):
    time.sleep(1)
    total = results['success'] + results['failure']
    error_rate = (results['failure'] / total * 100) if total > 0 else 0
    print(f"T+{i}s: Success={results['success']}, Failures={results['failure']}, Error Rate={error_rate:.2f}%")

# Expected: Error rate <0.1% during shutdown window
```

**Success Criteria:**
- ✅ Error rate <0.1% during shutdown
- ✅ All in-flight requests complete
- ✅ New requests route to healthy pods within 1 second

---

## Test Execution Schedule

| Week | Test Focus | Duration |
|------|-----------|----------|
| 1 | Test setup + Failure Case 1 | 5 days |
| 2 | Failure Cases 2 & 3 | 5 days |
| 3 | Failure Cases 4 & 5 | 5 days |
| 4 | Full chaos scenario + report | 5 days |

---

## Observability Requirements

### Metrics to Track

```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spot-optimization-metrics
spec:
  selector:
    matchLabels:
      app: spot-test
  endpoints:
    - port: metrics
      interval: 10s
```

**Key Metrics:**
- `kube_pod_status_phase{phase="Pending"}` - Track pending pods
- `kube_node_status_condition{condition="Ready"}` - Node availability
- `cluster_autoscaler_scaled_up_nodes_total` - Scale-up events
- `http_request_duration_seconds` - Application latency
- `http_requests_total` - Success/failure rates

### Dashboards

```bash
# Import Grafana dashboard for spot monitoring
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: spot-optimization-dashboard
  namespace: monitoring
data:
  spot-dashboard.json: |
    {
      "dashboard": {
        "title": "Spot Node Optimization",
        "panels": [
          {
            "title": "Pod Distribution by Node Type",
            "targets": [{
              "expr": "count(kube_pod_info) by (node)"
            }]
          },
          {
            "title": "Pending Pods",
            "targets": [{
              "expr": "sum(kube_pod_status_phase{phase='Pending'})"
            }]
          }
        ]
      }
    }
EOF
```

---

## Automated Test Runner

```bash
#!/bin/bash
# chaos-test-runner.sh

set -e

echo "=== AKS Spot Optimization Chaos Tests ==="
echo "Starting test suite at $(date)"

# Test 1: Multi-pool eviction
echo "Running Test 1: Multi-pool eviction..."
kubectl apply -f chaos-spot-multi-eviction.yaml
sleep 300
kubectl delete -f chaos-spot-multi-eviction.yaml

# Test 2: Autoscaler delay
echo "Running Test 2: Autoscaler delay..."
kubectl apply -f chaos-instant-demand-spike.yaml
sleep 600
kubectl delete -f chaos-instant-demand-spike.yaml

# Test 3: Spot unavailability
echo "Running Test 3: Spot capacity exhaustion..."
./test-spot-capacity-exhaustion.sh

# Test 4: Topology spread
echo "Running Test 4: Zone failure..."
kubectl apply -f chaos-zone-failure.yaml
sleep 600
kubectl delete -f chaos-zone-failure.yaml

# Test 5: Graceful shutdown
echo "Running Test 5: Shutdown timing..."
./shutdown-timing-test.sh

echo "=== All tests complete ==="
echo "Review results in test-results/$(date +%Y%m%d)"
```

---

## Success Criteria Summary

| Test | Metric | Target | Critical |
|------|--------|--------|----------|
| Multi-pool eviction | Recovery time | <120s | ✅ |
| Multi-pool eviction | Request success | >95% | ✅ |
| Autoscaler delay | Pending duration | <30s | ✅ |
| Spot unavailability | Fallback time | <60s | ✅ |
| Topology spread | Pod scheduling | 100% | ✅ |
| Graceful shutdown | Error rate | <0.1% | ✅ |

---

*Document End*
