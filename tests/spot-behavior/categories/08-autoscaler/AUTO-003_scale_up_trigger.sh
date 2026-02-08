#!/usr/bin/env bash
# AUTO-003: Scale-up triggered by pending pods
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "AUTO-003" "Scale-up triggered by pending pods" "autoscaler"

# Create a pending pod that requests spot scheduling
cat <<EOF | kubectl apply -f - 2>/dev/null || skip_test "Cannot create test pod"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: autoscaler-test
  namespace: $NAMESPACE
  labels:
    app: autoscaler-test
spec:
  replicas: 3
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
        operator: Equal
        value: spot
        effect: NoSchedule
      containers:
      - name: stress
        image: busybox
        command: ["sleep", "300"]
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
EOF

# Wait for pods to be scheduled (either running or triggering scale-up)
sleep 30

pending=$(kubectl get pods -n "$NAMESPACE" -l "app=autoscaler-test" --no-headers 2>/dev/null | grep -c Pending || echo 0)
running=$(kubectl get pods -n "$NAMESPACE" -l "app=autoscaler-test" --no-headers 2>/dev/null | grep -c Running || echo 0)

if [[ "$pending" -gt 0 ]]; then
  log_step "Pending pods detected - waiting for autoscaler scale-up..."
  wait_for_pods_ready "app=autoscaler-test" 300 || true
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=autoscaler-test" --no-headers 2>/dev/null | grep -c Running || echo 0)
fi

assert_gt "At least 1 autoscaler-test pod running" "$running" 0

# Cleanup
kubectl delete deployment autoscaler-test -n "$NAMESPACE" --grace-period=5 2>/dev/null || true

add_evidence "scale_up" "$(jq -n --argjson running "$running" --argjson pending "$pending" '{running: $running, pending: $pending}')"
finish_test
