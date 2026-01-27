# AKS Spot Node Cost Optimization

**For:** Executive Leadership | **January 2026**

---

## 🎯 Project Objective

**Cut AKS compute costs by 50%+ across 300+ clusters using Azure Spot VMs**

- **Annual Savings:** $260,000
- **Payback:** 3 months
- **Availability:** 99.9% maintained

---

## 📊 Status

| Phase | State |
|-------|-------|
| Architecture & Planning | ✅ Complete |
| Terraform & Runbooks | ✅ Complete |
| Security Review | ✅ Approved |
| **Pilot (Next)** | 🔄 Starting Week 1 |
| Fleet Rollout | ⏳ 3-month phased plan |

---

## 🔗 Dependencies – What We Need From Each BU

| Business Unit | What We Need | When |
|---------------|--------------|------|
| **Finance** | Approve $30K implementation budget | Week 1 |
| **FinOps** | Set up cost monitoring & alerts | Week 1-2 |
| **Security** | Deploy OPA policies to clusters | Week 2 |
| **SRE** | On-call coverage for rollout | Week 3+ |
| **App Teams** | Update workloads with graceful shutdown | Waves 1-3 |
| **CloudOps** | Verify Azure vCPU quotas | Week 1 |

---

## ⚠️ Key Risks

| Risk | Impact | Status |
|------|--------|--------|
| Spot eviction storm | Service disruption | ✅ Mitigated (auto-fallback) |
| Regional price spike | Lower savings | ✅ Mitigated (price caps) |
| App misconfig on spot | Data/availability | ⚠️ Needs OPA policies |
| 300-cluster scale | Throttling/quota | ⚠️ Needs quota planning |

---

## 🤝 BU Support Required

| Team | Ask |
|------|-----|
| **Finance/FinOps** | Budget + monthly cost tracking |
| **Security** | Policy enforcement on all clusters |
| **SRE** | 24/7 monitoring during prod rollout |
| **App Teams** | Migrate 15,000 workloads over 3 months |

---

## 🏆 Success Metrics

| Metric | Target |
|--------|--------|
| Cost Reduction | **50%+** |
| Availability | **99.9%** |
| Spot Adoption | **70-80%** |
| Incidents/Month | **<1** |

---

**Decision Requested:** Approve pilot start & $30K budget

---

*Contact: Platform Engineering | #platform-architecture*
