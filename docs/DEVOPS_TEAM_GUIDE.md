# DevOps Team Guide: Deploying on AKS with Spot Nodes

**Audience:** Application Development Teams, DevOps Engineers  
**Purpose:** Enable teams to deploy cost-optimized workloads on spot instances  
**Created:** 2026-01-12

---

## Quick Start

### Can My Application Run on Spot?

**Use this decision tree:**

```
Start
├─ Is your app stateful (database, cache with persistence)?
│  └─ YES → ❌ Do NOT use spot
│  └─ NO → Continue
│
├─ Can your app tolerate sudden termination (30-sec warning)?
│  └─ NO → ❌ Do NOT use spot
│  └─ YES → Continue
│
├─ Does your app handle PCI/HIPAA/SOC2 data?
│  └─ YES → ❌ Do NOT use spot (compliance requirement)
│  └─ NO → Continue
│
└─ ✅ Your app is SPOT-ELIGIBLE!
```

**Examples:**

| Workload Type | Spot Eligible? | Reasoning |
|---------------|----------------|-----------|
| REST API (stateless) | ✅ Yes | No local state, terminates cleanly |
| Web Frontend | ✅ Yes | Stateless, multiple replicas |
| Background Job Worker | ✅ Yes | Resumable, queue-based |
| Batch Processing | ✅ Yes | Checkpointed, can resume |
| CI/CD Runner | ✅ Yes | Ephemeral by design |
| Redis (cache-only, no persistence) | ⚠️ Maybe | If cache miss is acceptable |
| PostgreSQL Database | ❌ No | Stateful, critical data |
| Kafka Broker | ❌ No | Stateful, leader election |
| Payment Service (PCI-DSS) | ❌ No | Compliance requirement |

---

## Deploying to Spot Nodes

### Method 1: Just Add Tolerations (Simple)

Add this to your existing deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-api
spec:
  replicas: 3
  template:
    spec:
      # ADD THIS: Allow scheduling on spot nodes
      tolerations:
        - key: kubernetes.azure.com/scalesetpriority
          operator: Equal
          value: spot
          effect: NoSchedule
      
      containers:
        - name: api
          image: myapp:v1.0
          # ... rest of your config
```

**What this does:**
- Your pods CAN schedule on spot nodes
- They will PREFER spot nodes (cheaper)
- They will FALL BACK to standard nodes if spot unavailable

**When to use:** Quick wins, dev/test environments

---

### Method 2: Full Optimization (Recommended for Production)

Use this complete template for production applications:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-api
  labels:
    app: my-api
    cost-optimization: spot-preferred
spec:
  replicas: 6  # Use 3+ replicas for spot workloads
  
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
  
  selector:
    matchLabels:
      app: my-api
  
  template:
    metadata:
      labels:
        app: my-api
    
    spec:
      ##################################################################
      # SPOT CONFIGURATION
      ##################################################################
      
      # 1. TOLERATION: Allow scheduling on spot nodes
      tolerations:
        - key: kubernetes.azure.com/scalesetpriority
          operator: Equal
          value: spot
          effect: NoSchedule
        
        # Tolerate brief node unavailability during eviction
        - key: node.kubernetes.io/not-ready
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 30
        
        - key: node.kubernetes.io/unreachable
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 30
      
      # 2. AFFINITY: Prefer spot, fall back to standard
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            # Highest priority: Prefer spot nodes (cost savings)
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.azure.com/scalesetpriority
                    operator: In
                    values: [spot]
            # Lower priority: Fall back to standard nodes
            - weight: 50
              preference:
                matchExpressions:
                  - key: priority
                    operator: In
                    values: [on-demand]
        
        # Spread pods across different nodes for HA
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values: [my-api]
                topologyKey: kubernetes.io/hostname
      
      # 3. TOPOLOGY SPREAD: Distribute pods for resilience
      topologySpreadConstraints:
        # Spread across availability zones
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway  # Don't block scheduling
          labelSelector:
            matchLabels:
              app: my-api
        
        # Spread across node pool types (spot vs standard)
        - maxSkew: 2  # Allow some imbalance to prefer spot
          topologyKey: kubernetes.azure.com/scalesetpriority
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: my-api
        
        # Spread across individual nodes
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: my-api
      
      ##################################################################
      # GRACEFUL SHUTDOWN (CRITICAL FOR SPOT!)
      ##################################################################
      
      containers:
        - name: api
          image: myapp:v1.0
          
          ports:
            - name: http
              containerPort: 8080
          
          # Health checks (mark pod NotReady before shutdown)
          readinessProbe:
            httpGet:
              path: /health/ready
              port: http
            periodSeconds: 5
            failureThreshold: 2  # Fast to mark NotReady
          
          livenessProbe:
            httpGet:
              path: /health/live
              port: http
            periodSeconds: 10
          
          # CRITICAL: Graceful shutdown handler
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - |
                    echo "Received shutdown signal - starting graceful shutdown"
                    # Stop accepting new connections
                    kill -TERM 1 2>/dev/null || true
                    # Wait for existing connections to complete
                    sleep 25
                    echo "Graceful shutdown complete"
          
          env:
            - name: SHUTDOWN_TIMEOUT_SECONDS
              value: "30"
          
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
      
      # Pod shutdown grace period (must be >= preStop sleep time)
      terminationGracePeriodSeconds: 35
      
      # Security context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000

---
# Pod Disruption Budget - Ensure minimum availability
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-api-pdb
spec:
  minAvailable: 50%  # At least half your pods must remain available
  selector:
    matchLabels:
      app: my-api
```

**When to use:** Production workloads, high availability requirements

---

## Application Code Changes

### Implementing Graceful Shutdown

Your application MUST handle shutdown gracefully. Here's how:

#### Node.js Example

```javascript
// server.js
const express = require('express');
const app = express();
const server = app.listen(8080);

// Health check endpoint
app.get('/health/ready', (req, res) => {
  if (shuttingDown) {
    return res.status(503).send('Shutting down');
  }
  res.status(200).send('OK');
});

let shuttingDown = false;

// Graceful shutdown handler
process.on('SIGTERM', () => {
  console.log('SIGTERM received, starting graceful shutdown');
  shuttingDown = true;  // Mark as NotReady
  
  // Stop accepting new connections
  server.close(() => {
    console.log('HTTP server closed');
    
    // Clean up resources (close DB connections, etc.)
    cleanupResources().then(() => {
      console.log('Graceful shutdown complete');
      process.exit(0);
    });
  });
  
  // Force shutdown after 30 seconds
  setTimeout(() => {
    console.error('Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
});

async function cleanupResources() {
  // Close database connections
  await db.close();
  // Flush metrics
  await metrics.flush();
  // Any other cleanup
}
```

#### Python (Flask) Example

```python
# app.py
from flask import Flask
import signal
import sys
import time

app = Flask(__name__)
shutting_down = False

@app.route('/health/ready')
def health_ready():
    if shutting_down:
        return 'Shutting down', 503
    return 'OK', 200

def graceful_shutdown(signum, frame):
    global shutting_down
    print(f'Signal {signum} received, starting graceful shutdown')
    shutting_down = True  # Mark as NotReady
    
    # Give time for load balancer to remove this pod
    time.sleep(2)
    
    # Stop accepting new requests
    # Flask will finish current requests
    
    # Cleanup
    cleanup_resources()
    
    print('Graceful shutdown complete')
    sys.exit(0)

def cleanup_resources():
    # Close database connections
    db.close()
    # Flush logs
    logger.flush()

# Register signal handlers
signal.signal(signal.SIGTERM, graceful_shutdown)
signal.signal(signal.SIGINT, graceful_shutdown)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

#### Go Example

```go
// main.go
package main

import (
    "context"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"
)

var shuttingDown bool

func main() {
    mux := http.NewServeMux()
    
    // Health check
    mux.HandleFunc("/health/ready", func(w http.ResponseWriter, r *http.Request) {
        if shuttingDown {
            w.WriteHeader(http.StatusServiceUnavailable)
            return
        }
        w.WriteHeader(http.StatusOK)
    })
    
    server := &http.Server{
        Addr:    ":8080",
        Handler: mux,
    }
    
    // Start server in goroutine
    go func() {
        if err := server.ListenAndServe(); err != http.ErrServerClosed {
            log.Fatal(err)
        }
    }()
    
    // Wait for interrupt signal
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
    <-quit
    
    log.Println("Shutdown signal received, starting graceful shutdown")
    shuttingDown = true
    
    // Give load balancer time to remove pod from rotation
    time.Sleep(2 * time.Second)
    
    // Gracefully shutdown with 30-second timeout
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    
    if err := server.Shutdown(ctx); err != nil {
        log.Printf("Server forced to shutdown: %v", err)
    }
    
    // Cleanup resources
    cleanupResources()
    
    log.Println("Graceful shutdown complete")
}

func cleanupResources() {
    // Close database connections
    db.Close()
    // Flush metrics
    metrics.Flush()
}
```

---

## Testing Your Application on Spot

### Dev Environment Testing

```bash
# 1. Deploy your app to dev cluster (has spot nodes)
kubectl apply -f deployment.yaml --namespace=dev

# 2. Verify pods are on spot nodes
kubectl get pods -n dev -l app=my-api -o wide

# 3. Simulate eviction (drain a spot node)
SPOT_NODE=$(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o name | head -1)
kubectl drain $SPOT_NODE --ignore-daemonsets --delete-emptydir-data

# 4. Watch pods reschedule
kubectl get pods -n dev -l app=my-api -w

# 5. Verify no downtime (run concurrent load test)
while true; do curl http://my-api-dev.company.com/health; sleep 0.5; done

# 6. Uncordon node when done testing
kubectl uncordon $SPOT_NODE
```

**Expected Results:**
- ✅ Pods reschedule to other nodes within 30 seconds
- ✅ Zero or minimal failed requests during drain
- ✅ Application remains healthy throughout

---

## Common Issues & Solutions

### Issue 1: Pods Won't Schedule on Spot

**Symptom:** Pods always land on standard nodes, never spot

**Diagnosis:**
```bash
kubectl describe pod <pod-name> | grep -A10 Events
```

**Common Causes:**

#### Missing Toleration
**Fix:**
```yaml
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    value: spot
    effect: NoSchedule
```

#### PodDisruptionBudget Too Restrictive
**Fix:** Adjust minAvailable to allow spot scheduling:
```yaml
minAvailable: 1  # Instead of high number
```

#### Resource Requests Too Large
**Fix:** Spot nodes might be smaller VM sizes. Reduce requests:
```yaml
resources:
  requests:
    cpu: 250m      # Instead of 2000m
    memory: 256Mi  # Instead of 4Gi
```

---

### Issue 2: High Pod Churn (Frequent Rescheduling)

**Symptom:** Pods restarting frequently, event log shows many evictions

**Diagnosis:**
```bash
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | grep Evicted
```

**Possible Causes:**

1. **Spot eviction rate is high** (external factor)
   - Check SRE team for cluster-wide eviction trends
   - No action needed on your side - this is expected

2. **Too few replicas**
   - When one pod evicts, affects larger % of capacity
   - **Fix:** Increase replicas (minimum 3 for spot workloads)

3. **Improper readiness probe**
   - Pods marked Ready too quickly, receive traffic before fully initialized
   - **Fix:** Tune readiness probe timing
   ```yaml
   readinessProbe:
     initialDelaySeconds: 10  # Increase if app slow to start
     periodSeconds: 5
   ```

---

### Issue 3: Application Errors During Eviction

**Symptom:** Spike in 5xx errors or timeouts when spot nodes evicted

**Root Cause:** Application not shutting down gracefully

**Fix Checklist:**
- [ ] preStop hook implemented with adequate sleep time
- [ ] terminationGracePeriodSeconds ≥ preStop sleep + 5 seconds
- [ ] Readiness probe marks pod NotReady quickly (low failureThreshold)
- [ ] Application handles SIGTERM signal
- [ ] In-flight requests complete before shutdown

**Testing:**
```bash
# Send traffic while terminating pod
kubectl run -it --rm load-gen --image=busybox -- sh -c \
  "while true; do wget -q -O- http://my-api; sleep 0.1; done" &

# Terminate a pod
kubectl delete pod <pod-name>

# Check for errors in load-gen output
# Expected: No errors or very minimal (<0.1%)
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/deploy.yml
name: Deploy to AKS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up kubectl
        uses: azure/setup-kubectl@v3
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Get AKS credentials
        run: |
          az aks get-credentials \
            --resource-group rg-aks-prod \
            --name aks-prod
      
      - name: Validate spot compatibility
        run: |
          # Ensure deployment has spot toleration
          if ! grep -q "kubernetes.azure.com/scalesetpriority" k8s/deployment.yaml; then
            echo "WARNING: Deployment missing spot toleration"
            echo "Add spot toleration for cost savings"
            # Don't fail, just warn
          fi
      
      - name: Deploy
        run: |
          kubectl apply -f k8s/ --namespace=production
          kubectl rollout status deployment/my-api -n production --timeout=5m
      
      - name: Verify deployment
        run: |
          # Check if pods are on spot nodes
          SPOT_COUNT=$(kubectl get pods -n production -l app=my-api -o json | \
            jq '[.items[] | select(.spec.nodeName != null)] | length')
          echo "Pods on cluster: $SPOT_COUNT"
          
          # It's OK if not all on spot (might be on standard fallback)
          # Just report the distribution
```

---

## Helm Chart Integration

If you use Helm, add these values:

```yaml
# values.yaml
replicaCount: 6

spot:
  enabled: true  # Toggle spot support
  tolerations:
    - key: kubernetes.azure.com/scalesetpriority
      operator: Equal
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

podDisruptionBudget:
  enabled: true
  minAvailable: 50%

gracefulShutdown:
  enabled: true
  preStopSleepSeconds: 25
  terminationGracePeriodSeconds: 35
```

```yaml
# templates/deployment.yaml
{{- if .Values.spot.enabled }}
tolerations:
  {{- toYaml .Values.spot.tolerations | nindent 2 }}

affinity:
  {{- toYaml .Values.spot.affinity | nindent 2 }}
{{- end }}

{{- if .Values.gracefulShutdown.enabled }}
lifecycle:
  preStop:
    exec:
      command:
        - /bin/sh
        - -c
        - sleep {{ .Values.gracefulShutdown.preStopSleepSeconds }}

terminationGracePeriodSeconds: {{ .Values.gracefulShutdown.terminationGracePeriodSeconds }}
{{- end }}
```

---

## Best Practices Checklist

### Before Deploying to Spot

- [ ] Application is stateless OR has external state management
- [ ] Minimum 3 replicas for production workloads
- [ ] Graceful shutdown implemented (handles SIGTERM)
- [ ] preStop hook with 25-second sleep
- [ ] terminationGracePeriodSeconds ≥ 35 seconds
- [ ] Readiness probe configured (fast to mark NotReady)
- [ ] PodDisruptionBudget created (minAvailable: 50%)
- [ ] Topology spread constraints added
- [ ] Tested eviction scenario in dev environment
- [ ] Application handles brief outages gracefully
- [ ] No compliance restrictions (PCI/HIPAA/etc.)

### Monitoring Your Spot Workloads

```bash
# Add these labels to your deployment for tracking
labels:
  cost-optimization: spot-preferred
  cost-center: your-team-name

# Platform team provides dashboards filtered by these labels
```

Access dashboards at: Grafana → AKS → Spot Adoption by Team

---

## Cost Visibility

### How Much Am I Saving?

Platform team provides per-namespace cost breakdown.

**Example Report:**
```
Namespace: ecommerce-api
├─ Pods on Spot: 18 (75%)
├─ Pods on Standard: 6 (25%)
├─ Monthly Cost: $450
└─ Savings vs All Standard: $780 (63%)
```

**Access:** Azure Cost Management → Tags → Filter by namespace

---

## Getting Help

### Self-Service Resources

| Resource | Link | Purpose |
|----------|------|---------|
| Spot Docs | [Link to internal wiki] | Detailed documentation |
| Deployment Templates | [Link to Git repo] | Copy-paste examples |
| Grafana Dashboards | [Link to Grafana] | Monitor your apps |
| Cost Explorer | [Link to Azure] | Track savings |

### Support Channels

| Issue Type | Contact | Response Time |
|------------|---------|---------------|
| General Questions | #platform-engineering (Slack) | Best effort |
| Deployment Issues | #devops-support (Slack) | 4 business hours |
| Incident (P1/P2) | #incident-response (Slack) | Immediate |
| Cost Questions | #finops (Slack) | 24 hours |

### Office Hours

**Platform Engineering Office Hours:**  
Every Tuesday & Thursday, 2:00-3:00 PM  
Video: [Zoom Link]  
No agenda required - drop in with questions!

---

## FAQ

**Q: Will my app be less reliable on spot?**  
A: No, IF you follow best practices (3+ replicas, graceful shutdown, PDB). spot Just means pods reschedule occasionally.

**Q: How often do spot evictions happen?**  
A: Averages 3-5% per month per node. With 3 diversified spot pools, simultaneous eviction is <1% probability.

**Q: What if I forget the toleration?**  
A: Your app will only schedule on standard nodes - no savings, but no harm.

**Q: Can I use spot for batch jobs?**  
A: Yes! Spot is PERFECT for batch jobs. Use Kubernetes Jobs or CronJobs with spot tolerations.

**Q: What happens during spot eviction?**  
A:
1. Azure sends 30-second eviction notice
2. Pod marked NotReady (traffic stops)
3. preStop hook runs (cleanup)
4. Pod terminated
5. New pod schedules on available node (spot or standard)
6. Total downtime per pod: ~30-60 seconds (but you have multiple replicas!)

**Q: Can I mix spot and standard in the same deployment?**  
A: Yes! That's exactly how it works. topology spread constraints distribute pods across both.

**Q: Do I need to change my application code?**  
A: Only to add graceful shutdown (SIGTERM handling). This is good practice anyway!

---

## Migration Checklist

### Migrating Existing Deployment to Spot

```bash
# 1. Backup current deployment
kubectl get deployment <deployment-name> -n <namespace> -o yaml > backup.yaml

# 2. Add spot toleration, affinity, topology spread
# Edit your deployment YAML with template from above

# 3. Deploy to dev first
kubectl apply -f deployment.yaml --namespace=dev

# 4. Test eviction scenario (see "Testing Your Application" section)

# 5. Monitor for 1 week in dev

# 6. Deploy to staging
kubectl apply -f deployment.yaml --namespace=staging

# 7. Monitor for 1 week in staging

# 8. Deploy to production (gradual rollout)
kubectl apply -f deployment.yaml --namespace=production

# 9. Monitor cost savings
# Check Grafana dashboard after 1 month
```

---

**Questions? Feedback?**

This guide is maintained by the Platform Engineering team.  
Submit improvements via PR to: [git repo link]

Last Updated: 2026-01-12
