###############################################################################
# Spot-Tolerant Deployment Template
#
# Purpose: Template for deploying workloads that can run on both spot and
#          standard node pools with proper topology spread for resilience.
#
# Key Features:
# 1. Tolerates spot node taints - allows scheduling on spot nodes
# 2. Prefers spot nodes via node affinity weights
# 3. Spreads pods across zones and node types via topology constraints
# 4. Includes graceful shutdown handling for spot evictions
# 5. Pod disruption budget ensures minimum availability
#
# IMPORTANT: Replace placeholders marked with ${...} before applying:
#   - ${APP_NAME}: Name of your application
#   - ${NAMESPACE}: Target namespace
#   - ${IMAGE}: Container image
#   - ${REPLICAS}: Number of replicas (recommend 3+)
###############################################################################
---
# PodDisruptionBudget - Ensures minimum availability during evictions
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${APP_NAME}-pdb
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  # At least 50% of pods must remain available during voluntary disruptions
  minAvailable: 50%
  selector:
    matchLabels:
      app: ${APP_NAME}

---
# Service (optional - adjust as needed)
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app: ${APP_NAME}

---
# Deployment with spot-tolerant configuration
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    cost-optimization: spot-preferred
spec:
  replicas: ${REPLICAS}
  
  # Rolling update strategy for zero-downtime deployments
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
  
  selector:
    matchLabels:
      app: ${APP_NAME}
  
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        cost-optimization: spot-preferred
      annotations:
        # Prometheus metrics scraping (if enabled)
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    
    spec:
      #########################################################################
      # TOLERATIONS
      # Allow this pod to be scheduled on spot nodes (which have taints)
      #########################################################################
      tolerations:
        # Tolerate spot node taint
        - key: kubernetes.azure.com/scalesetpriority
          operator: Equal
          value: spot
          effect: NoSchedule
        
        # Tolerate node being in NotReady state briefly during eviction
        - key: node.kubernetes.io/not-ready
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 30
        
        # Tolerate node being unreachable briefly
        - key: node.kubernetes.io/unreachable
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 30

      #########################################################################
      # AFFINITY RULES
      # Prefer spot nodes but allow fallback to standard nodes
      #########################################################################
      affinity:
        # Node Affinity: Prefer spot, allow standard
        nodeAffinity:
          # SOFT PREFERENCE: Prefer spot nodes (100 weight)
          preferredDuringSchedulingIgnoredDuringExecution:
            # Highest weight: Prefer spot nodes
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.azure.com/scalesetpriority
                    operator: In
                    values:
                      - spot
            # Lower weight: Fall back to on-demand nodes
            - weight: 50
              preference:
                matchExpressions:
                  - key: priority
                    operator: In
                    values:
                      - on-demand
        
        # Pod Anti-Affinity: Spread pods across nodes
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            # Avoid co-locating pods of the same app on the same node
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - ${APP_NAME}
                topologyKey: kubernetes.io/hostname

      #########################################################################
      # TOPOLOGY SPREAD CONSTRAINTS
      # Ensure pods are distributed for resilience
      #########################################################################
      topologySpreadConstraints:
        # 1. Spread across availability zones (highest priority)
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway  # Don't block scheduling
          labelSelector:
            matchLabels:
              app: ${APP_NAME}
        
        # 2. Spread across node pool types (spot vs standard)
        # Allow skew of 2 to prefer spot while having some on standard
        - maxSkew: 2
          topologyKey: kubernetes.azure.com/scalesetpriority
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: ${APP_NAME}
        
        # 3. Spread across individual nodes
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: ${APP_NAME}

      #########################################################################
      # CONTAINER SPECIFICATION
      #########################################################################
      containers:
        - name: ${APP_NAME}
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          
          # Resource requests and limits
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          
          # Health checks
          livenessProbe:
            httpGet:
              path: /health/live
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          
          readinessProbe:
            httpGet:
              path: /health/ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          
          # Startup probe for slow-starting apps
          startupProbe:
            httpGet:
              path: /health/live
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 30  # 5 minutes max startup time
          
          #####################################################################
          # GRACEFUL SHUTDOWN FOR SPOT EVICTIONS
          # 
          # Azure provides ~30 seconds notice before spot eviction.
          # The preStop hook ensures the app has time to:
          # - Stop accepting new requests
          # - Drain existing connections
          # - Complete in-flight requests
          # - Perform cleanup
          #####################################################################
          lifecycle:
            preStop:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - |
                    echo "Received shutdown signal, starting graceful shutdown..."
                    # Signal app to stop accepting new connections
                    # Adjust this for your application
                    kill -SIGTERM 1 2>/dev/null || true
                    # Wait for connections to drain
                    sleep 25
                    echo "Graceful shutdown complete"
          
          # Environment variables
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            # Graceful shutdown period (match terminationGracePeriodSeconds)
            - name: SHUTDOWN_TIMEOUT_SECONDS
              value: "30"

      #########################################################################
      # POD-LEVEL SETTINGS
      #########################################################################
      
      # Termination grace period
      # Must be >= preStop sleep time to allow graceful shutdown
      terminationGracePeriodSeconds: 35
      
      # DNS config for fast DNS resolution
      dnsPolicy: ClusterFirst
      
      # Security context (adjust based on your needs)
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      
      # Service account
      serviceAccountName: default
      automountServiceAccountToken: false
      
      # Optional: Priority class for important workloads
      # priorityClassName: high-priority
