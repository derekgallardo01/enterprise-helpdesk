# ADR-001: Dataverse Over SharePoint Lists for Ticket Data

## Status
Accepted

## Context
The help desk system needs a primary data store for tickets — the most frequently accessed, security-sensitive, high-volume data in the system. The three options within the Microsoft ecosystem are Dataverse, SharePoint Lists, and Azure SQL.

## Decision
Use Dataverse as the primary transactional data store for all ticket-related data.

## Rationale

### SharePoint Lists — Rejected

| Limitation | Impact |
|---|---|
| **5,000 item view threshold** | At 200+ tickets/day, the list exceeds 5,000 items within a month. Views become non-functional. Power Apps delegation fails silently — queries return incomplete results without warning. |
| **No row-level security** | SharePoint item-level permissions exist but are not practical at scale (manual per-item assignment). Any user with list access can see all items via API/Graph, regardless of view filters in the app. |
| **Limited delegation** | Only `=`, `<`, `>`, `StartsWith` are delegable. `Search()`, `in`, and nested `Filter()` are not. At scale, non-delegable queries return only the first 500-2,000 records, producing silently wrong results. |
| **No referential integrity** | Lookup columns exist but have no cascade behaviors or orphan prevention. Deleting a category does not cascade or block — tickets with that category become broken. |
| **No business rules** | Logic must be implemented in each app separately. Different apps accessing the same list can bypass each other's validation. |

### Azure SQL — Rejected for Primary Store

Azure SQL has full relational capabilities but is not a native Power Apps data source. Using it as the primary store would require:
- Building a complete authentication/authorization layer (Dataverse provides this natively)
- Building API endpoints for every CRUD operation (Dataverse provides this natively)
- Losing model-driven app generation entirely
- Losing Power Automate first-party triggers (would need polling or custom webhook)
- Building audit logging from scratch

Azure SQL is used as a **secondary store** for the reporting warehouse — a role it is better suited for than Dataverse.

### Dataverse — Accepted

| Capability | Value |
|---|---|
| **Row-level security** | Security roles + business units enforce access at the platform level, regardless of which client accesses the data. |
| **Full delegation** | All filter and sort operations run server-side, regardless of dataset size. |
| **Model-driven app generation** | Forms, views, dashboards, and BPFs are generated from the schema — zero custom UI code for the agent console. |
| **Business rules** | Declarative rules enforced at the platform level. Priority matrix, required fields, and field locking apply regardless of which app or API is used. |
| **First-party Power Automate triggers** | `When a row is added/modified` fires within seconds with no polling. |
| **Built-in audit logging** | Field-level change tracking with who/when/before/after. |
| **Change tracking API** | Delta sync for the Azure SQL reporting warehouse. |

## Consequences

- Power Apps per-user ($20/user/month) or per-app ($5/app/user/month) licensing required for Dataverse access
- API request limits (6,000 per user per 5 minutes) require careful architecture — analytical workloads offloaded to Azure SQL
- Schema changes require solution export/import through the ALM pipeline
