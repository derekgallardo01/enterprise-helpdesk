# ADR-002: Azure SQL Reporting Warehouse

## Status
Accepted

## Context
Power BI needs to visualize ticket analytics — volume trends, SLA compliance, agent performance, department breakdowns. The data lives in Dataverse. The question is whether Power BI should query Dataverse directly or through a separate reporting warehouse.

## Decision
Sync Dataverse ticket data to Azure SQL via change tracking (delta sync every 15 minutes). Power BI connects exclusively to Azure SQL, never directly to Dataverse.

## Rationale

### The Problem with Direct Dataverse Queries

Dataverse enforces API request limits:
- **6,000 requests per user per 5 minutes** (interactive)
- **60,000 requests per organization per 5 minutes**

A Power BI dashboard with 10 visuals hitting Dataverse DirectQuery means 10 queries per page load per user. The math:

| Scenario | Concurrent Users | Queries/Burst | Impact |
|---|---|---|---|
| Small team | 5 managers | 50 queries | Fine |
| Medium org | 50 managers | 500 queries | Noticeable |
| Large org | 500 managers during standup | 5,000 queries | Competes with 2,000 agents using transactional apps |

Additionally, Dataverse's query language (FetchXML) cannot express:
- `PERCENTILE_CONT` — "What's the 90th percentile resolution time?"
- Window functions — "Running average of SLA compliance over 12 months"
- Complex CTEs — "Agent performance ranking by category by quarter"
- Star schema optimizations — Pre-computed aggregation tables

### The Solution

```
Dataverse ──(change tracking delta sync)──> Azure SQL ──(DirectQuery)──> Power BI
               every 15 minutes                          star schema
```

- Azure Function `DataverseSyncToSQL` uses Dataverse change tracking API (delta token) to sync only modified rows
- Star schema: `TicketFact` + dimension tables (`CategoryDim`, `DepartmentDim`, `AgentDim`, `DateDim`)
- Computed columns calculated at write time: `ResolutionMinutes`, `FirstResponseMinutes`, `IsOverdue`
- Power BI never touches Dataverse — API budget stays 100% for transactional apps

### Cost

Azure SQL Basic tier: **~$5/month**. At large scale, S1 ($15/month). The cost is negligible compared to the API quota protection it provides.

### Future Scale Path

At 50,000+ users, replace the custom Azure Function sync with **Dataverse Synapse Link** — Microsoft's native solution that streams data changes to Azure Synapse Analytics in near-real-time with zero custom code.

## Consequences

- 15-minute data latency for reports (acceptable for operational dashboards; not suitable for real-time monitoring)
- Additional Azure resource to manage (mitigated by infrastructure-as-code)
- Sync function must handle schema changes gracefully (column additions to Dataverse must be mirrored in SQL)
