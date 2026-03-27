# Enterprise Help Desk — Capacity Planning

## Overview

This document projects the system's resource consumption across all components and defines scaling triggers, cost implications, and monitoring strategies. The architecture described in [architecture.md](architecture.md) was designed to scale incrementally — each component can be upgraded independently without re-architecting the system.

## 1. Growth Assumptions

### Baseline (Year 0)

| Metric | Value |
|---|---|
| Tickets per day | 200 |
| Active users (requesters) | 500 |
| Agents | 50 |
| Managers / executives (Power BI) | 30 |
| KB articles | 200 |
| Average ticket comments | 4 per ticket |
| Average ticket size (Dataverse) | ~5 KB per ticket (including comments) |

### Growth Rates

| Metric | Annual Growth | Basis |
|---|---|---|
| Ticket volume | 15% | Historical IT demand curve + headcount growth |
| User base | 10% | Company hiring plan |
| KB articles | 20% | Knowledge-centered service adoption |
| Data storage | 20% | Ticket volume + richer content (attachments) |

### 3-Year Projection

| Metric | Year 0 | Year 1 | Year 2 | Year 3 |
|---|---|---|---|---|
| Tickets / day | 200 | 230 | 265 | 305 |
| Tickets / year | 52,000 | 59,800 | 68,770 | 79,085 |
| Cumulative tickets | 52,000 | 111,800 | 180,570 | 259,655 |
| Active users | 500 | 550 | 605 | 665 |
| Agents | 50 | 55 | 60 | 65 |
| Dataverse storage | 2 GB | 2.4 GB | 2.9 GB | 3.5 GB |
| Azure SQL storage | 500 MB | 600 MB | 720 MB | 865 MB |
| KB articles | 200 | 240 | 290 | 350 |

**Key takeaway**: At 15% annual growth, the system reaches ~300 tickets/day and ~260K cumulative tickets by Year 3. None of the component limits are breached at this scale with the default architecture.

## 2. Component Capacity Limits

| Component | Limit | Current Usage | Headroom | Scale Trigger | Action |
|---|---|---|---|---|---|
| Dataverse API (per user, interactive) | 6,000 req / 5 min | ~100 req / 5 min | 98% | >3,000 req / 5 min sustained | Batch API calls, reduce round-trips |
| Dataverse API (S2S, Azure Functions) | 40,000 req / 5 min | ~500 req / 5 min | 99% | >20,000 req / 5 min | Optimize sync queries, increase batch size |
| Dataverse storage (default) | 10 GB | ~2 GB | 80% | >8 GB | Purchase additional capacity ($40/GB/month) |
| Dataverse file storage | 20 GB (default) | ~500 MB | 97% | >16 GB | Purchase additional or offload to SharePoint |
| Azure SQL Basic DTU | 5 DTU | ~2 DTU | 60% | Sustained >4 DTU (80%) | Upgrade to S0 (10 DTU, ~$15/month) |
| Azure SQL storage (Basic) | 2 GB | ~500 MB | 75% | >1.5 GB | Upgrade tier (S0 = 250 GB) |
| Azure Functions (Consumption) | 200 concurrent executions | ~5 concurrent | 97% | >100 concurrent | Migrate to Premium plan |
| Azure Functions timeout | 10 min (Consumption) | ~30 sec avg | N/A | Any function approaching 5 min | Optimize or switch to Premium (unlimited) |
| Power Automate (per flow) | 100,000 actions / day | ~1,000 actions / day | 99% | >50,000 actions / day | Monitor growth, consider per-flow plan |
| Power Automate (standard connector) | 6,000 calls / 5 min | ~200 calls / 5 min | 97% | >3,000 calls / 5 min | Throttle-aware retry patterns |
| SharePoint list view threshold | 5,000 items | N/A (site pages, not lists) | N/A | N/A | KB uses site pages, not lists |
| SharePoint storage (tenant) | 25 TB | ~1 GB | 99%+ | N/A | Not a realistic concern |
| Power BI shared capacity | 8 dataset refreshes / day | DirectQuery (N/A) | N/A | >500 concurrent viewers | Upgrade to Power BI Premium per capacity |
| Power BI DirectQuery | 1M rows / query | ~50K rows typical | 95% | Query approaching 500K rows | Aggregation tables in SQL |
| Application Insights | 5 GB / month (free tier) | ~500 MB / month | 90% | >4 GB / month | Sampling or upgrade to paid tier |

### Dataverse API Budget Analysis

The most common capacity concern in Power Platform projects. Here is how the budget breaks down:

| Consumer | Requests / 5 min (per user) | Notes |
|---|---|---|
| Model-driven app (agent) | ~80-120 | Form load + subgrids + lookups + saves |
| Canvas app (self-service) | ~30-50 | Simpler forms, fewer subgrids |
| SPFx web parts | ~20-40 | Cached, batched API calls |
| Power Automate (per flow run) | ~5-15 | Depends on number of Dataverse actions |
| Azure Function sync (S2S) | ~500 total | Batch queries every 15 min, well within 40K limit |

**Why we are safe**: The separation of reporting workloads to Azure SQL means Power BI never consumes Dataverse API budget. This single architectural decision preserves the entire interactive budget for agents and self-service users.

## 3. Scaling Tiers

### Small (up to 50 users, 20 tickets/day)

| Component | Configuration | Monthly Cost |
|---|---|---|
| Dataverse | Default included storage (10 GB) | Included in Power Apps license |
| Azure Functions | Consumption plan | ~$0 (free tier) |
| Azure SQL | Basic tier (5 DTU, 2 GB) | ~$5 |
| Application Insights | Free tier (5 GB/month) | $0 |
| Key Vault | Standard tier | ~$0 |
| Power BI | Pro licenses for managers | $10/user/month |

**No changes needed** from the default architecture. This is a pilot or small-department deployment.

### Medium (up to 500 users, 200 tickets/day) — Current Target

| Component | Configuration | Monthly Cost |
|---|---|---|
| Dataverse | Default storage, monitor API usage | Included |
| Azure Functions | Consumption plan | ~$5 |
| Azure SQL | Basic tier → S0 at 80% DTU | $5-15 |
| Application Insights | Free tier, monitor ingestion | $0-5 |
| Key Vault | Standard tier | ~$1 |
| Power BI | Pro licenses for managers (30 users) | $300 |

**Trigger actions**:
- Monitor Dataverse API usage via Power Platform admin center → Analytics → API usage
- If SQL DTU consistently exceeds 80%, upgrade to S0
- If a single Power Automate flow exceeds 50K actions/day, review for optimization

### Large (up to 5,000 users, 2,000 tickets/day)

| Component | Configuration | Monthly Cost |
|---|---|---|
| Dataverse | Additional storage packs, S2S auth for all integrations | Included + $40-80/GB |
| Azure Functions | Premium plan (EP1) | ~$50 |
| Azure SQL | S2 (50 DTU, 250 GB) | ~$75 |
| Application Insights | Paid tier with sampling | ~$25 |
| Key Vault | Standard tier | ~$1 |
| Power BI | Premium per capacity (P1) | ~$5,000 |

**Architecture changes required**:
1. **S2S authentication for all integrations** (already implemented) — avoids per-user API budget consumption for background processes.
2. **Azure Functions Premium plan** — required for >100 concurrent executions and virtual network integration.
3. **SQL aggregation tables** — pre-computed daily/weekly/monthly rollups to reduce query complexity:
   ```sql
   CREATE TABLE dbo.DailyTicketAgg (
       DateKey INT,
       CategoryId UNIQUEIDENTIFIER,
       DepartmentId UNIQUEIDENTIFIER,
       TicketCount INT,
       AvgResolutionMinutes DECIMAL(10,2),
       SLABreachCount INT,
       AvgSatisfaction DECIMAL(3,2)
   );
   ```
4. **Power BI Premium** — required when >500 users need dashboard access (shared capacity cannot handle the concurrency).

### Enterprise (50,000+ users, 10,000+ tickets/day)

| Component | Configuration | Monthly Cost |
|---|---|---|
| Dataverse | Synapse Link replaces custom SQL sync | Included (Synapse costs apply) |
| Azure Synapse Analytics | Serverless SQL pool | ~$200-500 |
| Azure Functions | Premium plan (EP2/EP3) | ~$200 |
| Azure SQL | S4 (200 DTU) or Hyperscale | ~$500 |
| Application Insights | Paid tier, aggressive sampling | ~$100 |
| Key Vault | Premium tier (HSM-backed) | ~$5 |
| Power BI | Premium per capacity (P2) | ~$10,000 |
| Azure Front Door | Global load balancing + WAF | ~$100 |

**Architecture changes required**:
1. **Dataverse Synapse Link** — replaces the custom Azure Function sync entirely. Near-real-time replication to Azure Synapse, no API budget consumption.
2. **Azure Front Door / CDN** — for the SharePoint/SPFx portal if globally distributed users.
3. **Dedicated SQL pool** — if reporting query complexity demands it (otherwise serverless is cheaper).
4. **Event-driven architecture** — replace timer-based sync with Dataverse webhooks for real-time data flow.

## 4. Cost Projections

### Monthly Azure Costs by Tier

| Component | Small | Medium | Large | Enterprise |
|---|---|---|---|---|
| Azure Functions (Consumption/Premium) | $0 | $5 | $50 | $200 |
| Azure SQL (Basic/S0/S2/S4) | $5 | $15 | $75 | $500 |
| Application Insights | $0 | $5 | $25 | $100 |
| Key Vault | $0 | $1 | $1 | $5 |
| Azure Synapse | — | — | — | $300 |
| Azure Front Door | — | — | — | $100 |
| Blob Storage (audit archives) | $0 | $1 | $5 | $20 |
| **Total Azure** | **$5** | **$27** | **$156** | **$1,225** |

**Note**: M365 / Power Platform licensing is separate and covered in [cost-analysis.md](cost-analysis.md). The above represents Azure-only infrastructure costs.

### Cost per Ticket

| Tier | Monthly Azure Cost | Tickets / Month | Cost per Ticket |
|---|---|---|---|
| Small | $5 | 600 | $0.008 |
| Medium | $27 | 6,000 | $0.005 |
| Large | $156 | 60,000 | $0.003 |
| Enterprise | $1,225 | 300,000 | $0.004 |

The cost per ticket decreases with scale (consumption-based pricing) until Enterprise tier, where fixed-cost components (Synapse, Front Door) create a slight uptick.

## 5. Bottleneck Analysis

Which component fails first under load, and what to do about it:

### Failure Order (Most Likely to Least Likely)

| Rank | Component | Failure Mode | Ticket Volume at Risk | Symptoms | Fix |
|---|---|---|---|---|---|
| 1 | **Azure SQL (Basic DTU)** | DTU exhaustion, query timeouts | ~500 tickets/day | Power BI dashboards timeout, slow refresh | Upgrade to S0 ($15/month) |
| 2 | **Dataverse API (interactive)** | Per-user throttling (HTTP 429) | ~1,000 tickets/day with heavy app usage | Agents see "Rate limit exceeded" errors | Optimize app queries, implement caching |
| 3 | **Power Automate throughput** | Flow run queue backlog | ~2,000 tickets/day | SLA escalation delays, routing delays | Optimize flow actions, consider child flows |
| 4 | **Azure Functions (Consumption timeout)** | 10-minute timeout on large syncs | ~5,000 cumulative tickets per sync | SQL sync incomplete, data gaps in reporting | Switch to Premium plan or reduce batch size |
| 5 | **Power BI (shared capacity)** | Report rendering timeouts | >500 concurrent BI users | Dashboard fails to load, "capacity exceeded" | Upgrade to Premium per capacity |

### Mitigation Priority

Address bottlenecks in rank order. The first ($10/month SQL upgrade) buys significant headroom. Most organizations will never reach bottleneck #4 or #5.

## 6. Monitoring for Capacity

### Key Metrics and Thresholds

| Metric | Source | Warning Threshold | Critical Threshold | Action |
|---|---|---|---|---|
| Dataverse API usage (per user) | Power Platform Admin Center → Analytics | >3,000 req / 5 min | >5,000 req / 5 min | Optimize app, batch calls |
| Dataverse API usage (S2S) | Power Platform Admin Center → Analytics | >20,000 req / 5 min | >35,000 req / 5 min | Optimize sync, increase interval |
| Dataverse storage | Power Platform Admin Center → Capacity | >70% of allocation | >85% of allocation | Purchase capacity or archive data |
| Azure SQL DTU | Azure Monitor → SQL Database metrics | >70% sustained (1 hour) | >85% sustained (1 hour) | Upgrade tier |
| Azure SQL storage | Azure Monitor → SQL Database metrics | >60% of tier limit | >80% of tier limit | Upgrade tier |
| Function execution duration | Application Insights → Performance | P95 >30 seconds | P95 >5 minutes | Optimize code, consider Premium |
| Function failure rate | Application Insights → Failures | >1% of executions | >5% of executions | Investigate root cause |
| Power Automate flow failures | Power Automate → Analytics | >2% failure rate | >5% failure rate | Review flow logic, connector limits |
| Application Insights ingestion | Azure Monitor → Usage and costs | >3 GB / month | >4.5 GB / month | Enable sampling, review telemetry volume |

### Azure Monitor Alert Rules

Configure the following alerts in Azure Monitor:

```json
{
  "alerts": [
    {
      "name": "SQL-DTU-Warning",
      "metric": "dtu_consumption_percent",
      "threshold": 70,
      "window": "PT1H",
      "severity": 2,
      "action": "email-platform-admin"
    },
    {
      "name": "SQL-DTU-Critical",
      "metric": "dtu_consumption_percent",
      "threshold": 85,
      "window": "PT15M",
      "severity": 1,
      "action": "email-platform-admin + teams-channel"
    },
    {
      "name": "Function-Failures",
      "metric": "requests/failed",
      "threshold": 5,
      "window": "PT15M",
      "severity": 1,
      "action": "email-platform-admin"
    },
    {
      "name": "AppInsights-Ingestion",
      "metric": "ingestion_volume_gb",
      "threshold": 4,
      "window": "P1M",
      "severity": 2,
      "action": "email-platform-admin"
    }
  ]
}
```

### Monthly Capacity Review

Run the following checks on the first business day of each month:

1. **Dataverse**: Power Platform Admin Center → Capacity → review storage usage trend
2. **Azure SQL**: Azure Portal → SQL Database → Performance overview → DTU trend (30 days)
3. **Azure Functions**: Application Insights → Performance → execution count and duration trends
4. **Power Automate**: Power Automate admin analytics → flow runs, failures, action counts
5. **Power BI**: Power BI Admin Portal → Usage metrics → concurrent users, render times
6. **Application Insights**: Azure Portal → Usage and estimated costs → data volume trend

Document findings and compare against the 3-year projection table. Adjust growth assumptions if actual usage diverges by more than 20% from projections.
