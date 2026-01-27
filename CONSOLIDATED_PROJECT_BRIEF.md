# 📄 Consolidated Project Brief: AKS Spot Node Optimization

## 🎯 Overview
This project implements a production-grade cost-optimization strategy for Azure Kubernetes Service (AKS) by leveraging **Azure Spot Virtual Machines**. The goal is to run up to **75% of compute capacity** on Spot nodes, achieving an estimated **50-58% reduction in cloud spend** while maintaining **99.9% availability**.

## 🏗️ Architecture Summary
The solution ensures resilience through a multi-layered approach:
1. **Multi-Pool Strategy**: Distributes workloads across multiple Spot node pools using diverse VM families (e.g., D-series, E-series) and availability zones to minimize simultaneous eviction risks.
2. **Priority-Based Scaling**: Uses the Kubernetes Cluster Autoscaler with a `Priority Expander` to prefer Spot nodes and automatically fall back to On-Demand nodes if Spot capacity is unavailable.
3. **Resilient Workload Configuration**: Deployments are optimized with Pod Disruption Budgets (PDBs), Topology Spread Constraints, and Graceful Shutdown handling.

## 💰 Business Case & Metrics
- **Current Annual Spend**: ~$500,000
- **Target Annual Savings**: ~$260,000 (52% reduction)
- **Payback Period**: ~3 months
- **3-Year NPV**: ~$780,000
- **Success Criteria**: 70%+ of eligible workloads on Spot, <1 spot-related incident per month.

## 🛠️ Key Deliverables
- **Infrastructure**: Terraform modules for optimized AKS clusters.
- **Manifests**: Production-ready deployment templates (Spot-tolerant vs. Standard-only).
- **Chaos Testing**: Validated scenarios for multi-pool evictions and autoscaler delays.
- **Operations**: SRE Runbooks, DevOps Migration Guide, and [Spot Eviction Scenarios & Solutions](docs/SPOT_EVICITION_SCENARIOS.md).
- **Testing**: [Automated Go Tests](tests/), [Manual Eviction Manifests](tests/manifests/), and [Robot Shop Polyglot Test Suite](tests/robot-shop-spot-config/).

## ⚠️ Risk Management
- **Eviction Storms**: Mitigated by multi-pool diversity and PDBs.
- **Stateful Workloads**: Explicitly excluded from Spot nodes via hard anti-affinity.
- **Capacity Shortage**: Managed via automated fallback to On-Demand nodes.
- **See Also**: [Principal Engineer Audit](docs/PRINCIPAL_ENGINEER_AUDIT.md) for a comprehensive risk assessment.

## 🚀 Roadmap
- **Phase 1: Foundation**: Infrastructure deployment and monitoring setup.
- **Phase 2: Pilot**: Migration of dev/test workloads and chaos validation.
- **Phase 3: Production**: Graduated rollout to 80% of stateless workloads.
- **Phase 4: Optimization**: Ongoing tuning and predictive scaling.

---

## 🤖 AI Maintenance Workflow
> [!IMPORTANT]
> This document is the **Single Source of Truth** for the project. Every AI agent working on this repository MUST update this document after completing any significant task (e.g., adding features, updating infrastructure, or changing metrics). 
> 
> Follow the [Maintenance Workflow](.agent/workflows/maintenance.md) for updates.

---
**Last Updated**: 2026-01-27 (Principal Engineer Audit completed)  
**Status**: ✅ Ready for production rollout pilot
