# Scalability Review: 300+ Node AKS Cluster with Spot Architecture

**Document Version:** 1.0  
**Date:** 2026-01-12  
**Purpose:** Identify scalability gaps, limits, and missing failure scenarios for large-scale (300+ node) implementation of the Spot-Optimized Architecture.

---

## ⚠️ Critical Scalability Allocations

### 1. Subnet Sizing (IMMEDIATE ACTION REQUIRED)
**Current Config:** `/22` CIDR (1,024 IP addresses)
**Issue:** 
- A 300-node cluster using Azure CNI requires 1 IP per Node + 1 IP per Pod.
- If `max_pods = 30` (typical per node), 300 nodes need:
  - 300 IPs (Nodes)
  - 9,000 IPs (Pods) (300 * 30)
- **Result:** `/22` is vastly insufficient (supports ~30 nodes with max_pods=30).

**Recommendation:**
- **Switch to Overlay Networking (Kubenet/Azure CNI Overlay):**
  - Only needs IPs for nodes (300 IPs).
  - `/22` supports ~1,000 nodes.
- **OR Expand Subnet (Azure CNI):**
  - Requires `/18` (16,384 IPs) or larger for 300 nodes + pods.
- **Mitigation:** Update Terraform to use `network_plugin_mode = "overlay"` if sticking with `/22`.

### 2. Control Plane Performance
**Issue:**
- 300+ nodes generate excessive API server load from Kubelet heartbeats, DaemonSets, and Watch events.
- Spot evictions cause "thundering herd" API calls as hundreds of pods reschedule simultaneously.

**Recommendation:**
- Enable **AKS Standard Tier (Uptime SLA)** (ensures higher resource limits for control plane).
- Tune `scan_interval` in Autoscaler profile: Increase from `10s` to `30s` or `60s` to reduce API pressure.
- **System Node Pool:** Increase to `Standard_D8s_v5` (8 vCPU) to handle CoreDNS/metrics-server load for large clusters.

### 3. Subscription Quotas (vCPU)
**Issue:**
- 300 nodes * 4 vCPU (avg) = 1,200 vCPUs.
- Default Azure subscription limits are often ~100-200 vCPUs.
- Spot cores have separate quota limits.

**Recommendation:**
- **Pre-emptive Ticket:** Request quota increase for:
  - Standard vCPUs (family D/E/F) to 2,000
  - Spot vCPUs (Total Regional Spot Limit) to 2,000
  - Spot vCPUs per family (D, F, E) specifically.

---

## 🚨 Missing Failure Scenarios (At Scale)

### Failure Scenario 8: Subnet IP Exhaustion (Deadlock)
**Scenario:** 
- Spot pool attempts to scale up.
- Nodes provision in Azure but fail to join cluster due to "No available IP in subnet".
- Autoscaler waits 15min (timeout), then retries indefinitely.
**Impact:**
- Cluster autoscaler gets stuck.
- Critical standard pool cannot expand during emergencies.
**Mitigation:**
- **Monitoring:** Alert on `subnet_usage > 80%`.
- **Architecture:** Use CNI Overlay (assigns private pod CIDR per node, independent of VNet).

### Failure Scenario 9: SNAT Port Exhaustion
**Scenario:**
- 300 nodes * 30 pods = 9,000 workloads making outbound connections.
- Standard Load Balancer has limit of 64,000 SNAT ports total (default distribution).
- High-traffic outbound apps (e.g., 3rd party API calls) fail with timeouts.
**Impact:** 
- Intermittent connectivity failures (external calls drop).
**Mitigation:**
- **Managed NAT Gateway:** Attach to AKS subnet (provides 64k-1M+ ports per IP).
- **Allocated Outbound Ports:** Tune `load_balancer_profile` in Terraform.

### Failure Scenario 10: "Thundering Herd" on Recovery
**Scenario:**
- 100 spot nodes evicted simultaneously (Event).
- 3,000 pods try to reschedule.
- **Control Plane Saturation:** API server throttles requests (429 Too Many Requests).
- **Container Registry Throttling:** ACR hits limits pulling images for 3,000 pods.
**Impact:**
- Recovery takes 30-60 minutes instead of 2 minutes.
- ImagePullBackOff errors widespread.
**Mitigation:**
- Use **ACR Teleport / P2P Distribution** (Dragonfly/Kraken).
- **Image Pull Policies:** Ensure `IfNotPresent` is used.
- **Priority Classes:** Ensure critical system pods preempt waiting workloads.

### Failure Scenario 11: ARP Table overflows (Azure CNI)
**Scenario:**
- In large Layer 2 networks, ARP broadcast traffic increases quadratically.
- 9,000 pods (Azure CNI) create massive ARP tables.
**Impact:**
- Network latency, packet drops.
**Mitigation:**
- Use **Azure CNI Overlay** (Layer 3 routing for pods, much smaller broadcast domain).

---

## 🛠 Required Terraform Adjustments for 300+ Nodes

### 1. Enable CNI Overlay (Recommended)
```hcl
# main.tf
network_profile {
  network_plugin      = "azure"
  network_plugin_mode = "overlay"  # CRITICAL for IP scalability
  pod_cidr            = "192.168.0.0/16"
  service_cidr        = "10.100.0.0/16"
  dns_service_ip      = "10.100.0.10"
}
```

### 2. Auto-Scaler Profile Tuning
```hcl
# variables.tf (default overrides)
autoscaler_profile = {
  scan_interval                = "20s"    # Less frequent scans for large clusters
  max_node_provisioning_time   = "20m"    # Allow more time for large batch provisioning
  scale_down_delay_after_add   = "20m"    # Prevent thrashing
  max_unready_nodes            = 10       # Allow more unready during massive scale-up
}
```

### 3. Load Balancer / NAT Gateway
```hcl
# main.tf
network_profile {
  outbound_type = "userDefinedRouting" # If using Firewall
  # OR
  load_balancer_sku = "standard"
  load_balancer_profile {
    outbound_ip_address_ids = [azurerm_public_ip.outbound.id]
    outbound_ports_allocated = 2048 # Tune based on nodes
  }
}
```

---

## Summary Checklist for Scaling to 300+

- [ ] **Network:** Switch to CNI Overlay or Expand Subnet to /18+.
- [ ] **Quota:** Request Azure vCPU quota increase for 2000+ cores.
- [ ] **Control Plane:** Upgrade to Standard Tier (SLA).
- [ ] **Data Plane:** Implement NAT Gateway for SNAT scalability.
- [ ] **Registry:** Configure specific ACR endpoints or caching.
- [ ] **Observability:** Ensure Prometheus/Grafana storage persistence logic handles high-cardinality metrics (300 nodes generates huge metric volume).

---
**Status:** Review Complete. Architecture requires networking and quota adjustments to support 300+ nodes safely.
