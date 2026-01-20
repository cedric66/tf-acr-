# Azure Kubernetes Service (AKS) Design Document

## 1. Introduction and Requirements

### 1.1 Business Context
This architecture is designed for a general-purpose enterprise platform hosting critical microservices. It prioritizes security (Zero Trust), scalability, and operational excellence to support [Business Goal: e.g., Rapid Modernization].

### 1.2 Non-Functional Requirements (NFRs)
| Metric | Target | Description |
| :--- | :--- | :--- |
| **Availability (SLA)** | 99.95% | Guaranteed via Availability Zones (3) and Uptime SLA. |
| **RTO** | 4 Hours | Time to restore service in a paired region. |
| **RPO** | 1 Hour | Max data loss tolerance (Geo-Redundant Backup). |
| **Scalability** | 1k-10k Pods | Supported via CNI Overlay and Autoscaling. |
| **Compliance** | PCI-DSS, CIS | Hardened nodes, FIPS compliance (optional), and Audit logging. |

### 1.3 Design Principles
*   **Infrastructure as Code (IaC):** 100% Terraform/Bicep. No manual changes.
*   **Immutable Infrastructure:** Nodes are replaced, not patched.
*   **Zero Trust:** "Never trust, always verify" networking and identity.

---

## 2. Architecture Overview

The solution follows a **Hub-and-Spoke** topology. The **Hub VNet** contains shared services (Firewall, Bastion), while the **Spoke VNet** hosts the AKS cluster and application resources.

```mermaid
architecture-beta
    group Hub["Hub VNet"]
        Firewall["Azure Firewall<br/>(Egress)"]
        Bastion["Azure Bastion"]

    group Spoke["Spoke VNet"]
        AppGW["App Gateway For Containers<br/>(WAF + Ingress)"]
        AKS["AKS Cluster<br/>(System/User Node Pools)"]
        ACR["ACR (Private Link)"]
        KV["Key Vault (CSI/ESO)"]

    User --> AppGW
    AppGW --> AKS
    AKS --> ACR
    AKS --> KV
    AKS -.-> Firewall : Egress UDRs
```

---

## 3. Networking Configuration

### 3.1 Network Plugin: Azure CNI Overlay
*   **Rationale:** Eliminates IP exhaustion. Pods get IPs from a private overlay CIDR (e.g., `10.244.0.0/16`) which is NAT"d to the node IP.
*   **Dataplane:** **Cilium** (eBPF) for high-performance policy enforcement.

### 3.2 IP Planning (Subnet Calculator)
| Subnet | Size | Purpose |
| :--- | :--- | :--- |
| **Hub Gateway** | /26 | VPN/ExpressRoute Gateway. |
| **Hub Firewall** | /26 | Azure Firewall Premium. |
| **Hub Bastion** | /26 | Azure Bastion Hosts. |
| **Spoke Nodes** | /20 | Hosts AKS Nodes (System + User). Supports ~4000 nodes. |
| **Spoke Ingress** | /24 | Application Gateway for Containers (ALB). |
| **Spoke PrivLink** | /24 | Private Endpoints (Key Vault, ACR, SQL). |

### 3.3 Egress Control
*   **User Defined Routes (UDR):** `0.0.0.0/0` next hop routed to Azure Firewall in the Hub.
*   **HTTP Proxy:** (Optional) For strict environments, inject `HTTP_PROXY` env vars to route non-transparent traffic.

---

## 4. Cluster Compute and Node Pools

### 4.1 Node Pool Separation
We separate System and User workloads to prevent noisy neighbors and ensure cluster stability.

| Pool Name | VM SKU | OS | Scaling | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **system** | `Standard_D2s_v5` | Azure Linux (Mariner) | Manual (3) | Critical addons (CoreDNS, Cilium, Metrics). |
| **user-gen** | `Standard_D4s_v5` | Azure Linux (Mariner) | Auto (2-20) | General purpose workloads. |
| **user-mem** | `Standard_E4s_v5` | Azure Linux (Mariner) | Auto (0-10) | Memory-intensive apps (Java/Redis). |

### 4.2 OS Configuration
*   **OS SKU:** **Azure Linux** (optimized for AKS).
*   **Auto-Upgrade:** `NodeImage` channel (Weekly surge upgrades).
*   **Hardening:** SSH disabled. Host access via `kubectl debug` only.

---

## 5. Identity and Access Management

### 5.1 Authentication
*   **Cluster Access:** **Entra ID** integration with Kubernetes RBAC.
*   **Local Accounts:** **Disabled** (`--disable-local-accounts`) to force Entra ID audit trails.

### 5.2 Managed Identities
*   **Control Plane:** User Assigned Managed Identity (UAMI) for Control Plane.
*   **Kubelet:** UAMI for Kubelet (pulling images from ACR).
*   **Workload Identity:** **Microsoft Entra Workload ID** for pods to access Azure resources (SQL, Key Vault) without secrets.

---

## 6. Security and Network Policies

### 6.1 Network Security
*   **Network Policies:** **Cilium Network Policies** (Default Deny).
*   **API Server:** **Private Cluster** (Private Link). Access via Bastion or Runners.

### 6.2 Application Security (WAF)
*   **WAF:** Application Gateway for Containers (AGC) with WAF policies enabled (OWASP 3.2).
*   **Scanning:** **Microsoft Defender for Containers** enabled for runtime threat detection.

---

## 7. Ingress/Egress and Secrets

### 7.1 Ingress Flow
We use **Application Gateway for Containers (AGC)** for 2026-ready ingress.

```flowchart TD
    User[End Users] -->|HTTPS/TLS| FrontDoor[Azure Front Door]
    FrontDoor --> WAF[App Gateway for Containers]
    WAF --> ILB[Internal Load Balancer]
    ILB --> Ingress[ALB Controller]
    Ingress --> Pods[Workload Pods]
    Pods --> DB[(Azure SQL DB)]
    Pods --> Cache[(Redis Cache)]
    Monitor[Azure Monitor] -.-> AKS
```

```sequenceDiagram
    participant Client
    participant AG as App Gateway (AGC)
    participant ALB as ALB Controller
    participant Pod as Workload Pod
    Client->>AG: HTTPS (TLS1.2+)
    AG->>ALB: Traffic Split / Header Routing
    ALB->>Pod: HTTP/gRPC (mTLS optional)
    Note over Pod: Workload ID Token Injected
```

### 7.2 Secret Management Strategy
We support two patterns based on scale and legacy requirements.

*   **Primary (Standard): Azure Key Vault Secret Store CSI Driver.**
    *   **Pros:** Native Microsoft support, simplest implementation.
    *   **Cons:** Higher Key Vault API costs at extreme scale.
*   **High-Scale (Alternative): External Secrets Operator (ESO).**
    *   **Pros:** Caches secrets, lower API costs, mirrors to K8s Secrets.
    *   **Cons:** Third-party operator.

---

## 8. Monitoring, Operations, and CI/CD

### 8.1 Observability
*   **Metrics:** Azure Managed Prometheus.
*   **Logs:** Container Insights (Basic Logs).
*   **Tracing:** Application Insights (OpenTelemetry).

### 8.2 CI/CD
*   **Tool:** GitHub Actions with **Actions Runner Controller (ARC)**.
*   **GitOps:** Infrastructure state in Terraform.
*   **Policy:** **Azure Policy** (Gatekeeper) enforces constraints (e.g., "No Public IPs").

---

## 9. Reliability and Backup

### 9.1 Resilience
*   **Zones:** All node pools deployed across Availability Zones 1, 2, 3.
*   **PDBs:** Pod Disruption Budgets mandated for all applications (minAvailable: 1).

### 9.2 Backup
*   **Service:** **Azure Backup for AKS**.
*   **Schedule:** Daily snapshots (7-day retention), Monthly vault tier (1-year retention).
*   **Redundancy:** GRS (Geo-Redundant) for cross-region restore.

---

## 10. Cost Optimization

### 10.1 Strategies
*   **Spot Instances:** Used for `user-batch` node pools (non-critical jobs).
*   **Reservations:** 1-year Reserved Instances (RI) for System Node Pool and Baseline User Pool.
*   **OpenCost:** Deployed for namespace-level cost attribution.
*   **Rightsizing:** Monthly review of "Wasted CPU/RAM" metrics via Azure Advisor.
