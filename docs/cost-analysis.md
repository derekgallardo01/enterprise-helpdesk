# Enterprise Help Desk — Cost Analysis & TCO

## Overview

This document provides a complete cost breakdown for the Enterprise Help Desk Portal across Microsoft licensing, Azure consumption, and operational costs. It includes a Total Cost of Ownership (TCO) comparison against commercial ITSM alternatives.

## Microsoft 365 & Power Platform Licensing

### Required Licenses (Per User)

| License | Who Needs It | Monthly Cost | Notes |
|---------|-------------|-------------|-------|
| Microsoft 365 E3/E5 | All employees | $36 / $57 | Typically already provisioned; includes SharePoint, Teams, Entra ID |
| Power Apps per-user | Agents + Managers (~60 users) | $20 | Required for model-driven app (agent console) |
| Power Automate per-user | Included with Power Apps | $0 | Premium flows included with Power Apps per-user license |
| Power BI Pro | Report consumers (~20 users) | $10 | Required to view shared Power BI reports; included in M365 E5 |
| Copilot Studio messages | All employees (via Teams) | Usage-based | $200/month for 25,000 messages; ~$0.008/message |

### License Cost Summary

| Tier | Users | Agents | Power Apps | Power BI Pro | Copilot Studio | Monthly License Cost |
|------|-------|--------|-----------|-------------|----------------|---------------------|
| Small | 50 | 5 | $100 | $50 | $200 | **$350** |
| Medium | 500 | 50 | $1,000 | $200 | $200 | **$1,400** |
| Large | 5,000 | 200 | $4,000 | $500 | $400 | **$4,900** |
| Enterprise | 50,000 | 500 | $10,000 | $4,950* | $1,000 | **$15,950** |

*Enterprise tier assumes Power BI Premium per-capacity ($4,950/month) instead of per-user licensing.

**Key assumption:** M365 E3/E5 licenses are already provisioned and not counted as incremental cost.

### License Optimization Strategies

1. **Power Apps per-app ($5/user/app)**: If <4 apps are used, per-app licensing is cheaper than per-user for casual users
2. **Power BI included in E5**: Organizations on M365 E5 already have Power BI Pro included — no incremental cost
3. **Copilot Studio**: Message pool is shared across all bots; monitor usage to right-size
4. **Developer environments**: Free for development/testing; no license cost for Dev/Test environments

## Azure Consumption Costs

### Monthly Azure Costs by Tier

| Component | Small | Medium | Large | Enterprise |
|-----------|-------|--------|-------|------------|
| **Azure Functions** | | | | |
| Consumption plan (executions) | $0* | $2 | N/A | N/A |
| Premium plan (EP1) | N/A | N/A | $155 | $155 |
| Premium plan (EP2) | N/A | N/A | N/A | $310 |
| **Azure SQL Database** | | | | |
| Basic (5 DTU, 2 GB) | $5 | N/A | N/A | N/A |
| Standard S0 (10 DTU, 250 GB) | N/A | $15 | N/A | N/A |
| Standard S2 (50 DTU, 250 GB) | N/A | N/A | $75 | N/A |
| Standard S4 (200 DTU, 250 GB) | N/A | N/A | N/A | $300 |
| Geo-replication (secondary) | N/A | N/A | N/A | $300 |
| **Application Insights** | | | | |
| Data ingestion (GB/month) | $0** | $5 | $25 | $100 |
| **Log Analytics** | | | | |
| Data ingestion (GB/month) | $0** | $3 | $15 | $60 |
| **Key Vault** | | | | |
| Operations | $0 | $1 | $1 | $5 |
| **Azure Front Door** | N/A | N/A | N/A | $35 |
| **CDN (SPFx assets)** | N/A | N/A | $5 | $10 |
| **Total Azure** | **$5** | **$26** | **$276** | **$1,275** |

*Azure Functions Consumption plan includes 1M free executions/month.
**Application Insights includes 5 GB free ingestion/month.

### Azure Cost Optimization

1. **Reserved capacity**: Azure SQL 1-year reserved saves ~33% ($75 → $50 for S2)
2. **Consumption plan**: Sufficient for Small/Medium tiers; only upgrade when cold start latency impacts SLA monitoring
3. **Log sampling**: Configure Application Insights adaptive sampling to reduce ingestion at scale
4. **Retention tuning**: Reduce App Insights retention from 90 to 30 days for non-critical data

## Total Monthly Cost Summary

| Tier | Licensing | Azure | Total Monthly | Annual |
|------|-----------|-------|---------------|--------|
| Small (50 users) | $350 | $5 | **$355** | **$4,260** |
| Medium (500 users) | $1,400 | $26 | **$1,426** | **$17,112** |
| Large (5,000 users) | $4,900 | $276 | **$5,176** | **$62,112** |
| Enterprise (50,000 users) | $15,950 | $1,275 | **$17,225** | **$206,700** |

## TCO Comparison vs. Commercial ITSM

### Pricing Assumptions

| Product | Pricing Model | Agent License | Requester License |
|---------|--------------|--------------|-------------------|
| **This System** | Power Platform + Azure | $20/agent/month | $0 (M365 included) |
| **ServiceNow ITSM** | Per agent | $100-150/agent/month | $0 (portal included) |
| **Jira Service Management** | Per agent (tiered) | $22-50/agent/month | $0 (portal included) |
| **Zendesk Suite** | Per agent (tiered) | $55-115/agent/month | $0 (portal included) |
| **Freshdesk** | Per agent (tiered) | $15-79/agent/month | $0 (portal included) |

### 3-Year TCO Comparison (Medium Tier: 500 users, 50 agents)

| Cost Category | This System | ServiceNow | Jira SM | Zendesk |
|---------------|-------------|------------|---------|---------|
| Agent licensing (3 yr) | $36,000 | $180,000-$270,000 | $39,600-$90,000 | $99,000-$207,000 |
| Azure infrastructure (3 yr) | $936 | Included | Included (Cloud) | Included |
| Implementation (one-time) | $15,000-25,000* | $50,000-150,000 | $10,000-30,000 | $5,000-15,000 |
| Customization/year | $5,000 | $20,000-50,000 | $10,000-20,000 | $5,000-15,000 |
| Training | $2,000 | $5,000-10,000 | $2,000-5,000 | $2,000-5,000 |
| **3-Year TCO** | **$68,936** | **$295,000-$580,000** | **$81,600-$185,000** | **$126,000-$277,000** |

*Implementation cost assumes internal team build using this repo as accelerator.

### When This System Wins

- Organization already has M365 E3/E5 (licensing delta is minimal)
- Deep Microsoft Teams integration is a priority
- Customization requirements exceed what commercial ITSM allows without expensive professional services
- Data sovereignty requires all data in org-controlled Azure tenancy
- IT team has Power Platform / Azure skills

### When Commercial ITSM Wins

- >200 agents (ServiceNow's enterprise features justify cost at scale)
- Need pre-built ITIL process library (incident, problem, change, CMDB)
- Multi-tenant SaaS is preferred over self-managed infrastructure
- Organization lacks Power Platform / Azure expertise
- Need 24/7 vendor support SLA

## One-Time Setup Costs

| Activity | Internal Team | Consultant |
|----------|--------------|------------|
| Azure infrastructure provisioning | 4 hrs | $800 |
| Dataverse schema + security roles | 10 hrs | $2,000 |
| Power Automate workflows | 7 hrs | $1,400 |
| Canvas app | 9 hrs | $1,800 |
| SPFx web parts | 14 hrs | $2,800 |
| Azure Functions completion | 9 hrs | $1,800 |
| Power BI reports | 7 hrs | $1,400 |
| Copilot Studio bot | 7 hrs | $1,400 |
| Operational readiness (docs, IaC, monitoring) | 12 hrs | $2,400 |
| Testing & hardening | 10 hrs | $2,000 |
| UAT & rollout | 6 hrs | $1,200 |
| **Total** | **~91 hrs** | **$19,800** |

*Consultant rate assumed at $200/hr.

## Cost Monitoring

### Azure Cost Alerts

Configure Azure Cost Management alerts:
- **Budget alert**: Monthly Azure spend exceeds $50 (Medium tier threshold)
- **Anomaly alert**: Any single day cost >3x daily average
- **Forecast alert**: Projected monthly spend exceeds budget by >20%

### License Utilization Review

Quarterly review checklist:
- [ ] Power Apps licenses: Are all assigned licenses actively used? (check 30-day activity)
- [ ] Power BI Pro licenses: Are all assigned users accessing reports? (check usage metrics)
- [ ] Copilot Studio messages: Is message pool utilization >70%? (right-size if <30%)
- [ ] Azure Functions: Is consumption plan still sufficient or should we upgrade to Premium?
- [ ] Azure SQL: Is current DTU tier >70% utilized? Scale up/down as needed.
