# Azure Kubernetes Service (AKS) Architecture Design (2026 Ready)

## 1. Executive Summary

This design document outlines a comprehensive, future-proof architecture for a general-purpose, enterprise-grade Azure Kubernetes Service (AKS) platform. Designed with a **2026 perspective**, it leverages the latest Azure advancements—including **Cilium-powered networking**, **Application Gateway for Containers (AGC)**, and **Entra Workload ID**—to ensure long-term stability, security, and scalability.

The architecture strictly adheres to the **Azure Well-Architected Framework**, prioritizing Security (Zero Trust), Reliability, and Operational Excellence. It is tailored for **Hard Multi-tenancy**, ensuring strict isolation between diverse workloads sharing the same cluster.

### Key Technology Decisions

| Domain | Technology Selection | Justification (2026 Perspective) |
| :--- | :--- | :--- |
| **Networking** | **Azure CNI Overlay + Cilium** | Replaces legacy Azure CNI. Uses eBPF for high-performance dataplane, advanced security policies, and eliminates IP exhaustion issues. |
| **Ingress** | **Application Gateway for Containers (AGC)** | The successor to AGIC. Fully supports Kubernetes Gateway API, traffic splitting, and superior performance. |
| **Identity** | **Entra Workload ID** | Replaces Pod Identity. Standard, secure, federation-based identity management for pods. |
| **Observability** | **Azure Managed Prometheus & Grafana** | Fully managed, scalable monitoring stack replacing self-hosted solutions. |
| **Cost** | **OpenCost + Azure Cost Management** | Granular, namespace-level cost attribution for multi-tenant chargeback. |

---

## 2. High-Level Architecture

The solution implements a **Hub-and-Spoke** network topology to centralize shared services (Firewall, DNS, Bastion) while isolating the AKS workload.

### 2.1 Logical Architecture

```mermaid
graph TD
    subgraph "Hub VNet"
        FW[Azure Firewall Premium]
        Bastion[Azure Bastion]
        DNS[Private DNS Resolver]
    end

    subgraph "Spoke VNet (AKS)"
        AGC[App Gateway for Containers]

        subgraph "AKS Cluster (Private)"
            API[API Server <br/> (Private Endpoint)]

            subgraph "System Node Pool"
                Cilium[Cilium Agent]
                CoreDNS
                Metrics[AMA Metrics]
            end

            subgraph "User Node Pool (Team A)"
                AppA[App A Pods]
            end

            subgraph "User Node Pool (Team B)"
                AppB[App B Pods]
            end
        end
    end

    Internet --> FW
    FW --> AGC
    AGC --> AppA
    AGC --> AppB
    Bastion -.-> API
    API <--> Cilium
```

### 2.2 Networking Design

We adopt the **Azure CNI Overlay** network plugin powered by **Cilium**.

*   **Overlay Mode:** Pods receive IPs from a private CIDR (e.g., `10.244.0.0/16`) that does not consume VNet IP addresses. The VNet only sees Node IPs. This simplifies IP planning significantly compared to legacy Azure CNI.
*   **Cilium Dataplane:** Replaces `iptables` with **eBPF**. This provides:
    *   **Performance:** Near metal network speeds.
    *   **Security:** Identity-aware network policies (L3/L4/L7).
    *   **Observability:** Hubble (if enabled) or deep flow logs.
*   **Egress Traffic:** All egress traffic is routed through **Azure Firewall Premium** in the Hub VNet for FQDN filtering and IDPS.

### 2.3 Compute Design

The cluster is divided into dedicated node pools to separate system concerns from user workloads.

*   **System Node Pool:**
    *   **Purpose:** Runs critical cluster services (CoreDNS, Cilium, Metrics Agents, Ingress Controllers).
    *   **Configuration:** `CriticalAddonsOnly=true` taint.
    *   **VM SKU:** `Standard_D4s_v5` (General Purpose).
*   **User Node Pools (Spot & On-Demand):**
    *   **Purpose:** Runs application workloads.
    *   **Configuration:** Autoscaling enabled (`min: 2`, `max: 20`).
    *   **VM SKU:** `Standard_E8s_v5` (Memory Optimized) for general enterprise Java/Go apps.
    *   **Isolation:** Hard separation possible via `nodeSelector` or dedicated pools per tenant if required.

---

## 3. Identity & Security (Hard Multi-Tenancy)

To support **Hard Multi-tenancy** (multiple teams sharing the cluster with strict isolation), we implement a "Zero Trust" security model.

### 3.1 Identity Management: Entra Workload ID

We utilize **Microsoft Entra Workload ID** (formerly Azure AD Pod Identity) for all pod authentication.

*   **Mechanism:** Uses Kubernetes Service Account Token Volume Projection and OIDC federation.
*   **Benefit:** No secrets/passwords stored in the cluster. Pods exchange their K8s Service Account token for an Azure AD Access Token.
*   **Implementation:**
    *   Each Tenant/Application gets a dedicated User Managed Identity (UMI).
    *   Federated credential established between UMI and the K8s Service Account.

### 3.2 Hard Multi-Tenancy Strategy

Isolation is enforced at multiple layers to prevent "noisy neighbor" issues and cross-tenant data access.

| Layer | Control | Implementation Details |
| :--- | :--- | :--- |
| **Logical** | **Namespaces** | Each tenant gets a dedicated namespace (e.g., `tenant-a-prod`). |
| **Network** | **Cilium Network Policies** | **Default Deny** policy applied to all namespaces. Explicit allow rules required for intra-namespace communication. Cross-namespace traffic is blocked by default. |
| **Compute** | **Resource Quotas** | Strict CPU/Memory Requests & Limits per namespace to prevent resource starvation. |
| **Storage** | **Storage Classes** | Dynamic provisioning with distinct Storage Accounts per tenant (if strict data isolation is required) or shared storage with strict RBAC. |
| **Runtime** | **Pod Security Standards** | Enforce **Restricted** profile (no privileged containers, root users, or host path mounts) via Azure Policy (Gatekeeper). |

#### 3.2.1 Sample Cilium Network Policy (Default Deny)

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny
  namespace: tenant-a
spec:
  endpointSelector: {}
  policyEnabled: true
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
  egress:
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
```


### 3.4 Advanced Security Controls

#### 3.4.1 Policy Enforcement: Azure Policy (Gatekeeper)
We enforce organizational standards using **Azure Policy for Kubernetes**, which manages the OPA Gatekeeper admission controller.

*   **Mandatory Policies:**
    *   **Privileged Containers:** Deny.
    *   **Root User:** Deny running as root (MustRunAsNonRoot).
    *   **Allowed Registries:** Only allow images from the private Azure Container Registry (ACR).
    *   **Internal Load Balancers:** Deny creation of public IPs for Services.

#### 3.4.2 Secret Management
We recommend **External Secrets Operator (ESO)** for high-scale secret management.

*   **Mechanism:** ESO runs in the cluster and polls **Azure Key Vault**.
*   **Authentication:** Uses Workload Identity to authenticate to Key Vault (Zero Trust).
*   **Advantage:** Superior to the CSI Driver for scaling (caching secrets) and supports mirroring secrets to Kubernetes `Secret` objects for native application consumption.

#### 3.4.3 Supply Chain Security
*   **Image Cleaning:** Enable **Image Cleaner** (Eraser) to automatically remove unused vulnerability-laden images from nodes.
*   **Signature Verification:** Use **Ratify** + Gatekeeper to verify that only images signed by the CI pipeline (via Notary Project) can be deployed.

#### 3.4.4 Node Hardening
*   **OS:** **Azure Linux (Mariner)** is the preferred Host OS for 2026 (smaller attack surface than Ubuntu).
*   **Access:** **SSH Access Disabled** by default. Debugging is performed via `kubectl debug` ephemeral containers only.

### 3.3 Ingress Strategy: Application Gateway for Containers (AGC)

For 2026, we adopt **Application Gateway for Containers (AGC)** over the legacy AGIC.

*   **Architecture:** AGC lives outside the cluster (fully managed PAAS) but integrates directly via the **ALB Controller** running in the System Node Pool.
*   **API Standard:** We use the **Kubernetes Gateway API** (`gateway.networking.k8s.io`) instead of the legacy Ingress API for richer traffic management.
*   **Multi-Tenancy:**
    *   **One AGC per Cluster** (shared infrastructure).
    *   **Listeners/Routes** separated by hostname (`team-a.corp.com`, `team-b.corp.com`).
    *   **WAF Policies:** Attached at the listener level to apply specific security rules per tenant.

#### 3.3.1 Best Practices
*   **End-to-End TLS:** TLS terminated at AGC, then re-encrypted to the Pod (Zero Trust).
*   **Private Ingress:** AGC is deployed with a Private Frontend IP (internal Load Balancer) to ensure no exposure to the public internet. Access is mediated via the Hub Firewall or VPN.

---

## 4. Observability & FinOps

A 2026-ready architecture moves away from self-hosted monitoring stacks (e.g., in-cluster Prometheus) to fully managed Azure native services to reduce operational overhead.

### 4.1 Observability Stack

| Component | Service | Details |
| :--- | :--- | :--- |
| **Metrics** | **Azure Monitor Managed Service for Prometheus** | Scrapes metrics from the cluster. Replaces local Prometheus server. |
| **Visualization** | **Azure Managed Grafana** | Connects to the Managed Prometheus workspace. Provides out-of-the-box dashboards for Cilium, Kubernetes, and Node performance. |
| **Logs** | **Container Insights (Log Analytics)** | configured with **Basic Logs** plan for high-volume verbose logs (cost optimization) and **Analytics Logs** for critical alerts. |

#### 4.1.1 Cilium Hubble
*   **Hubble UI:** Enabled via AKS addon for visualizing network flows.
*   **Flow Logs:** Exported to Azure Monitor for forensic analysis of dropped packets or policy denials.

### 4.2 FinOps Strategy

Multi-tenancy requires strict cost accountability. We implement **OpenCost** integrated with Azure Cost Management.

*   **Tooling:** OpenCost (Standard CNCF project).
*   **Mechanism:**
    *   OpenCost queries the Azure Billing API to get real-time spot/on-demand pricing.
    *   Allocates costs based on `namespace` and `label` breakdown.
    *   Idle costs are identified and charged back to a "Common Infrastructure" cost center.
*   **Reporting:**
    *   Dashboards showing "Cost per Tenant" (Namespace).
    *   Budgets and Alerts configured in Azure Cost Management to trigger when a Tenant exceeds their monthly forecast.


---

## 5. Cluster Lifecycle & Operations

### 5.1 Upgrade Strategy

We adopt an automated, channel-based upgrade strategy to minimize toil and ensure security compliance.

*   **Node Image Upgrades:**
    *   **Channel:** `NodeImage` (Automated).
    *   **Frequency:** Weekly.
    *   **Mechanism:** Azure automatically reimages nodes with the latest OS patches and container runtime updates. This uses **Surge** upgrades (extra nodes spun up) to prevent capacity loss.
*   **Kubernetes Version Upgrades:**
    *   **Channel:** `Stable` (Automated).
    *   **Strategy:** N-1 version policy.
    *   **Safety:** **Pod Disruption Budgets (PDBs)** must be defined for all tenant workloads to ensure Zero Downtime during rolling upgrades.

### 5.2 Infrastructure as Code & CI/CD

We adhere to a strict **Infrastructure as Code (IaC)** methodology using Terraform or Bicep.

*   **Tooling:** Terraform (State in Azure Storage) or Bicep.
*   **Pipeline:** Azure DevOps or GitHub Actions.
*   **Workflow:**
    1.  **Plan:** PR triggers a `terraform plan` to validate changes.
    2.  **Apply:** Merge to `main` triggers `terraform apply`.
    3.  **No Manual Changes:** Direct `kubectl` access is restricted; all cluster config changes must go through the pipeline.

### 5.3 Advanced Networking

*   **Private Link Service:** Used to expose internal services to other VNets/Consumers without peering.
*   **NAT Gateway:** Associated with the AKS subnet to ensure a static, deterministic outbound IP for all egress traffic (simplified allowlisting).

### 5.4 Compute Placement

*   **Proximity Placement Groups (PPG):** Optional for latency-sensitive workloads to co-locate nodes physically.
*   **Availability Zones:** Strict distribution across Zones 1, 2, and 3 for both System and User node pools to ensure 99.95% SLA.

### 5.5 Disaster Recovery & Reliability

#### 5.5.1 Backup Strategy
*   **Tool:** **Azure Backup for AKS**.
*   **Scope:**
    *   **Cluster State:** ETCD snapshots (Namespace, Deployment, Service definitions).
    *   **Persistent Data:** CSI Snapshots of Azure Disks/Files.
*   **Schedule:** Daily backups with 30-day retention. Cross-region restore enabled.

#### 5.5.2 Chaos Engineering
To validate the 99.95% SLA, we integrate **Azure Chaos Studio**.
*   **Experiments:**
    *   **Pod Chaos:** Randomly kill pods in the System nodepool to verify HA.
    *   **Network Chaos:** Simulate latency between Spoke and Hub VNet.
    *   **Node Chaos:** Simulate node eviction (Spot) or failure.

#### 5.5.3 Region Failover Plan
1.  **Trigger:** Critical Region Outage (Traffic Manager/Front Door detects 5xx).
2.  **Action:** CI/CD Pipeline deploys Terraform to the Paired Region.
3.  **Hydration:** Azure Backup restores the latest "Gold" configuration state.
4.  **RTO:** Target < 4 hours.
---

## 7. Summary of Recommendations

1.  **Network:** Use **Azure CNI Overlay + Cilium** for best performance and security.
2.  **Ingress:** Migrate to **Application Gateway for Containers (AGC)**.
3.  **Security:** Enforce **Hard Multi-tenancy** with Namespaces, Network Policies, and Workload Identity.
4.  **Operations:** Automate upgrades via **Stable** channels and use **IaC/CI/CD** for all changes.
5.  **Cost:** Implement **OpenCost** for precise showback/chargeback.

## 6. Operational Procedures

### 6.1 Access Control (PIM)
Direct cluster access is restricted. For emergency "Break-Glass" scenarios:
*   **Tool:** **Entra Privileged Identity Management (PIM)**.
*   **Process:** Admins request "Cluster Admin" role activation for a limited duration (e.g., 4 hours).
*   **Audit:** All actions logged to Azure Monitor Audit Logs.

### 6.2 Troubleshooting Standard Operating Procedure (SOP)
Since SSH is disabled, debugging follows a strict cloud-native pattern:
1.  **Log Analysis:** Check Container Insights (Log Analytics) first.
2.  **Network Debug:** Use `kubectl debug` to attach an ephemeral container (e.g., `netshoot`) to the target pod.
    ```bash
    kubectl debug -it pod/target-app --image=nicolaka/netshoot --target=target-app
    ```
3.  **Node Debug:** Use `kubectl debug node/aks-node-1` to launch a privileged container on the host.

---
