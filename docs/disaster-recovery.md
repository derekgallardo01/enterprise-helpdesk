# Enterprise Help Desk — Disaster Recovery & Business Continuity Plan

## Objectives

| Metric | Target | Rationale |
|---|---|---|
| **RTO (Recovery Time Objective)** | 4 hours | Maximum acceptable downtime before ticket operations must be restored |
| **RPO (Recovery Point Objective) — Transactional** | 0 minutes | Dataverse and Power Automate operate on Microsoft-managed infrastructure with synchronous replication. No ticket data loss is acceptable. |
| **RPO (Recovery Point Objective) — Analytics** | 15 minutes | Azure SQL reporting warehouse syncs via `DataverseSyncToSQL` every 15 minutes. Losing one sync cycle is acceptable — the data still exists in Dataverse and will backfill on recovery. |

**Why these targets**: Ticket operations are business-critical — agents cannot triage incidents without Dataverse and Power Automate. Reporting is important but read-only; a 15-minute gap in dashboards does not block any operational workflow.

## System Tier Classification

Every component is classified by its impact on ticket operations when unavailable.

### Tier 1 — Critical (Must recover first)

| Component | Function | Impact If Down |
|---|---|---|
| **Dataverse** | Ticket CRUD, security roles, business rules, audit trail | Total operational failure. No tickets can be created, updated, or viewed. Agents and requesters are fully blocked. |
| **Power Automate** | Ticket routing, SLA timer, escalation, approval workflows | New tickets sit unassigned. SLA clocks stop. Escalations do not fire. Agents can still work existing tickets manually, but no automation. |

### Tier 2 — Important (Recover after Tier 1)

| Component | Function | Impact If Down |
|---|---|---|
| **Azure Functions** | Dataverse-to-SQL sync, email-to-ticket parsing, Graph API integration, webhook receiver | SQL reporting warehouse goes stale. Inbound emails queue in the mailbox (no data loss — emails persist). User profile enrichment fails gracefully. |
| **Azure SQL** | Reporting data warehouse, Power BI DirectQuery source | Power BI dashboards fail. Ticket operations are completely unaffected — Dataverse is the source of truth. |

### Tier 3 — Deferrable (Recover last)

| Component | Function | Impact If Down |
|---|---|---|
| **Power BI** | Operational dashboards, SLA reports, executive summary | Managers lose visibility into metrics. No impact on ticket operations. Reports catch up automatically once restored. |
| **Copilot Studio** | AI-powered self-service bot in Teams | End users cannot use the bot to submit or check tickets. They fall back to the SharePoint portal or direct email. |
| **SPFx Web Parts** | SharePoint portal (ticket dashboard, KB search) | End users cannot use the portal. They fall back to the model-driven Power App or Teams bot. Agents are unaffected. |

**Why this tiering matters**: During a multi-component outage, the recovery team focuses on Dataverse and Power Automate first. Restoring those two components brings back 100% of core ticket operations. Everything else is a read-only overlay or an alternative channel.

## Backup Strategy

### Dataverse

| Aspect | Detail |
|---|---|
| **Automatic backups** | Microsoft-managed, continuous. 7-day retention. Taken automatically — no configuration needed. |
| **Manual backups** | Triggered via Power Platform admin center before major changes (solution imports, bulk data operations, schema changes). |
| **Point-in-time restore** | Available via admin center. Restores the entire environment to any point within the 7-day window. Granularity: 1 minute. |
| **Restore target** | Can restore to the same environment (overwrites current state) or to a new sandbox environment (for validation before promoting). |
| **What is backed up** | All tables, rows, security roles, business rules, workflows, environment variables, connection references. |
| **What is NOT backed up** | Audit log data older than the retention window, integration runtime state (Power Automate run history). |

**Pre-change backup procedure**:
1. Navigate to Power Platform admin center → Environments → `HelpDesk-Prod`
2. Select **Backups** → **Create** (manual)
3. Label: `Pre-[change description]-YYYYMMDD` (e.g., `Pre-SLASchemaChange-20260326`)
4. Wait for confirmation (typically < 5 minutes)
5. Proceed with the change

### Azure SQL

| Aspect | Detail |
|---|---|
| **Point-in-time restore (PITR)** | Automated. Retention: 7 days (Basic tier) to 35 days (Standard/Premium). Full backup weekly, differential every 12 hours, transaction log every 5-10 minutes. |
| **Long-term retention (LTR)** | Weekly full backup retained for 5 weeks, monthly for 12 months, yearly for 3 years. Configured via Azure Portal → SQL Database → Long-term retention. |
| **Geo-redundant backup storage** | Enabled. Backup blobs replicated to a paired Azure region. Enables cross-region restore if the primary region is entirely unavailable. |
| **Restore procedure** | Azure Portal → SQL Database → Restore → select point-in-time → restore to new database → validate → swap connection strings. |

**Why long-term retention matters**: Even though the SQL warehouse is a derived copy of Dataverse, LTR preserves historical analytical snapshots that may not be reconstructible if Dataverse audit retention has expired.

### SharePoint

| Aspect | Detail |
|---|---|
| **Versioning** | Enabled on all document libraries and pages. 500 major versions retained. Any version can be restored by a site owner. |
| **Recycle bin** | First-stage: 93-day retention (user-accessible). Second-stage: 93-day retention (site collection admin). Total: up to 186 days. |
| **Preservation hold library** | Automatically captures versions of content under retention policies. Prevents permanent deletion even if a user empties the recycle bin. |
| **Site collection backup** | Microsoft-managed. 14-day retention. Restore via SharePoint admin center or support ticket. |

### Azure Functions

| Aspect | Detail |
|---|---|
| **Code** | Git repository is the source of truth. All function code is version-controlled. Redeployment from any commit takes < 10 minutes via GitHub Actions. |
| **Configuration** | Application settings reference Azure Key Vault. Key Vault has soft-delete enabled (90-day retention) and purge protection (90-day hold). No secrets are stored in app settings directly. |
| **Application Insights data** | 90-day retention (default). Extended to 180 days for production. Historical telemetry is not required for recovery — it is diagnostic only. |
| **Deployment slots** | Production slot + staging slot. Staging validates before swap. If a deployment causes failures, swap back to the previous slot in < 30 seconds. |

## Failover Procedures

### Tier 1: Dataverse Environment Unavailable

**Symptoms**: Power Apps return "Environment not found" or timeout. Power Automate flows fail with Dataverse connector errors. SPFx web parts show "Unable to connect to data source."

**Immediate actions** (0-15 minutes):
1. Check [Microsoft 365 Service Health](https://admin.microsoft.com/Adminportal/Home#/servicehealth) and [Power Platform status](https://status.power-platform.com/) for known incidents
2. Verify the issue is not tenant-specific: test a second Dataverse environment if available
3. Notify stakeholders via the Communication Plan (see below)

**If Microsoft-side outage** (wait for Microsoft resolution):
1. Log a Premier Support case via the Power Platform admin center
2. Monitor the service health dashboard for ETR (Estimated Time to Resolve)
3. Communicate ETR to stakeholders every 30 minutes
4. No local action possible — Dataverse is a fully managed service

**If environment corruption or accidental data loss**:
1. Identify the point-in-time to restore to (check audit logs, flow run history)
2. Restore to a **new sandbox** environment first (not directly to production)
3. Validate: run spot-check queries on key tables (`hd_Ticket`, `hd_Category`, `hd_SLAProfile`)
4. Verify security roles and business rules are intact
5. If validated, restore to the production environment
6. Trigger a manual `DataverseSyncToSQL` run to re-sync the reporting warehouse

**Recovery validation**: See the Recovery Validation Checklist below.

### Tier 1: Power Automate Flows Suspended

**Symptoms**: New tickets are not being auto-assigned. SLA timers are not firing. Escalation emails stop.

**Immediate actions**:
1. Navigate to Power Automate → Solutions → HelpDesk → check flow status
2. Common causes: connection expired, DLP policy change, license change, throttling

**If flows are turned off**:
1. Check the flow's run history for the error that caused suspension
2. Fix the root cause (re-authenticate connection, update DLP policy, etc.)
3. Turn flows back on in the correct order:
   - First: `HD-TicketRouting` (assigns new tickets)
   - Second: `HD-SLATimer` (starts SLA clocks)
   - Third: `HD-Escalation` (escalates breached tickets)
   - Fourth: All other flows
4. Manually process any tickets that were created during the outage:
   - Query `hd_Ticket` where `hd_status = New` and `hd_assignedto = null`
   - Trigger the routing flow manually for each, or assign manually

**If flows are throttled**:
1. Check Power Platform admin center → Analytics → Power Automate → Capacity
2. Identify the flow consuming the most runs
3. Optimize or temporarily disable non-critical flows to free capacity
4. Consider Power Automate per-flow licensing for high-volume flows

### Tier 2: Azure SQL Database Down

**Symptoms**: Power BI dashboards show "Unable to connect" or display stale data. `DataverseSyncToSQL` function logs connection errors.

**Immediate actions**:
1. Check Azure Portal → SQL Database → Overview for status and recent alerts
2. Check Azure Service Health for regional SQL outages

**If database is corrupted or deleted**:
1. Azure Portal → SQL Server → Deleted databases → Restore (if within retention)
2. Or: SQL Database → Restore → select point-in-time → restore to new database
3. Validate: run `SELECT COUNT(*) FROM dbo.TicketFact` and compare to Dataverse record count
4. Update Azure Function app settings to point to the restored database (if new server/name)
5. Trigger a full sync: set the change tracking token to null and run `DataverseSyncToSQL`

**If database is unresponsive (resource exhaustion)**:
1. Azure Portal → SQL Database → Compute + Storage → scale up to next tier
2. Monitor DTU/CPU for 15 minutes
3. Scale back down after load normalizes

**Impact reminder**: Power BI dashboards are unavailable during SQL downtime. All ticket operations continue normally in Dataverse.

### Tier 2: Azure Functions Not Executing

**Symptoms**: SQL warehouse not updating. Inbound emails not creating tickets. Webhook events not processing.

**Immediate actions**:
1. Azure Portal → Function App → Overview → check status (Running / Stopped)
2. Check Application Insights → Live Metrics for invocation activity
3. Check Azure Service Health for regional Functions outages

**If app is stopped**:
1. Restart via Azure Portal → Function App → Restart
2. If restart fails, check for deployment issues: review deployment center logs

**If app is running but functions fail**:
1. Check Application Insights → Failures → drill into exception details
2. Common causes: Key Vault access revoked, Dataverse S2S certificate expired, managed identity disabled
3. Fix the root cause, then verify each function:
   - `DataverseSyncToSQL`: Trigger manually → check SQL for new data
   - `EmailToTicket`: Send a test email → verify ticket created in Dataverse
   - `WebhookReceiver`: Send a test webhook payload → verify processing
   - `HealthCheck`: Call `/api/health` → verify 200 response

**If Functions infrastructure is unavailable (regional outage)**:
1. Inbound emails queue safely in the Exchange mailbox (no data loss)
2. SQL sync pauses — dashboards show stale data
3. Recovery: Functions will process the backlog automatically on restart

### Tier 3: SharePoint Site Inaccessible

**Symptoms**: KB portal returns 404 or access denied. SPFx web parts fail to load.

**Immediate actions**:
1. Check Microsoft 365 Service Health for SharePoint incidents
2. Verify the site collection has not been deleted: SharePoint admin center → Active sites
3. If deleted: Restore from the deleted sites list (retained for 93 days)

**If site is corrupted**:
1. Microsoft support ticket for site collection restore from backup (14-day window)
2. SPFx package can be redeployed from the app catalog backup or rebuilt from git

**Impact reminder**: SharePoint downtime does not affect ticket operations. Users fall back to the model-driven Power App or Teams bot.

## Geo-Redundancy Strategy

### Current State: Single-Region Deployment

All components are deployed to a single Azure region, matching the M365 tenant's data residency (e.g., East US).

| Component | Current Redundancy |
|---|---|
| Dataverse | Microsoft-managed within-region replication (multiple availability zones) |
| Azure SQL | Locally redundant storage (LRS) with geo-redundant backups |
| Azure Functions | Consumption plan, single-region |
| SharePoint | Microsoft-managed geo-redundancy (built into M365) |
| Power Automate | Microsoft-managed within-region |
| Power BI | Microsoft-managed within-region |

**Why single-region is acceptable today**: The 4-hour RTO target is achievable with within-region recovery for all components. Full regional outages across Microsoft's availability zones are rare (< 1 incident per year historically) and typically resolve within 2-4 hours.

### Scale Path: Multi-Region

If the organization requires a sub-1-hour RTO or operates in a regulated industry with mandatory geo-redundancy:

| Component | Multi-Region Strategy | Complexity |
|---|---|---|
| **Azure SQL** | Active geo-replication to a paired region. Automatic failover group with read-only secondary. Power BI redirects to secondary on failover. | Low — native Azure feature, < 1 hour to configure |
| **Azure Functions** | Deploy identical Function App to a secondary region. Azure Front Door routes traffic with health probe failover. Both regions share the same Key Vault (or replicated vault). | Medium — requires CI/CD pipeline update, Front Door configuration |
| **SPFx Assets** | CDN (Azure Front Door or SharePoint CDN) for static assets. Multi-region CDN provides automatic failover. | Low — configuration change only |
| **Dataverse** | **Limitation**: Dataverse environments are single-region. Cross-region failover requires a second environment in a different region with Synapse Link data federation for near-real-time replication. This is a significant architectural change. | High — requires Synapse Link, dual-environment management, custom failover logic |
| **Power Automate** | Follows Dataverse — flows run in the same region as the environment. Multi-region requires duplicate flows in the secondary environment. | High — tied to Dataverse multi-region |

**Recommendation**: Implement Azure SQL geo-replication and Functions multi-region first (low/medium effort, covers Tier 2 components). Defer Dataverse multi-region unless regulatory requirements demand it — the cost and complexity are significant, and Microsoft's within-region SLA for Dataverse is 99.9%.

## Restore Drill Schedule

Quarterly drills ensure the recovery team can execute procedures under pressure. All drills run against the `HelpDesk-Test` environment — never production.

### Q1 Drill: Dataverse Point-in-Time Restore

| Step | Action | Success Criteria |
|---|---|---|
| 1 | Create 50 test tickets in `HelpDesk-Test` with varied statuses and assignments | Tickets visible in model-driven app |
| 2 | Take a manual backup | Backup appears in admin center |
| 3 | Delete 25 tickets and modify 10 others | Confirm destructive changes |
| 4 | Restore to the backup point-in-time (new sandbox) | Restore completes within 30 minutes |
| 5 | Validate all 50 tickets exist with original data | Record counts and spot-check field values |
| 6 | Validate security roles and business rules | Test as Requester, Agent, and Manager personas |
| 7 | Document restoration time and any issues | Update this DR plan if procedures need adjustment |

### Q2 Drill: Azure SQL Recovery + Full Sync

| Step | Action | Success Criteria |
|---|---|---|
| 1 | Record current `TicketFact` row count and latest `CreatedOn` | Baseline established |
| 2 | Drop and recreate the test SQL database from PITR | Database restored within 15 minutes |
| 3 | Run `DataverseSyncToSQL` with reset change token (full sync) | Function completes without errors |
| 4 | Compare row counts and sample data between Dataverse and SQL | Counts match, data integrity confirmed |
| 5 | Verify Power BI dashboard reconnects and renders | All visuals load with current data |

### Q3 Drill: Azure Functions Redeployment from Git

| Step | Action | Success Criteria |
|---|---|---|
| 1 | Delete the test Function App entirely | App removed from Azure Portal |
| 2 | Redeploy from git using GitHub Actions pipeline | Deployment completes within 10 minutes |
| 3 | Verify Key Vault access and managed identity configuration | `/api/health` returns 200 with all checks passing |
| 4 | Send a test email and verify ticket creation | Ticket appears in Dataverse within 5 minutes |
| 5 | Trigger `DataverseSyncToSQL` and verify SQL update | New data appears in `TicketFact` |

### Q4 Drill: Full Multi-Component Recovery

| Step | Action | Success Criteria |
|---|---|---|
| 1 | Simulate simultaneous failure: Dataverse restore + SQL restore + Functions redeploy | All three recovery procedures initiated in parallel |
| 2 | Follow Tier 1 → Tier 2 → Tier 3 recovery order | Dataverse and Power Automate restored first |
| 3 | Verify end-to-end ticket lifecycle | Create ticket → auto-route → assign → resolve → verify in SQL → verify in Power BI |
| 4 | Measure total recovery time | Must be < 4 hours (RTO target) |
| 5 | Conduct post-drill retrospective | Document lessons learned, update procedures |

## Communication Plan

### Escalation Levels

| Level | Trigger | Who Is Notified | Channel | SLA |
|---|---|---|---|---|
| **L1 — Alert** | Automated alert fires (see monitoring doc) | On-call engineer | Teams channel + PagerDuty | Acknowledge within 15 minutes |
| **L2 — Incident** | Issue confirmed, user impact verified | On-call engineer + Engineering lead | Teams incident channel | Incident commander assigned within 30 minutes |
| **L3 — Major Incident** | Tier 1 component down > 30 minutes | Engineering lead + IT Director + Business stakeholders | Teams war room + Email broadcast | Executive update within 1 hour |
| **L4 — Crisis** | Tier 1 component down > 2 hours, or data loss detected | CIO + All stakeholders | All channels + Status page | Continuous updates every 30 minutes |

### Incident Commander Role

The Incident Commander (IC) is the single point of authority during a major incident:

- **Assigned**: The first engineering lead to acknowledge the L2 escalation
- **Responsibilities**:
  - Coordinates all recovery activities
  - Authorizes destructive recovery actions (environment restore, database overwrite)
  - Writes and sends stakeholder communications
  - Decides when to escalate from L2 to L3/L4
  - Leads post-incident review within 48 hours
- **Authority**: The IC can pull any team member into the incident and authorize emergency changes without the normal change management approval process
- **Handoff**: If the incident spans > 8 hours, the IC role rotates to the next available engineering lead

### Stakeholder Communication Templates

**Initial notification** (sent at L2):
> **[INCIDENT] Help Desk System — [Component] Issue Detected**
> We are investigating an issue affecting [component]. [Brief impact description]. Ticket operations are [fully operational / degraded / unavailable]. Next update in 30 minutes.

**Ongoing update** (every 30 minutes during L3/L4):
> **[UPDATE] Help Desk System — [Component] Recovery In Progress**
> Status: [Recovery step currently executing]. Estimated time to recovery: [ETR]. Ticket operations are [status]. Workaround: [if applicable].

**Resolution notification**:
> **[RESOLVED] Help Desk System — [Component] Restored**
> The issue has been resolved as of [time]. All systems are operating normally. [Brief root cause]. A full post-incident review will be shared within 48 hours.

## Recovery Validation Checklist

After any recovery event, run through this checklist before declaring the incident resolved. Every item must pass.

### Tier 1 Validation (Dataverse + Power Automate)

- [ ] **Dataverse connectivity**: Power Apps model-driven app loads and displays ticket list
- [ ] **Data integrity**: Spot-check 10 recent tickets — all fields populated correctly
- [ ] **Security roles**: Log in as Requester, Agent, and Manager — verify correct data visibility
- [ ] **Business rules**: Change a ticket's impact/urgency — verify priority auto-calculates
- [ ] **Business process flow**: Verify the BPF stages render and advance correctly
- [ ] **Audit trail**: Verify audit history is accessible on a ticket record
- [ ] **Power Automate flows**: All flows show status "On" in the solution
- [ ] **Ticket routing**: Create a test ticket — verify it is auto-assigned within 5 minutes
- [ ] **SLA timer**: Verify the test ticket's `hd_duedate` is populated correctly
- [ ] **Escalation**: Verify escalation flow is active (do not trigger in production — verify run history shows recent successful runs)

### Tier 2 Validation (Azure Functions + Azure SQL)

- [ ] **Health endpoint**: `GET /api/health` returns 200 with all checks passing (Dataverse: OK, SQL: OK, Key Vault: OK)
- [ ] **SQL connectivity**: Run `SELECT TOP 1 * FROM dbo.TicketFact` — returns data
- [ ] **Sync function**: Trigger `DataverseSyncToSQL` manually — verify new rows appear in SQL within 15 minutes
- [ ] **Email parsing**: Send a test email to the help desk mailbox — verify ticket created in Dataverse
- [ ] **Row count reconciliation**: Compare `hd_Ticket` count in Dataverse to `TicketFact` count in SQL — should match (within one sync cycle)
- [ ] **Power BI dashboards**: Open each dashboard — verify data loads and visuals render

### Tier 3 Validation (Portal + Bot + Dashboards)

- [ ] **SPFx web parts**: Navigate to the SharePoint portal — verify ticket dashboard and KB search load
- [ ] **Copilot Studio bot**: Open Teams → interact with the bot → verify it can retrieve ticket status
- [ ] **KB search**: Search for a known article — verify results appear
- [ ] **End-to-end test**: Submit a ticket via the SharePoint portal → verify it appears in the model-driven app → verify it syncs to SQL → verify it appears in Power BI

### Sign-Off

| Role | Name | Verified At | Signature |
|---|---|---|---|
| Incident Commander | | | |
| Engineering Lead | | | |
| IT Operations Manager | | | |
