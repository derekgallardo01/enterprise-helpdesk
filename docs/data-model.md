# Enterprise Help Desk — Data Model

## Overview

The data model is built on Dataverse with publisher prefix `hd`. All tables, columns, and relationships are packaged in a managed solution called `HelpDesk`.

## Entity Relationship Diagram

```
hd_Category (1) ────────< (N) hd_Subcategory       [Parental]
hd_Category (1) ────────< (N) hd_Ticket            [Referential]
hd_Category (1) ────────< (N) hd_KBArticleRef      [Referential]
hd_Subcategory (1) ────< (N) hd_Ticket             [Referential]
hd_Subcategory (N) >───  (1) hd_SLAProfile         [Referential]
hd_Ticket (1) ─────────< (N) hd_TicketComment      [Parental]
hd_Ticket (N) >──────── (1) systemuser (RequestedBy)  [Referential]
hd_Ticket (N) >──────── (1) systemuser (AssignedTo)   [Referential]
hd_Ticket (N) >──────── (1) team (AssignedTeam)       [Referential]
hd_Ticket (N) >──────── (1) hd_Asset                  [Referential]
hd_Asset (N) >───────── (1) systemuser (AssignedTo)    [Referential]
hd_Asset (N) >───────── (1) hd_Department              [Referential]
hd_Department (N) >──── (1) systemuser (Manager)       [Referential]
```

## Core Tables

### hd_Ticket (Primary Entity)

The central table. Every other component reads from or writes to this table.

| Column (Schema Name) | Display Name | Type | Details |
|---|---|---|---|
| `hd_ticketid` | Ticket ID | Primary Key (GUID) | Auto-generated |
| `hd_ticketnumber` | Ticket Number | Auto-number | Format: `TKT-{SEQNUM:6}` (e.g., TKT-000001) |
| `hd_title` | Title | Single Line (200) | Required |
| `hd_description` | Description | Multi-line (rich text) | Required |
| `hd_priority` | Priority | Choice | 1=Critical, 2=High, 3=Medium, 4=Low |
| `hd_status` | Status | Choice | 1=New, 2=Assigned, 3=In Progress, 4=Waiting on Requester, 5=Waiting on Third Party, 6=Resolved, 7=Closed, 8=Cancelled |
| `hd_category` | Category | Lookup → `hd_Category` | Required |
| `hd_subcategory` | Subcategory | Lookup → `hd_Subcategory` | Filtered by selected category |
| `hd_requestedby` | Requested By | Lookup → `systemuser` | The person who submitted the ticket |
| `hd_assignedto` | Assigned To | Lookup → `systemuser` | The agent working the ticket |
| `hd_assignedteam` | Assigned Team | Lookup → `team` | Support group (e.g., Hardware Support) |
| `hd_impact` | Impact | Choice | 1=Enterprise, 2=Department, 3=Individual |
| `hd_urgency` | Urgency | Choice | 1=Critical, 2=High, 3=Medium, 4=Low |
| `hd_source` | Source | Choice | 1=Portal, 2=Email, 3=Teams Bot, 4=Phone, 5=Walk-up |
| `hd_duedate` | Due Date | DateTime | Calculated from SLA profile by Power Automate |
| `hd_resolutiondate` | Resolution Date | DateTime | Stamped when status changes to Resolved |
| `hd_firstresponseat` | First Response At | DateTime | Stamped when first agent comment is added |
| `hd_slabreach` | SLA Breached | Yes/No | Set by Power Automate SLA timer flow |
| `hd_resolutionnotes` | Resolution Notes | Multi-line | Required when status = Resolved |
| `hd_satisfactionrating` | Satisfaction Rating | Whole Number | 1-5, set by requester after resolution |
| `hd_relatedasset` | Related Asset | Lookup → `hd_Asset` | Optional link to affected IT asset |
| `hd_environment` | Environment | Choice | 1=Production, 2=Staging, 3=Development |

#### Business Rules

| Rule | Trigger | Action | Why |
|---|---|---|---|
| Priority Matrix | Impact or Urgency changes | Auto-calculate Priority from Impact × Urgency matrix | Ensures consistent priority assignment across all agents |
| Require Resolution Notes | Status changes to Resolved | Make `hd_resolutionnotes` required | Prevents agents from closing tickets without documenting the fix |
| Require Assigned To | Status changes to Assigned | Make `hd_assignedto` required | Cannot assign a ticket to nobody |
| Stamp Resolution Date | Status changes to Resolved | Set `hd_resolutiondate` = `now()` | Enables SLA compliance calculation |
| Lock on Close | Status changes to Closed | Make all fields read-only | Closed tickets are immutable records |

#### Priority Matrix (Impact × Urgency)

|  | Urgency: Critical | Urgency: High | Urgency: Medium | Urgency: Low |
|---|---|---|---|---|
| **Impact: Enterprise** | Critical | Critical | High | Medium |
| **Impact: Department** | Critical | High | Medium | Medium |
| **Impact: Individual** | High | Medium | Low | Low |

#### Business Process Flow

```
New → Triage → In Progress → Resolution → Closure
 |       |          |             |           |
 |   Assign to   Begin work   Document    Verify with
 |   agent/team  on fix       resolution  requester,
 |                             notes       collect CSAT
 v
(Cancelled) — can exit from any stage
```

### hd_TicketComment

Child records representing the conversation thread on a ticket.

| Column | Type | Details |
|---|---|---|
| `hd_ticketcommentid` | Primary Key (GUID) | Auto-generated |
| `hd_ticket` | Lookup → `hd_Ticket` | Parental relationship (cascade delete) |
| `hd_commentbody` | Multi-line (rich text) | The comment text |
| `hd_commenttype` | Choice | 1=Public (visible to requester), 2=Internal (agents only) |
| `hd_createdby` | System field | Auto-populated |
| `hd_createdon` | System field | Auto-populated |

**Security note**: Internal comments (`hd_commenttype = 2`) are protected by a column-level security profile. Only users with the `HD - Agent` role or above can read `hd_commentbody` on internal comments. This applies even via direct API access — it's enforced at the platform level, not in the app UI.

### hd_Category

Top-level classification for tickets.

| Column | Type | Details |
|---|---|---|
| `hd_categoryid` | Primary Key | |
| `hd_name` | Single Line (100) | e.g., "Hardware", "Software", "Network", "Access & Permissions" |
| `hd_description` | Multi-line | Category description |
| `hd_isactive` | Yes/No | Soft delete pattern — inactive categories hidden from dropdowns |
| `hd_defaultteam` | Lookup → `team` | Default routing target for auto-assignment flow |
| `hd_sortorder` | Whole Number | Display order in dropdowns |

**Seed data**: Hardware, Software, Network & Connectivity, Access & Permissions, Email & Communication

### hd_Subcategory

Second-level classification, filtered by parent category.

| Column | Type | Details |
|---|---|---|
| `hd_subcategoryid` | Primary Key | |
| `hd_name` | Single Line (100) | e.g., "Laptop", "Monitor", "VPN" |
| `hd_category` | Lookup → `hd_Category` | Parental relationship |
| `hd_defaultpriority` | Choice | Suggested priority for this subcategory |
| `hd_slaprofile` | Lookup → `hd_SLAProfile` | SLA profile governing response/resolution times |
| `hd_isactive` | Yes/No | Soft delete |

**Seed data examples**:
- Hardware: Laptop, Desktop, Monitor, Keyboard/Mouse, Printer, Phone
- Software: Installation Request, Bug Report, License Request, Update/Patch
- Network: VPN, Wi-Fi, Internet, Firewall
- Access: New Account, Password Reset, Permission Change, Account Deactivation

### hd_Asset

IT asset tracking linked to tickets.

| Column | Type | Details |
|---|---|---|
| `hd_assetid` | Primary Key | |
| `hd_assettag` | Auto-number | Format: `AST-{SEQNUM:5}` |
| `hd_name` | Single Line (200) | e.g., "Dell Latitude 7440" |
| `hd_assettype` | Choice | 1=Laptop, 2=Desktop, 3=Monitor, 4=Phone, 5=Printer, 6=Server, 7=Software License |
| `hd_status` | Choice | 1=Active, 2=In Repair, 3=Retired, 4=Lost |
| `hd_assignedto` | Lookup → `systemuser` | Current holder |
| `hd_department` | Lookup → `hd_Department` | Owning department |
| `hd_purchasedate` | Date | |
| `hd_warrantyexpiry` | Date | |
| `hd_serialnumber` | Single Line (100) | |

### hd_SLAProfile

Defines response and resolution time targets.

| Column | Type | Details |
|---|---|---|
| `hd_slaprofileid` | Primary Key | |
| `hd_name` | Single Line (100) | e.g., "Standard", "VIP", "Critical Infrastructure" |
| `hd_firstresponseminutes` | Whole Number | Target first response time (e.g., 60, 240, 480) |
| `hd_resolutionminutes` | Whole Number | Target resolution time (e.g., 480, 1440, 2880) |
| `hd_businesshoursonly` | Yes/No | Whether SLA clock pauses outside business hours (M-F 8am-6pm) |
| `hd_priority` | Choice | Which priority level this profile applies to |

**Seed data**:

| Profile | First Response | Resolution | Business Hours Only |
|---|---|---|---|
| Critical Infrastructure | 15 min | 2 hours | No (24/7) |
| VIP | 30 min | 4 hours | Yes |
| Standard - Critical | 1 hour | 8 hours | Yes |
| Standard - High | 4 hours | 24 hours | Yes |
| Standard - Medium | 8 hours | 48 hours | Yes |
| Standard - Low | 24 hours | 5 business days | Yes |

### hd_Department

Organizational structure for routing and reporting.

| Column | Type | Details |
|---|---|---|
| `hd_departmentid` | Primary Key | |
| `hd_name` | Single Line (100) | e.g., "Engineering", "Finance", "HR" |
| `hd_manager` | Lookup → `systemuser` | Department manager |
| `hd_costcenter` | Single Line (20) | For chargeback reporting (e.g., "CC-4200") |

### hd_KBArticleRef

Lightweight Dataverse index pointing to SharePoint KB articles. Enables cross-referencing without duplicating content.

| Column | Type | Details |
|---|---|---|
| `hd_kbarticlerefid` | Primary Key | |
| `hd_title` | Single Line (200) | Mirror of SharePoint page title |
| `hd_sharepointurl` | URL | Link to the actual SharePoint page |
| `hd_category` | Lookup → `hd_Category` | Cross-reference to ticket categories |
| `hd_viewcount` | Whole Number | Incremented by Azure Function on page view |
| `hd_helpfulcount` | Whole Number | User feedback from SPFx "Was this helpful?" button |
| `hd_lastupdated` | DateTime | Synced from SharePoint page modified date |

## Azure SQL Star Schema (Reporting Warehouse)

Synced from Dataverse via Azure Function (`DataverseSyncToSQL`) using change tracking (delta sync every 15 minutes).

See [sql/schema.sql](../sql/schema.sql) for the full DDL.

### Fact Table: `dbo.TicketFact`

| Column | Type | Source |
|---|---|---|
| TicketId | UNIQUEIDENTIFIER PK | `hd_ticketid` |
| TicketNumber | NVARCHAR(20) | `hd_ticketnumber` |
| Title | NVARCHAR(200) | `hd_title` |
| CategoryId | UNIQUEIDENTIFIER FK | `hd_category` |
| SubcategoryId | UNIQUEIDENTIFIER FK | `hd_subcategory` |
| DepartmentId | UNIQUEIDENTIFIER FK | Requester's department |
| RequestedById | UNIQUEIDENTIFIER | `hd_requestedby` |
| AssignedToId | UNIQUEIDENTIFIER | `hd_assignedto` |
| Priority | INT | `hd_priority` |
| Status | INT | `hd_status` |
| Impact | INT | `hd_impact` |
| Urgency | INT | `hd_urgency` |
| Source | INT | `hd_source` |
| SLABreached | BIT | `hd_slabreach` |
| SatisfactionRating | INT | `hd_satisfactionrating` |
| CreatedOn | DATETIME2 | `createdon` |
| ResolvedOn | DATETIME2 | `hd_resolutiondate` |
| DueDate | DATETIME2 | `hd_duedate` |
| FirstResponseAt | DATETIME2 | `hd_firstresponseat` |
| ResolutionMinutes | AS COMPUTED | `DATEDIFF(MINUTE, CreatedOn, ResolvedOn)` |
| FirstResponseMinutes | AS COMPUTED | `DATEDIFF(MINUTE, CreatedOn, FirstResponseAt)` |
| IsOverdue | AS COMPUTED | `CASE WHEN DueDate < GETUTCDATE() AND Status NOT IN (6,7,8) THEN 1 ELSE 0 END` |

### Dimension Tables

- `dbo.CategoryDim` — CategoryId, CategoryName, IsActive
- `dbo.DepartmentDim` — DepartmentId, DepartmentName, ManagerName, CostCenter
- `dbo.AgentDim` — AgentId, DisplayName, Email, Team, BusinessUnit
- `dbo.DateDim` — DateKey (YYYYMMDD), FullDate, DayOfWeek, MonthName, Quarter, Year, IsBusinessDay

## Indexing Strategy

### Dataverse (Automatic + Custom)

- **Automatic**: All lookup columns and choice columns are indexed by default
- **Custom Find Columns**: Add `hd_ticketnumber` and `hd_title` as find columns for fast search
- **Alternate Key**: `hd_ticketnumber` — enables upsert by ticket number from external systems

### Azure SQL

```sql
-- Most common query patterns
CREATE INDEX IX_TicketFact_Status ON dbo.TicketFact (Status) INCLUDE (Priority, CategoryId, CreatedOn);
CREATE INDEX IX_TicketFact_CreatedOn ON dbo.TicketFact (CreatedOn) INCLUDE (Status, CategoryId, Priority);
CREATE INDEX IX_TicketFact_CategoryId ON dbo.TicketFact (CategoryId) INCLUDE (Status, Priority, CreatedOn, ResolvedOn);
CREATE INDEX IX_TicketFact_AssignedToId ON dbo.TicketFact (AssignedToId) INCLUDE (Status, CreatedOn, ResolvedOn);
```
