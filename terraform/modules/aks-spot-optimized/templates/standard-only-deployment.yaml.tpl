###############################################################################
# Standard-Only Deployment Template
#
# Purpose: Template for deploying workloads that MUST NOT run on spot nodes.
#          Use this for stateful applications, databases, or any workload
#          that cannot tolerate sudden eviction.
#
# Key Features:
# 1. Does NOT tolerate spot node taints - will never schedule on spot
# 2. Requires scheduling on standard (on-demand) nodes only
# 3. Includes anti-affinity for high availability
#
# Use this template for:
# - Databases (PostgreSQL, MySQL, MongoDB, etc.)
# - Cache services with persistence (Redis with AOF)
# - Message queues (RabbitMQ, Kafka)
# - Any stateful application
# - Leader election services
###############################################################################
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    cost-optimization: standard-only
spec:
  replicas: ${REPLICAS}
  
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero downtime for critical workloads
  
  selector:
    matchLabels:
      app: ${APP_NAME}
  
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        cost-optimization: standard-only
    
    spec:
      #########################################################################
      # NO SPOT TOLERATIONS
      # By NOT tolerating the spot taint, pods will only schedule on standard
      #########################################################################
      tolerations: []  # Explicitly empty - no spot toleration

      #########################################################################
      # NODE AFFINITY: Require standard nodes
      #########################################################################
      affinity:
        nodeAffinity:
          # HARD REQUIREMENT: Must schedule on non-spot nodes
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  # Exclude spot nodes explicitly
                  - key: kubernetes.azure.com/scalesetpriority
                    operator: NotIn
                    values:
                      - spot
                  # Must be a user node pool
                  - key: node-pool-type
                    operator: In
                    values:
                      - user
        
        # Pod Anti-Affinity: Spread across nodes for HA
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - ${APP_NAME}
              topologyKey: kubernetes.io/hostname

      #########################################################################
      # TOPOLOGY SPREAD - Zone distribution only (not spot/standard)
      #########################################################################
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule  # Strict for critical workloads
          labelSelector:
            matchLabels:
              app: ${APP_NAME}
        
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: ${APP_NAME}

      containers:
        - name: ${APP_NAME}
          image: ${IMAGE}
          
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "2000m"
              memory: "2Gi"
          
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 15
          
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          
          env:
            - name: NODE_TYPE
              value: "standard-only"

      terminationGracePeriodSeconds: 60  # More time for stateful apps
      priorityClassName: high-priority  # Ensure these never get preempted

---
# PodDisruptionBudget - Stricter for critical workloads
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${APP_NAME}-pdb
  namespace: ${NAMESPACE}
spec:
  minAvailable: 66%  # At least 2/3 must remain available
  selector:
    matchLabels:
      app: ${APP_NAME}
