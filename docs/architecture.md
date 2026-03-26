# Enterprise Help Desk Portal — Architecture

## Overview

This system is an enterprise-grade IT help desk built across the full Microsoft stack. It follows a **three-store architecture** that separates transactional data (Dataverse), unstructured content (SharePoint), and analytical workloads (Azure SQL) — each optimized for its access pattern.

## Architecture Diagram

```
                          +---------------------------+
                          |      End Users / IT        |
                          |     (Browser / Teams)      |
                          +-----|-----------|----------+
                                |           |
                    +-----------+           +------------+
                    |                                    |
          +---------v---------+              +-----------v-----------+
          | SharePoint Online |              |    Microsoft Teams    |
          | - KB Portal (SPFx)|              | - Copilot Studio Bot |
          | - Ticket Dashboard|              | - Adaptive Cards      |
          |   (SPFx Web Parts)|              | - Notifications       |
          +---------+---------+              +-----------+-----------+
                    |                                    |
                    +----------------+-------------------+
                                     |
                         +-----------v-----------+
                         |      Dataverse        |
                         | (Primary Data Store)  |
                         | - Tickets             |
                         | - Assets              |
                         | - Categories / SLAs   |
                         | - Audit Trail         |
                         +-----------+-----------+
                                     |
              +----------+-----------+-----------+----------+
              |          |                       |          |
    +---------v---+ +----v--------+    +---------v--+ +----v----------+
    | Power Apps  | | Power       |    | Azure      | | Power BI      |
    | - Model-    | | Automate    |    | Functions  | | - Operational |
    |   Driven    | | - Ticket    |    | - Graph    | |   Dashboards  |
    |   (Agents)  | |   Routing   |    |   Sync     | | - SLA Reports |
    | - Canvas    | | - SLA       |    | - Email    | | - Executive   |
    |   (Self-    | |   Escalation|    |   Parser   | |   Summary     |
    |   Service)  | | - Approvals |    | - Webhook  | +---------------+
    +-------------+ +-------------+    |   Receiver |
                                       +------+-----+
                                              |
                                       +------v------+
                                       | Azure SQL   |
                                       | (Reporting  |
                                       |  Warehouse) |
                                       +-------------+
```

## Why This Architecture Is Enterprise-Grade

### 1. Separation of Concerns (OLTP / OLAP / Content)

| Store | Workload | Optimized For |
|---|---|---|
| **Dataverse** | Transactional (OLTP) | Row-level CRUD, security roles, business rules, real-time triggers |
| **Azure SQL** | Analytical (OLAP) | Window functions, CTEs, aggregations, star schema, DirectQuery |
| **SharePoint** | Content | Rich editing, versioning, Microsoft Search, co-authoring |

**Why this matters at enterprise scale**: Mixing OLTP and OLAP in one store is the #1 architecture mistake in Power Platform projects. Dataverse enforces API request limits — 6,000 per user per 5 minutes (interactive), 60,000 per org per 5 minutes. At 200+ tickets/day, a Power BI DirectQuery against Dataverse would consume API quota meant for the agents actively triaging tickets.

By offloading analytics to Azure SQL, the Dataverse API budget stays 100% available for the transactional apps.

### 2. Single Identity Plane (Entra ID)

Every component authenticates through the same Entra ID tenant:

| Component | Auth Method |
|---|---|
| Power Apps → Dataverse | Zero-config (native) |
| SPFx → Dataverse | `AadHttpClient` (automatic token from SharePoint context) |
| SPFx → Microsoft Graph | `MSGraphClientV3` (automatic token) |
| Azure Functions → Dataverse | S2S app registration (40K requests/5 min) |
| Azure Functions → Azure SQL | Managed identity (no connection strings) |
| Power Automate → Dataverse | First-party connector (user or service principal context) |
| Copilot Studio → Dataverse | Power Automate cloud flows (service context) |

**Why this matters**: One identity plane = one place to revoke access (disable the Entra ID account), one place to audit (sign-in logs), one conditional access policy set (MFA, device compliance, location). No service accounts with passwords, no API keys in app settings, no separate user databases.

### 3. Fault Isolation

| If This Goes Down... | These Still Work | Degradation |
|---|---|---|
| Azure Functions | Power Apps, Power Automate, SharePoint | SQL sync pauses (backfills on recovery). Email-to-ticket queues in mailbox. |
| SharePoint | Power Apps, Power Automate, Teams | KB search unavailable. Ticket operations continue normally. |
| Power BI | Everything except dashboards | Operational apps unaffected. Reporting is a read-only overlay. |
| Azure SQL | Power Apps, Power Automate, SharePoint, Teams | Power BI dashboards fail. Ticket operations unaffected. |

No single component failure takes down the entire system. Each layer degrades gracefully.

### 4. Licensing Efficiency

| Component | License Source | Incremental Cost |
|---|---|---|
| Dataverse, Power Apps, Power Automate | M365 E3/E5 + Power Apps per-user ($20/user/mo) or per-app ($5/app/user/mo) | Likely already licensed |
| SharePoint Online | M365 E3/E5 | Already licensed |
| Microsoft Teams | M365 E3/E5 | Already licensed |
| Azure Functions | Consumption plan | ~$2/month at 1,000 tickets/day |
| Azure SQL | Basic tier | ~$5/month |
| Power BI | Pro ($10/user/mo) or Premium per capacity | For managers/execs only |
| Copilot Studio | Per-message pricing or capacity pack | Variable |

**Why this matters for consulting**: "Most capabilities are already covered by your existing M365 licenses. Azure adds ~$10/month." That licensing story wins deals.

## Technology Choice Justifications

### Dataverse for Tickets

| Factor | Dataverse | SharePoint Lists | Azure SQL |
|---|---|---|---|
| Row-level security | Native (roles + BUs) | None without custom code | Must build auth layer |
| Delegation in Power Apps | Full — server-side at any scale | 5,000 item view threshold | Not a native Power Apps source |
| Model-driven app generation | Forms, views, BPFs from schema | N/A | N/A |
| Business rules | Platform-enforced, client-agnostic | App-level only, bypassed by API | Triggers exist, no Power Apps integration |
| Audit logging | Built-in, field-level | Version history only | Must build custom |
| Relationships | Native lookups + cascade behaviors | No referential integrity | Full FK with RI |

**Decision**: Tickets are relational, security-sensitive, high-volume transactional data. Dataverse is the only option providing row-level security, full delegation, and model-driven UI in one platform.

### SharePoint for Knowledge Base

| Factor | SharePoint | Dataverse |
|---|---|---|
| Content authoring | Full WYSIWYG page editor | Multi-line field, 1MB cap |
| Version history | Automatic with diff + restore | Audit only, no diff view |
| Search | Microsoft Search auto-indexes | FetchXML or Dataverse Search |
| Collaboration | Co-authoring, @mentions, approvals | No co-authoring |

**Decision**: KB articles are long-form, collaboratively edited, read-heavy content. `hd_KBArticleRef` in Dataverse acts as a lightweight cross-reference index.

### Azure SQL for Reporting

**The problem**: A Power BI dashboard with 10 visuals × 500 managers refreshing = 5,000 Dataverse queries competing with 2,000 agents using the transactional apps.

**The solution**: Sync ticket data to Azure SQL via change tracking (delta). Power BI hits SQL exclusively. Star schema enables queries Dataverse cannot express (`PERCENTILE_CONT`, window functions, cross-table CTEs). $5/month.

### SPFx over Power Apps Iframes

| Factor | SPFx Web Part | Power Apps Iframe |
|---|---|---|
| Load time | < 1 second | 3-5 seconds |
| Theming | Automatic SharePoint tokens | Manual, breaks on theme change |
| Navigation | Native page context | Iframe isolation |
| Authentication | `AadHttpClient` (zero prompt) | Separate auth flow |
| Bundle size | < 100KB gzipped (tree-shaken) | ~2MB (full runtime) |
| Viva Connections | ACE support | No equivalent |

### Power Automate over Logic Apps

| Factor | Power Automate | Logic Apps |
|---|---|---|
| Dataverse trigger | First-party, fires in seconds | Third-party, polling-based |
| Visibility | Power Platform admin center | Azure Portal only |
| Licensing | Included in Power Apps license | Pay-per-execution on Azure |
| Maintainability | Client admins can edit | Requires developer skills |

**Exception**: Azure Functions for code-level work (email parsing, bulk SQL, custom auth). Power Automate orchestrates, Functions execute.

### Copilot Studio over Bot Framework SDK

| Factor | Copilot Studio | Bot Framework SDK |
|---|---|---|
| Build time | Hours | 40+ hours |
| KB search | Generative answers, zero training data | Custom RAG pipeline needed |
| Teams deploy | One-click | Bot registration + manifest |
| Maintenance | Business users can update | Developer required |

## Integration Strategy

### Microsoft Graph API

| Integration | Endpoint | Called From | Purpose |
|---|---|---|---|
| User profiles | `GET /users/{id}` | Azure Function | Auto-populate ticket submitter details |
| Profile photos | `GET /users/{id}/photo` | SPFx web parts | Show avatars in ticket dashboard |
| Manager chain | `GET /users/{id}/manager` | Azure Function | VIP ticket routing |
| Teams notifications | `POST /chats/{id}/messages` | Power Automate | Ticket status updates |
| SharePoint search | `POST /search/query` | SPFx web part | Full-text KB search |
| Send mail | `POST /users/{id}/sendMail` | Power Automate | Ticket confirmation emails |

### Custom Connector

```
Canvas App / Power Automate
        |
        v
  Custom Connector (OpenAPI)
        |  (OAuth 2.0 via Entra ID)
        v
  Azure Function App (.NET 10)
    /api/email-to-ticket    [POST]
    /api/sync-users          [POST]
    /api/webhook             [POST]
    /api/classify-ticket     [POST]
```

OpenAPI spec auto-generated from .NET 10 minimal API. Imported into Power Platform custom connector wizard. Auth: Entra ID OAuth 2.0.

## Anti-Patterns Avoided

| Anti-Pattern | Risk | How We Avoid It |
|---|---|---|
| Everything in SharePoint Lists | 5K threshold, no row-level security, delegation failures | Dataverse for all transactional data |
| Analytical queries against Dataverse | API limit exhaustion, degraded app performance | Separate Azure SQL reporting warehouse |
| Power Apps iframe in SharePoint | 3-5s load, broken theming, navigation isolation | Native SPFx web parts |
| All logic in Power Automate | 200-step monster flows, painful email parsing | Power Automate orchestrates, Azure Functions execute |
| Editing in Production | No rollback, no audit, "someone broke the flow" | Managed solutions, Dev → Test → Prod ALM |
| Flat security model | Everyone sees everything, app-level security bypassed by API | Dataverse platform-level security roles + BUs |
| Monolithic single-store | One outage = total failure, OLTP/OLAP compete | Three stores with fault isolation |
| Custom bot from scratch | 40+ hours, hard to maintain | Copilot Studio + Power Automate extension |
