# Enterprise Help Desk Portal

A production-grade IT help desk system built across the full Microsoft stack — Power Apps, SharePoint Online, SPFx, Azure Functions, Dataverse, Power Automate, Power BI, and Copilot Studio.

## Architecture

```
                     End Users (Browser / Teams)
                          |           |
              +-----------+           +------------+
              |                                    |
    SharePoint Online                    Microsoft Teams
    - KB Portal (SPFx)                   - Copilot Studio Bot
    - Ticket Dashboard (SPFx)            - Adaptive Cards
    - Quick Stats (ACE)                  - Notifications
              |                                    |
              +----------------+-------------------+
                               |
                   +-----------v-----------+
                   |      Dataverse        |
                   | (Primary Data Store)  |
                   | - Tickets, Assets     |
                   | - Categories, SLAs    |
                   | - Audit Trail         |
                   +-----------+-----------+
                               |
        +----------+-----------+-----------+----------+
        |          |                       |          |
   Power Apps  Power Automate      Azure Functions  Power BI
   - Model-    - Ticket Routing    - Email Parser   - SLA Reports
     Driven    - SLA Escalation    - Graph Sync     - Exec Dashboard
   - Canvas    - Notifications     - SQL Sync       - Agent Perf
              |                       |
              +----------+------------+
                         |
                   Azure SQL
                   (Reporting Warehouse)
```

### Three-Store Architecture

| Store | Purpose | Access Pattern | Why |
|---|---|---|---|
| **Dataverse** | Tickets, assets, categories, SLAs, audit trail | OLTP — row-level CRUD with security | Row-level security, full Power Apps delegation, model-driven UI generation, business rules at platform level |
| **SharePoint** | KB articles, SOPs, attachments | Content — rich editing, versioning, search | WYSIWYG page editor, Microsoft Search integration, version history with diff, collaborative editing |
| **Azure SQL** | Reporting warehouse (star schema) | OLAP — complex analytics, aggregations | Window functions, CTEs, computed columns. Protects Dataverse API quota (6,000 req/5 min/user) from Power BI queries |

### Why Not a Single Store?

Mixing OLTP and OLAP in Dataverse is the #1 architecture mistake in Power Platform projects. At 200+ tickets/day, Power BI DirectQuery against Dataverse would consume API quota meant for the 500 users actively submitting and triaging tickets. Each store is optimized for its access pattern, and each can degrade independently without taking down the entire system.

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Data | Dataverse (tickets), SharePoint (KB), Azure SQL (reporting) | Three-store architecture: OLTP / Content / OLAP |
| Apps | Power Apps (Model-Driven + Canvas) | Agent console + Employee self-service portal |
| Automation | Power Automate | Ticket routing, SLA escalation, notifications |
| Portal | SPFx (React + TypeScript + Fluent UI v9) | SharePoint-embedded ticket dashboard, KB search, Viva Connections ACE |
| Backend | Azure Functions (.NET 10 Isolated Worker) | Email parsing, Graph sync, webhook receiver, SQL sync |
| Analytics | Power BI (DirectQuery to Azure SQL) | Operational dashboards, executive summary, SLA compliance |
| AI | Copilot Studio + Azure OpenAI (GPT-4o-mini) | Teams bot for ticket creation/KB search, AI ticket classification |
| Identity | Entra ID | Single identity plane across all components |
| Governance | DLP policies, managed solutions, environment strategy | Dev → Test → Prod ALM pipeline |

## Security Model

| Role | Creates Tickets | Reads Tickets | Edits Tickets | Internal Comments |
|---|---|---|---|---|
| **HD - Requester** | Own only | Own only | Own, status=New only | Cannot see |
| **HD - Agent** | Any | Own business unit | Own BU | Can see and create |
| **HD - Manager** | Any | Organization-wide | Organization-wide | Can see and create |
| **HD - Admin** | Any | Organization-wide | Org-wide + schema | Full access |

Security is enforced at the Dataverse platform level via security roles + business units — not in app logic. This means access control applies regardless of whether data is accessed via Power Apps, SPFx, API, or any other client.

## Phased Build Order

```
Phase 1: Dataverse + Model-Driven ──> Phase 2: Power Automate ──> Phase 3: Canvas App
                                                                        |
Phase 5: Azure Functions + SQL  <── Phase 4: SPFx Web Parts <──────────┘
        |
Phase 6: Power BI ──────────────> Phase 7: Copilot Studio + AI
```

| Phase | What | Hours | Why This Order |
|---|---|---|---|
| 1 | Dataverse Schema + Model-Driven App | 10 | Foundation — everything depends on the schema |
| 2 | Power Automate Workflows | 7 | Validates schema under realistic scenarios |
| 3 | Canvas App (Self-Service Portal) | 9 | Needs working workflows so tickets auto-route |
| 4 | SPFx Web Parts (SharePoint Portal) | 14 | Needs reference UX from Canvas App |
| 5 | Azure Functions + Azure SQL | 9 | Extends Power Automate with code-level processing |
| 6 | Power BI Reports | 7 | Needs SQL warehouse from Phase 5 |
| 7 | Copilot Studio + AI | 7 | Needs ALL prior phases for full end-to-end demo |
| | **Total** | **63** | |

Each phase produces a working, demoable increment. No phase is a dead-end.

## Scalability

| Scale | Users | Tickets/Day | What Changes |
|---|---|---|---|
| Small | 50 | ~20 | Default configuration |
| Medium | 500 | ~200 | Monitor API limits, consider Power BI Import mode |
| Large | 5,000 | ~2,000 | S2S auth for Functions, aggregation tables, CDN for SPFx |
| Enterprise | 50,000+ | ~20,000 | Synapse Link replaces SQL sync, Power BI Premium, Azure Front Door |

## Project Structure

```
enterprise-helpdesk/
├── docs/                          # Architecture documentation
│   ├── architecture.md            # Full architecture doc
│   ├── data-model.md              # Dataverse schema reference
│   ├── security-model.md          # Roles, DLP, governance
│   └── decisions/                 # Architecture Decision Records
├── spfx/helpdesk-spfx/            # SPFx solution (Phase 4)
├── functions/HelpDesk.Functions/   # Azure Functions .NET 10 (Phase 5)
├── sql/                           # Azure SQL star schema (Phase 5)
├── power-platform/solutions/      # Exported Dataverse solution XML
└── .github/workflows/             # CI/CD pipelines
```

## Documentation

- [Architecture](docs/architecture.md) — Full enterprise architecture with justifications
- [Data Model](docs/data-model.md) — Dataverse schema, relationships, business rules
- [Security Model](docs/security-model.md) — Roles, DLP, environment strategy, ALM, compliance
- Architecture Decision Records:
  - [ADR-001: Dataverse over SharePoint Lists](docs/decisions/001-dataverse-over-sharepoint-lists.md)
  - [ADR-002: Azure SQL Reporting Warehouse](docs/decisions/002-azure-sql-reporting-warehouse.md)
  - [ADR-003: SPFx over Power Apps iframe](docs/decisions/003-spfx-over-power-apps-iframe.md)
  - [ADR-004: Copilot Studio over Bot Framework](docs/decisions/004-copilot-studio-over-bot-framework.md)
