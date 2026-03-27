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
Prerequisites + IaC (infra/)
    |
Phase 1 (Dataverse + Model-Driven) ─── FOUNDATION
    |
    ├──> Phase 2 (Power Automate)  ──> Phase 3 (Canvas App)
    |
    ├──> Phase 4 (SPFx)  ←── parallel
    |
    └──> Phase 5 (Azure Functions + SQL)
              |
              ├──> Phase 6 (Power BI)
              └──> Phase 7 (Copilot Studio + AI)
                        |
Phase 8 (Operational Readiness) ── DR, monitoring, runbooks, IaC
Phase 9 (Testing & Hardening)  ── integration, load, security, a11y
Phase 10 (UAT Pilot & Rollout) ── real users, measured go-live
```

| Phase | What | Hours | Status |
|---|---|---|---|
| 0 | Prerequisites + Infrastructure-as-Code | 4 | Built (Bicep templates) |
| 1 | Dataverse Schema + Model-Driven App | 10 | Documented (seed data, solution scaffold) |
| 2 | Power Automate Workflows | 7 | Documented (flow definitions) |
| 3 | Canvas App (Self-Service Portal) | 9 | Documented (screen specs) |
| 4 | SPFx Web Parts (SharePoint Portal) | 14 | **Built** (React components, DataGrid, KB Search, ACE) |
| 5 | Azure Functions + Azure SQL | 9 | **Built** (sync, webhooks, AI classification, health check) |
| 6 | Power BI Reports | 7 | Built (PBIP project, semantic model, DAX measures) |
| 7 | Copilot Studio + AI | 7 | Documented (topic definitions, prompt templates) |
| 8 | Operational Readiness | 12 | **Built** (DR, monitoring, runbooks, deployment guide, GDPR, IaC) |
| 9 | Testing & Hardening | 10 | **Built** (xUnit tests, k6 scripts, security tests, seed data) |
| 10 | UAT Pilot & Rollout | 6 | Built (UAT plan, go/no-go checklist) |
| | **Total** | **~91** | |

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
├── docs/                              # Architecture & operational documentation
│   ├── architecture.md                # Full architecture with justifications
│   ├── data-model.md                  # Dataverse schema, relationships, business rules
│   ├── security-model.md              # Roles, DLP, governance, ALM
│   ├── disaster-recovery.md           # DR/BC plan, RTO/RPO, failover procedures
│   ├── monitoring-alerting.md         # Health checks, alert thresholds, dashboards
│   ├── deployment-guide.md            # Step-by-step deployment with IaC references
│   ├── capacity-planning.md           # Growth projections, scaling tiers, cost projections
│   ├── change-management.md           # CAB process, release notes, rollback procedures
│   ├── gdpr-compliance.md             # Data map, DSAR, retention, anonymization
│   ├── cost-analysis.md               # Licensing, Azure costs, TCO vs ServiceNow/Zendesk
│   ├── testing-strategy.md            # Unit, integration, security, performance, a11y
│   ├── uat-plan.md                    # UAT pilot plan, success criteria, rollout
│   ├── decisions/                     # Architecture Decision Records (4 ADRs)
│   └── runbooks/                      # 5 incident response runbooks
├── spfx/helpdesk-spfx/               # SPFx solution (React 18.3 + Fluent UI v9)
│   ├── src/components/                # StatusBadge, PriorityIcon, TicketDetailPanel, etc.
│   ├── src/context/                   # TicketContext (React Context + useReducer)
│   ├── src/hooks/                     # useTickets, useKBSearch (300ms debounce)
│   ├── src/services/                  # TicketService, KBService (Dataverse + Graph)
│   ├── src/webparts/                  # TicketDashboard, KBSearch web parts
│   └── src/adaptiveCardExtensions/    # Viva Connections ticket summary ACE
├── functions/HelpDesk.Functions/      # Azure Functions (.NET 10 Isolated Worker)
│   ├── Functions/                     # EmailToTicket, DataverseSyncToSQL, GraphSync,
│   │                                  # WebhookReceiver, HealthCheck, ClassifyTicket,
│   │                                  # SuggestResponse
│   ├── Services/                      # DataverseService, DataverseSyncService,
│   │                                  # AIClassificationService
│   └── Middleware/                     # ExceptionHandlingMiddleware
├── functions/HelpDesk.Functions.Tests/ # xUnit + Moq test project
├── sql/                               # Azure SQL star schema + migrations + sprocs
├── infra/                             # Bicep IaC (modular: Function App, SQL, KV, monitoring)
│   ├── main.bicep                     # Orchestrator
│   ├── modules/                       # functionapp, sql, monitoring, keyvault
│   └── parameters/                    # dev.bicepparam, prod.bicepparam
├── power-platform/                    # Power Platform solution + seed data
│   ├── solutions/HelpDesk/            # Solution scaffold (.cdsproj, Solution.xml)
│   ├── seed-data/                     # Categories, subcategories, SLA profiles, departments
│   ├── flows/                         # Power Automate flow definitions
│   └── canvas-app/                    # Canvas app screen documentation
├── powerbi/                           # Power BI project (PBIP format, DAX measures)
├── copilot-studio/                    # Bot topic definitions + AI prompt templates
├── tests/                             # Integration, security, performance, seed data
│   ├── integration/                   # E2E test scripts + setup/teardown
│   ├── security/                      # RBAC verification scripts
│   ├── performance/                   # k6 load test scripts
│   └── seed-data/                     # 1,000 test tickets generator
└── .github/workflows/                 # CI/CD (Functions deploy, SPFx deploy with tests)
```

## Documentation

### Architecture & Design
- [Architecture](docs/architecture.md) — Full enterprise architecture with justifications
- [Data Model](docs/data-model.md) — Dataverse schema, relationships, business rules
- [Security Model](docs/security-model.md) — Roles, DLP, environment strategy, ALM, compliance
- Architecture Decision Records:
  - [ADR-001: Dataverse over SharePoint Lists](docs/decisions/001-dataverse-over-sharepoint-lists.md)
  - [ADR-002: Azure SQL Reporting Warehouse](docs/decisions/002-azure-sql-reporting-warehouse.md)
  - [ADR-003: SPFx over Power Apps iframe](docs/decisions/003-spfx-over-power-apps-iframe.md)
  - [ADR-004: Copilot Studio over Bot Framework](docs/decisions/004-copilot-studio-over-bot-framework.md)

### Operational Readiness
- [Disaster Recovery](docs/disaster-recovery.md) — RTO/RPO targets, backup strategy, failover procedures
- [Monitoring & Alerting](docs/monitoring-alerting.md) — Health checks, alert thresholds, KQL queries
- [Deployment Guide](docs/deployment-guide.md) — Step-by-step from zero to production
- [Capacity Planning](docs/capacity-planning.md) — Growth projections, component limits, cost projections
- [Change Management](docs/change-management.md) — CAB process, release notes, rollback procedures
- [GDPR Compliance](docs/gdpr-compliance.md) — Data map, subject access requests, retention policies
- [Cost Analysis](docs/cost-analysis.md) — Licensing breakdown, TCO vs. ServiceNow/Zendesk
- [Testing Strategy](docs/testing-strategy.md) — Unit, integration, security, performance, accessibility
- [UAT Plan](docs/uat-plan.md) — Pilot plan, success criteria, measured rollout
- [Incident Runbooks](docs/runbooks/) — 5 scenarios: API throttling, sync failure, email parsing, access issues, stale data

## Anti-Patterns Avoided

This project deliberately avoids common Power Platform mistakes:

| Anti-Pattern | What We Do Instead | Why |
|---|---|---|
| Everything in SharePoint Lists | Dataverse with RLS + delegation | 5,000 item threshold, no row-level security |
| Analytical queries against Dataverse | Azure SQL star schema via delta sync | Protects 6,000 req/5min API quota |
| Power Apps iframe in SharePoint | SPFx with Fluent UI v9 | <1s load vs 3-5s, inherits theme, <100KB bundle |
| All logic in Power Automate | Power Automate orchestrates, Functions execute | Avoid 200-step monster flows |
| Editing in Production | Managed solutions, Dev→Test→Prod | No rollback, no audit trail |
| Flat security model | 4 roles + column security + business units | Everyone sees everything = compliance nightmare |
| Custom bot from scratch | Copilot Studio + generative answers | 40+ hours saved, zero training data needed |
| Single-store monolith | Three-store pattern | One outage ≠ total system failure |
