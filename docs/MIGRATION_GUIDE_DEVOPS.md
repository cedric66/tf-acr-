# DevOps/App Team Spot Migration Guide

**Target Audience:** Application Developers & DevOps Engineers
**Purpose:** Concise guide to preparing workloads for Spot Node Pools.

---

## 1. What is Changing?

The platform team is introducing **Spot Node Pools** to the AKS cluster.
*   **Benefit:** Significant cost savings (up to 90%).
*   **Trade-off:** Nodes can be "evicted" (reclaimed by Azure) with **30 seconds notice**.

**Your Goal:** Ensure your application can handle a 30-second shutdown signal safely.

---

## 2. Am I Eligible?

| Criteria | Spot Eligible? | Action Required |
|----------|----------------|-----------------|
| **Stateless API / Web App** | ✅ **YES** | Add Toleration + Graceful Shutdown |
| **Worker / Batch Job** | ✅ **YES** | Add Toleration + Checkpointing |
| **Database / Stateful Store** | ❌ **NO** | **Do Nothing** (Will stay on Standard nodes) |
| **Critical Singleton** | ❌ **NO** | **Do Nothing** (Will stay on Standard nodes) |

---

## 3. Implementation Steps

### Step 1: Add Spot Toleration

By default, pods will **NOT** schedule on spot nodes. You must opt-in by adding this toleration to your `Deployment.yaml` or Helm values.

**Code Snippet (Deployment / Pod Spec):**
```yaml
spec:
  template:
    spec:
      tolerations:
        # Allow scheduling on Spot Nodes
        - key: "kubernetes.azure.com/scalesetpriority"
          operator: "Equal"
          value: "spot"
          effect: "NoSchedule"
```

### Step 2: Enable Graceful Shutdown (Critical)

Spot nodes give you only 30 seconds to shut down. You **must** ensure your app stops accepting new connections and finishes in-flight requests within this window.

**Configuration Updates:**

```yaml
spec:
  template:
    spec:
      # 1. Give pod enough time to shut down (default is 30s, recommend 35s+)
      terminationGracePeriodSeconds: 35
      
      containers:
        - name: my-app
          # 2. Add preStop hook to stop traffic BEFORE process kill
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 20"]
```

**Why the `sleep 20`?**
This keeps the container alive but "NotReady", allowing the LoadBalancer time to remove the pod from rotation *before* the application process receives the SIGTERM signal.

### Step 3: Handle SIGTERM in Code

Your application code must catch the `SIGTERM` signal and exit cleanly.

**Node.js Example:**
```javascript
process.on('SIGTERM', () => {
  server.close(() => {
    console.log('Connections closed.');
    process.exit(0);
  });
});
```

**Python (Flask) Example:**
```python
import signal, sys

def handler(signum, frame):
    print("Graceful shutdown...")
    sys.exit(0)

signal.signal(signal.SIGTERM, handler)
```

**Java (Spring Boot):**
Spring Boot handles this automatically. Ensure `server.shutdown: graceful` is set in `application.properties`.

---

## 4. Verification

After deploying your changes, verify your pods are running on Spot nodes:

```bash
# Check which node type your pods are on
kubectl get pods -l app=<your-app> -o wide

# Verify the node is Spot (look for "spot" in the name or labels)
kubectl describe node <node-name> | grep -i spot
```

**Simulate Eviction (Dev Environment Only):**
Ask Platform Ops to run a "drain" test on the node running your pod to confirm zero-downtime behavior.

---

## 5. Rollback

If your application becomes unstable on Spot:
1.  **Remove the Toleration** added in Step 1.
2.  Redeploy.
3.  Pods will automatically move back to Standard (On-Demand) nodes.
