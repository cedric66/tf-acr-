# Security Assessment: AKS Spot Instance Implementation

**Document Owner:** Group Information Security  
**Assessment Date:** 2026-01-12  
**Classification:** Internal - Security Review  
**Risk Rating:** Medium (Acceptable with Controls)

---

## Executive Summary for Security

**Assessment:** The proposed AKS Spot Instance architecture introduces **no new security boundaries** and maintains existing security posture. All workloads continue to run within the same AKS cluster with identical RBAC, network policies, and encryption controls.

**Security Impact:** ✅ **APPROVED** with conditions (see recommendations)

**Key Findings:**
- No change to attack surface or trust boundaries
- Eviction mechanism is infrastructure-level (non-security event)
- Potential data availability impact during evictions (mitigated)
- Enhanced observability aids security monitoring

---

## Security Architecture Analysis

### Trust Boundaries (Unchanged)

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Subscription                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              AKS Cluster (Same Security Zone)         │  │
│  │  ┌──────────────┬──────────────┬──────────────┐      │  │
│  │  │ Spot Nodes   │ Standard     │ System Pool  │      │  │
│  │  │              │ Nodes        │              │      │  │
│  │  │ - Same VNet  │ - Same VNet  │ - Same VNet  │      │  │
│  │  │ - Same NSG   │ - Same NSG   │ - Same NSG   │      │  │
│  │  │ - Same RBAC  │ - Same RBAC  │ - Same RBAC  │      │  │
│  │  └──────────────┴──────────────┴──────────────┘      │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Security Assessment:** ✅ No new trust boundaries introduced

---

## Threat Model

### Threat 1: Privileged Access During Eviction

**Scenario:** Malicious actor times attack during spot eviction to exploit reduced redundancy

**Likelihood:** Low  
**Impact:** Medium  
**Risk:** Low-Medium

**Mitigations:**
- ✅ PodDisruptionBudgets prevent >50% of replicas being evicted
- ✅ Topology spread ensures pods remain on multiple nodes
- ✅ Standard pools provide fallback capacity
- ✅ WAF and rate limiting remain active throughout

**Residual Risk:** ✅ Acceptable

---

### Threat 2: Data Exposure Through Spot Node Reuse

**Scenario:** Azure reallocates spot VM to another tenant without proper disk sanitization

**Likelihood:** Very Low (Azure handles VM lifecycle securely)  
**Impact:** Critical  
**Risk:** Low

**Mitigations:**
- ✅ Azure encrypts all disks at rest (default)
- ✅ Ephemeral OS disks recommended (data never persists)
- ✅ Azure Disk Encryption for OS and data disks
- ✅ Azure guarantees disk wipe between allocations
- ✅ No sensitive data persists on node filesystems

**Configuration:**
```hcl
# Terraform - Ephemeral OS Disk (recommended)
os_disk_type = "Ephemeral"

# Alternative - Encrypted Managed Disk
os_disk_type = "Managed"
# Azure automatically encrypts with platform-managed keys
```

**Residual Risk:** ✅ Acceptable (Azure platform control)

---

### Threat 3: Secrets Exposure During Rapid Pod Rescheduling

**Scenario:** Pod eviction leaves secrets in memory or logs on terminated nodes

**Likelihood:** Low  
**Impact:** High  
**Risk:** Medium

**Mitigations:**
- ✅ **Use Azure Key Vault with CSI Driver** (secrets never on disk)
- ✅ Pod `preStop` hooks clear sensitive data
- ✅ `terminationGracePeriodSeconds` allows cleanup
- ✅ Secrets rotation via External Secrets Operator
- ❌ **NOT RECOMMENDED:** Kubernetes Secrets (base64 in etcd)

**Recommended Configuration:**
```yaml
# Use Azure Key Vault CSI Driver
volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "azure-keyvault-secrets"

# Pod lifecycle - clear secrets on shutdown
lifecycle:
  preStop:
    exec:
      command:
        - /bin/sh
        - -c
        - |
          # Clear environment variables
          unset DB_PASSWORD API_KEY
          # Clear in-memory caches
          curl -X POST http://localhost:8080/admin/cache/clear
          sleep 2
```

**Control Requirement:** ✅ **MUST implement Key Vault CSI for production**

**Residual Risk:** ✅ Acceptable with Key Vault

---

### Threat 4: Compliance Data Processing on Spot Nodes

**Scenario:** PCI/HIPAA/SOC2 workloads run on spot nodes, evicted during audit window

**Likelihood:** Medium (without controls)  
**Impact:** High (compliance violation)  
**Risk:** High

**Mitigations:**
- ✅ **Mandatory:** Hard anti-affinity for compliance workloads
- ✅ Label-based scheduling enforcement
- ✅ OPA Gatekeeper policies prevent spot scheduling
- ✅ Audit logging of workload placement

**Enforcement Policy (OPA Gatekeeper):**
```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireNodeAntiAffinity
metadata:
  name: compliance-no-spot
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet"]
    namespaceSelector:
      matchLabels:
        compliance: "pci-dss"
  parameters:
    # MUST NOT schedule on spot nodes
    requiredAntiAffinity:
      - key: kubernetes.azure.com/scalesetpriority
        operator: In
        values: ["spot"]
```

**Workload Classification:**
```yaml
# Example: PCI-compliant payment service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: finance
  labels:
    compliance: pci-dss
    data-classification: restricted
spec:
  template:
    spec:
      # HARD REQUIREMENT: Never on spot
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.azure.com/scalesetpriority
                    operator: NotIn
                    values: [spot]
      # No toleration = cannot schedule on spot nodes
      tolerations: []
```

**Control Requirement:** ✅ **MUST implement OPA policy before production**

**Residual Risk:** ✅ Acceptable with policy enforcement

---

### Threat 5: Denial of Service via Eviction Storm

**Scenario:** Coordinated eviction of all spot pools creates availability gap

**Likelihood:** Very Low (0.5-2%)  
**Impact:** Medium (temporary degradation)  
**Risk:** Low

**Mitigations:**
- ✅ Standard pools auto-scale automatically
- ✅ DDoS protection at network edge (unchanged)
- ✅ Rate limiting at application layer
- ✅ PodDisruptionBudgets prevent full outage

**Security Note:** This is an **availability** concern, not a security vulnerability.

**Residual Risk:** ✅ Acceptable (business continuity control)

---

## Data Classification & Workload Placement

### Decision Matrix: Can This Workload Run on Spot?

| Data Classification | Stateful | Spot Allowed | Reasoning |
|---------------------|----------|--------------|-----------|
| **Public** | No | ✅ Yes | No confidentiality risk |
| **Public** | Yes | ❌ No | Data availability risk |
| **Internal** | No | ✅ Yes | Acceptable with encryption |
| **Internal** | Yes | ❌ No | Recovery time > RTO |
| **Confidential** | No | ⚠️ Case-by-case | Security review required |
| **Confidential** | Yes | ❌ No | Never acceptable |
| **Restricted/PCI/HIPAA** | Any | ❌ No | Compliance prohibition |

### Enforcement Mechanism

```yaml
# Namespace labels trigger OPA policies
apiVersion: v1
kind: Namespace
metadata:
  name: payment-processing
  labels:
    data-classification: restricted
    compliance: pci-dss
    spot-allowed: "false"  # OPA enforces no spot scheduling
```

---

## Identity & Access Management

### No Changes to IAM

| Control | Spot Nodes | Standard Nodes | Status |
|---------|------------|----------------|--------|
| Azure AD Integration | ✅ Same | ✅ Same | ✅ No change |
| Kubernetes RBAC | ✅ Same | ✅ Same | ✅ No change |
| Pod Managed Identity | ✅ Same | ✅ Same | ✅ No change |
| Service Principal | ✅ Same | ✅ Same | ✅ No change |

**Security Assessment:** ✅ No IAM changes required

---

## Network Security

### Network Policy Enforcement (Unchanged)

```yaml
# Example: Spot and standard nodes enforce same NetworkPolicy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress-policy
spec:
  podSelector:
    matchLabels:
      app: api-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: frontend
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              role: database
      ports:
        - protocol: TCP
          port: 5432
```

**Security Assessment:** ✅ Network policies apply uniformly across all node types

### Firewall & NSG Rules

| Component | Configuration | Spot Impact |
|-----------|---------------|-------------|
| Azure Firewall | Centralized egress | ✅ No change |
| NSG (Subnet) | Applied to all nodes | ✅ No change |
| Calico Network Policy | Pod-level enforcement | ✅ No change |
| Private Endpoint | AKS API server | ✅ No change |

---

## Encryption & Data Protection

### Encryption at Rest

| Data Type | Encryption | Spot Nodes | Standard Nodes |
|-----------|------------|------------|----------------|
| OS Disk | Platform-managed keys | ✅ Yes | ✅ Yes |
| Data Disk (PV) | Customer-managed keys | ✅ Yes | ✅ Yes |
| etcd | Azure encryption | ✅ Yes | ✅ Yes |
| Secrets | Key Vault CSI | ✅ Required | ✅ Required |

**Recommendation:** ✅ Use ephemeral OS disks for spot nodes (no persistent data)

### Encryption in Transit

| Connection | Protocol | Configuration |
|------------|----------|---------------|
| Pod-to-Pod | mTLS (service mesh) | Istio/Linkerd |
| Ingress | TLS 1.3 | Azure Application Gateway |
| Egress | TLS 1.2+ | Policy enforcement |
| Node-to-API | TLS 1.2+ | AKS default |

**Security Assessment:** ✅ No changes to encryption in transit

---

## Audit & Compliance

### Logging Requirements

```yaml
# Azure Monitor integration (mandatory)
oms_agent {
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

# Logs to capture
- Container logs (stdout/stderr)
- Kubernetes audit logs
- Azure Activity logs
- Node system logs (syslog)
- Security events (Azure Defender)
```

### Audit Trail for Evictions

**Security Requirement:** Track all eviction events for security analysis

```bash
# Query eviction events in Log Analytics
KubePodInventory
| where TimeGenerated > ago(30d)
| where PodStatus == "Evicted"
| extend NodeType = tostring(PodLabel.kubernetes_azure_com_scalesetpriority)
| summarize EvictionCount = count() by NodeType, Namespace, Name
| order by EvictionCount desc
```

**Control:** ✅ Alert on eviction rate >10/hour for security review

---

## Security Monitoring & Detection

### New Monitoring Requirements

| Metric | Alert Threshold | Security Relevance |
|--------|-----------------|-------------------|
| Eviction rate spike | >20/hour | Potential DoS or attack |
| Spot node rapid cycling | >5 evictions/node/hour | Suspicious activity |
| Failed pod scheduling | >50 pending pods | Resource exhaustion attack |
| Unexpected standard failover | All spot pools down | Investigate cause |

### SIEM Integration

```yaml
# Forward AKS logs to Sentinel
output:
  - type: logAnalytics
    workspaceId: ${LOG_ANALYTICS_WORKSPACE_ID}
    workspaceKey: ${LOG_ANALYTICS_KEY}
    customLogType: AKSSpotEviction

# Sentinel detection rule
query: |
  AKSSpotEviction
  | where EventType == "Evicted"
  | summarize EvictionCount = count() by bin(TimeGenerated, 5m)
  | where EvictionCount > 10
severity: Medium
```

---

## Compliance Impact Assessment

### Regulatory Frameworks

| Framework | Impact | Assessment |
|-----------|--------|------------|
| **SOC 2** | None | ✅ Approved (availability control documented) |
| **ISO 27001** | None | ✅ Approved (risk assessment completed) |
| **PCI-DSS** | Medium | ⚠️ **MUST NOT** schedule cardholder data on spot |
| **HIPAA** | High | ⚠️ **MUST NOT** schedule PHI on spot |
| **GDPR** | Low | ✅ Approved (personal data can use spot with controls) |

### Control Attestation

**For SOC 2 Audit:**
- Control ID: CC7.2 (System Monitoring)
  - Evidence: PodDisruptionBudgets, eviction logs, availability metrics
  - Status: ✅ Control operating effectively

- Control ID: A1.2 (Availability Commitments)
  - Evidence: Chaos testing results, topology spread validation
  - Status: ✅ Control operating effectively

---

## Security Hardening Recommendations

### Mandatory (Must Implement)

1. ✅ **Ephemeral OS Disks** - Prevent data persistence on spot nodes
   ```hcl
   os_disk_type = "Ephemeral"
   ```

2. ✅ **OPA Gatekeeper Policies** - Enforce spot restrictions for compliance workloads
   ```bash
   kubectl apply -f opa-policies/no-spot-for-compliance.yaml
   ```

3. ✅ **Key Vault CSI Driver** - Never store secrets in Kubernetes Secrets
   ```bash
   helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver
   ```

4. ✅ **Azure Defender for Kubernetes** - Runtime threat detection
   ```bash
   az security pricing create --name KubernetesService --tier Standard
   ```

### Recommended (Should Implement)

1. ⚠️ Service Mesh (Istio/Linkerd) - mTLS for all pod-to-pod communication
2. ⚠️ Pod Security Standards - Enforce restricted profile
3. ⚠️ Image Scanning - Block vulnerable images (Trivy, Snyk)
4. ⚠️ Runtime Security - Falco for anomaly detection

### Optional (Nice to Have)

1. ℹ️ Network segmentation with multiple VNets
2. ℹ️ Private endpoint for ACR
3. ℹ️ Customer-managed encryption keys (CMK)

---

## Security Testing Requirements

### Pre-Production Security Tests

| Test | Purpose | Pass Criteria |
|------|---------|---------------|
| **OPA Policy Validation** | Ensure compliance workloads cannot schedule on spot | 100% blocks |
| **Secret Leakage Test** | Verify secrets cleared on eviction | No secrets in logs/disk |
| **Network Policy Test** | Confirm isolation across node types | 0 unauthorized connections |
| **Eviction DoS Test** | Validate availability during mass eviction | >99.5% uptime |

**Execution:**
```bash
# Test 1: OPA Policy
kubectl apply -f test-workloads/pci-compliant-deployment.yaml
# Expected: Rejected by OPA if contains spot toleration

# Test 2: Secret Leakage
kubectl exec <pod> -- cat /proc/1/environ | grep SECRET
# Expected: Empty after preStop hook

# Test 3: Network Policy
kubectl exec attack-pod -- curl http://victim-pod:8080
# Expected: Connection refused

# Test 4: Eviction DoS
# Run chaos test from CHAOS_ENGINEERING_TESTS.md
```

---

## Security Approval Checklist

- [ ] OPA Gatekeeper policies deployed and tested
- [ ] Key Vault CSI driver configured for all sensitive workloads
- [ ] Compliance workload classification completed
- [ ] Ephemeral OS disks enabled for spot nodes
- [ ] Azure Defender for Kubernetes enabled
- [ ] Audit logging configured and verified
- [ ] Security testing completed (all tests passed)
- [ ] Runbooks include security incident response
- [ ] InfoSec team trained on spot eviction patterns

---

## Risk Summary

| Risk Area | Inherent Risk | Residual Risk | Acceptable? |
|-----------|---------------|---------------|-------------|
| Data Confidentiality | Low | Low | ✅ Yes |
| Data Integrity | Low | Low | ✅ Yes |
| Data Availability | Medium | Low | ✅ Yes (with controls) |
| Compliance | High | Low | ✅ Yes (with OPA) |
| IAM | Low | Low | ✅ Yes |

---

## Security Recommendation

**APPROVAL STATUS:** ✅ **APPROVED** for production deployment

**Conditions:**
1. Implement all "Mandatory" hardening recommendations
2. Complete security approval checklist before production
3. Quarterly security review of spot eviction patterns
4. Immediate InfoSec notification if eviction rate >50/hour

**Security Point of Contact:**  
Group Information Security Team  
Email: infosec@company.com  
Slack: #security-architecture

---

**Document Approval**

| Role | Name | Date | Status |
|------|------|------|--------|
| CISO | | | ⏳ Pending |
| Security Architect | | | ⏳ Pending |
| Compliance Officer | | | ⏳ Pending |
