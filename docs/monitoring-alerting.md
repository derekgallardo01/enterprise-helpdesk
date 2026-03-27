# Enterprise Help Desk — Monitoring & Alerting Architecture

## Monitoring Stack

The monitoring architecture uses four complementary layers, each serving a different audience and time horizon.

| Layer | Tool | Purpose | Audience |
|---|---|---|---|
| **Telemetry** | Application Insights | Function execution traces, dependency calls, exceptions, custom metrics | Developers, on-call engineers |
| **Aggregation** | Log Analytics Workspace | Centralized log storage, KQL queries, cross-resource correlation | Developers, engineering leads |
| **Alerting** | Azure Monitor | Threshold-based alerts, action groups, escalation rules | On-call engineers (automated) |
| **Visualization** | Power BI + Azure Workbooks | Operational dashboards, trend analysis, executive reporting | Managers, IT leadership, on-call engineers |

**Why this stack**: Every component is native to Azure or M365 — no third-party monitoring tools to license, integrate, or maintain. Application Insights and Log Analytics share the same underlying data store (Azure Monitor Logs), so telemetry flows seamlessly from function-level traces to workspace-level queries to alert rules.

## Health Check Architecture

### `/api/health` Endpoint

The Azure Function App exposes a health endpoint that validates connectivity to all downstream dependencies in a single call.

```csharp
[Function("HealthCheck")]
public async Task<IActionResult> Run(
    [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "health")] HttpRequest req)
{
    var results = new Dictionary<string, string>();

    // 1. Dataverse connectivity — WhoAmI request
    try
    {
        var response = await _dataverseClient.ExecuteAsync(new WhoAmIRequest());
        results["dataverse"] = "OK";
    }
    catch (Exception ex)
    {
        results["dataverse"] = $"FAIL: {ex.Message}";
    }

    // 2. Azure SQL connectivity — lightweight query
    try
    {
        await using var conn = new SqlConnection(_sqlConnectionString);
        await conn.OpenAsync();
        await using var cmd = new SqlCommand("SELECT 1", conn);
        await cmd.ExecuteScalarAsync();
        results["sql"] = "OK";
    }
    catch (Exception ex)
    {
        results["sql"] = $"FAIL: {ex.Message}";
    }

    // 3. Key Vault access — read a known secret
    try
    {
        await _secretClient.GetSecretAsync("HealthCheckProbe");
        results["keyvault"] = "OK";
    }
    catch (Exception ex)
    {
        results["keyvault"] = $"FAIL: {ex.Message}";
    }

    var allHealthy = results.Values.All(v => v == "OK");
    return new JsonResult(results) { StatusCode = allHealthy ? 200 : 503 };
}
```

**Response format**:
```json
{
    "dataverse": "OK",
    "sql": "OK",
    "keyvault": "OK"
}
```

Returns HTTP 200 if all checks pass. Returns HTTP 503 if any check fails (with the failure detail in the response body). The endpoint is unauthenticated (`AuthorizationLevel.Anonymous`) so Azure Monitor availability tests can call it without token management.

### Azure Monitor Availability Tests

| Test | Type | Frequency | Timeout | Locations |
|---|---|---|---|---|
| Health endpoint ping | URL ping test | Every 5 minutes | 30 seconds | 5 Azure regions (East US, West US, North Europe, Southeast Asia, Brazil South) |
| Health endpoint validation | Multi-step web test | Every 5 minutes | 120 seconds | 3 Azure regions |

The multi-step test parses the JSON response body and fails if any dependency reports `FAIL`. This catches partial failures (e.g., SQL down but Dataverse healthy) that a simple HTTP status check might miss if the endpoint returns 503 but the alert only checks for network-level failure.

### Canary Test: Synthetic Ticket Lifecycle

An hourly canary test validates the full end-to-end ticket pipeline:

```
[Timer Trigger: 0 0 * * * *]  (every hour on the hour)
    |
    1. Create ticket in Dataverse via SDK
       - hd_title = "CANARY-{timestamp}"
       - hd_source = Portal
       - hd_category = "Software" (test category)
    |
    2. Wait 90 seconds (allow Power Automate routing to fire)
    |
    3. Verify ticket was auto-assigned
       - Query hd_Ticket where hd_title = "CANARY-{timestamp}"
       - Assert hd_assignedto is not null
       - Assert hd_duedate is populated (SLA profile applied)
    |
    4. Verify sync to Azure SQL
       - Query TicketFact where TicketNumber = canary ticket number
       - Assert row exists (may take up to 15 min — check with retry)
    |
    5. Cleanup: Delete the canary ticket
       - Hard delete to avoid polluting production data
    |
    6. Log result to Application Insights
       - Custom event: "CanaryTest"
       - Properties: { result: "Pass"/"Fail", step: "last successful step", durationMs }
```

**Why a canary test**: The health endpoint validates connectivity. The canary test validates behavior — that Power Automate actually routes tickets, that SLA profiles are applied, and that the SQL sync pipeline is functioning. A canary failure with a passing health check indicates a logic or configuration problem, not an infrastructure outage.

### Power Automate Flow Monitor

A dedicated Azure Function runs every 15 minutes to check Power Automate flow health:

1. Query the Power Automate Management API for flow run history in the last 30 minutes
2. Flag any flows with `status = Failed`
3. Log failures to Application Insights with flow name, error code, and error message
4. Trigger an alert if critical flows (`HD-TicketRouting`, `HD-SLATimer`, `HD-Escalation`) have failed

## Alert Thresholds

| Metric | Warning | Critical | Action |
|---|---|---|---|
| Function invocation failure rate | >1% over 5 min window | >5% over 5 min window | Page on-call engineer |
| `DataverseSyncToSQL` latency | >20 min since last successful run | >45 min since last successful run | Page on-call engineer |
| Azure SQL CPU utilization | >70% sustained for 15 min | >85% sustained for 5 min | Auto-scale up (alert group triggers runbook) |
| Azure SQL DTU consumption | >80% | >90% | Auto-scale up (alert group triggers runbook) |
| Dataverse API 429 responses | >10 per hour | >50 per hour | Investigate API usage patterns |
| Health endpoint down | 1 consecutive failure from any location | 3 consecutive failures from 2+ locations | Page on-call engineer |
| Canary test failure | 1 failure | 2 consecutive failures | Investigate — likely Power Automate or sync issue |
| Power Automate flow failure | Any single failure | 3+ failures in 1 hour | Investigate — check connection health |
| SPFx page load time | >3s at P95 | >5s at P95 | Investigate — check CDN, API latency, bundle size |
| Email processing backlog | >10 unprocessed emails | >50 unprocessed emails | Page on-call engineer |

### Alert Configuration

All alerts are configured in Azure Monitor with action groups:

```
Azure Monitor Alert Rule
    → evaluates metric/log query
    → fires action group "HelpDesk-OnCall"
        → Email: helpdesk-oncall@contoso.com
        → Teams webhook: #helpdesk-incidents channel
        → PagerDuty integration (Critical alerts only)
```

**Suppression rules**: Alerts are suppressed during announced maintenance windows (configured in Azure Monitor → Alert processing rules). This prevents false pages during planned deployments.

**Auto-resolve**: Warning-level alerts auto-resolve when the metric returns to normal. Critical alerts require manual acknowledgment in PagerDuty before they stop paging.

## Dashboard Design

### Dashboard 1: System Health (Azure Portal)

**Audience**: On-call engineers, developers
**Refresh**: Real-time (Application Insights Live Metrics) + 5-minute auto-refresh (pinned queries)

| Panel | Visualization | Data Source |
|---|---|---|
| Function execution rate | Line chart (requests/sec by function name) | Application Insights → `requests` table |
| Function failure rate | Line chart (failed requests/sec, stacked by function) | Application Insights → `requests` where `success == false` |
| Function duration (P50, P95, P99) | Line chart with percentile bands | Application Insights → `requests` → `percentile(duration, 50, 95, 99)` |
| Azure SQL DTU utilization | Area chart | Azure Monitor → SQL Database metrics |
| Azure SQL active connections | Line chart | Azure Monitor → SQL Database metrics |
| Dataverse API call volume | Bar chart (calls per 5 min) | Application Insights → `dependencies` where target contains "dynamics" |
| Dataverse API 429 throttling | Counter + spark line | Application Insights → `dependencies` where `resultCode == 429` |
| Health check status | Traffic light (green/red per dependency) | Application Insights → `customEvents` where name == "HealthCheck" |
| Active alerts | Table (alert name, severity, fired time) | Azure Monitor → Alerts API |

### Dashboard 2: Operational Overview (Power BI)

**Audience**: IT managers, engineering leads
**Refresh**: Every 15 minutes (DirectQuery to Azure SQL)

| Panel | Visualization | Data Source |
|---|---|---|
| Ticket volume — today vs. 7-day average | KPI card + trend line | `TicketFact` → `COUNT` by `CreatedOn` |
| Tickets by status | Donut chart | `TicketFact` → `COUNT` by `Status` |
| Tickets by priority | Stacked bar | `TicketFact` → `COUNT` by `Priority` |
| SLA compliance rate — current week | Gauge (target: 95%) | `TicketFact` → `SUM(CASE WHEN SLABreached = 0 THEN 1 END) / COUNT(*)` |
| Average resolution time — trend (4 weeks) | Line chart | `TicketFact` → `AVG(ResolutionMinutes)` by week |
| Sync status | Card (last sync time, rows synced) | Custom table updated by `DataverseSyncToSQL` |
| Top 5 categories — this week | Horizontal bar | `TicketFact` JOIN `CategoryDim` |
| Agent workload distribution | Heatmap (agent × priority) | `TicketFact` → `COUNT` by `AssignedToId`, `Priority` |

### Dashboard 3: Incident Dashboard (Azure Workbook)

**Audience**: On-call engineers during active incidents
**Refresh**: Manual refresh + auto-refresh every 1 minute during incidents

| Panel | Visualization | Data Source |
|---|---|---|
| Error trend — last 4 hours | Area chart (errors by function, 5-min buckets) | Log Analytics → `AppExceptions` |
| Dependency failure map | Node graph (function → dependency, colored by health) | Log Analytics → `AppDependencies` where `success == false` |
| Recent exceptions — detail | Table (timestamp, function, exception type, message) | Log Analytics → `AppExceptions` → last 100 |
| SLA breach alerts — active | Table (ticket number, category, time since breach) | Azure SQL → `TicketFact` where `IsOverdue = 1` |
| Power Automate flow failures | Table (flow name, error message, last failure time) | Application Insights → `customEvents` where name == "FlowMonitor" |
| Canary test results — last 24 hours | Timeline (pass/fail markers) | Application Insights → `customEvents` where name == "CanaryTest" |

## Log Analytics Queries

### 1. Function Execution Failures in Last 24 Hours

```kql
AppRequests
| where TimeGenerated > ago(24h)
| where Success == false
| summarize FailureCount = count(), LastFailure = max(TimeGenerated) by OperationName, ResultCode
| order by FailureCount desc
| project OperationName, ResultCode, FailureCount, LastFailure
```

**Use case**: Morning check — identify any functions that failed overnight and whether they recovered.

### 2. Dataverse API Throttling Events

```kql
AppDependencies
| where TimeGenerated > ago(24h)
| where Target contains "dynamics.com" or Target contains "crm.dynamics.com"
| where ResultCode == "429"
| summarize ThrottleCount = count() by bin(TimeGenerated, 15m), DependencyName = Name
| order by TimeGenerated desc
| render timechart
```

**Use case**: Identify when and which operations are being throttled. Spikes correlate with bulk operations or poorly optimized queries. Feed this into API budget planning.

### 3. Sync Duration Trends

```kql
AppRequests
| where TimeGenerated > ago(7d)
| where OperationName == "DataverseSyncToSQL"
| project TimeGenerated, DurationMs = DurationMs, RowsSynced = toint(Properties["RowsSynced"])
| summarize
    AvgDurationSec = avg(DurationMs) / 1000,
    P95DurationSec = percentile(DurationMs, 95) / 1000,
    AvgRowsSynced = avg(RowsSynced)
    by bin(TimeGenerated, 1h)
| order by TimeGenerated desc
| render timechart
```

**Use case**: Detect gradual performance degradation in the sync pipeline. If duration trends upward while row count stays flat, investigate SQL index fragmentation or Dataverse API slowdowns.

### 4. Error Rate by Function Name

```kql
AppRequests
| where TimeGenerated > ago(24h)
| summarize
    TotalInvocations = count(),
    Failures = countif(Success == false),
    ErrorRate = round(100.0 * countif(Success == false) / count(), 2)
    by OperationName
| order by ErrorRate desc
| project OperationName, TotalInvocations, Failures, ErrorRate
```

**Use case**: Quick health summary across all functions. Any function with an error rate above 1% warrants investigation.

### 5. End-to-End Ticket Creation Latency

```kql
let ticketCreations = AppDependencies
| where TimeGenerated > ago(24h)
| where Name == "Dataverse" and Data contains "hd_Ticket" and Data contains "Create"
| project OperationId, DataverseCallTime = TimeGenerated, DataverseDurationMs = DurationMs;
let syncOperations = AppRequests
| where TimeGenerated > ago(24h)
| where OperationName == "DataverseSyncToSQL"
| project SyncTime = TimeGenerated, SyncDurationMs = DurationMs;
ticketCreations
| extend NextSyncTime = toscalar(syncOperations | where SyncTime > DataverseCallTime | summarize min(SyncTime))
| extend EndToEndMinutes = datetime_diff('minute', NextSyncTime, DataverseCallTime)
| summarize
    AvgE2EMinutes = avg(EndToEndMinutes),
    P95E2EMinutes = percentile(EndToEndMinutes, 95),
    MaxE2EMinutes = max(EndToEndMinutes)
    by bin(DataverseCallTime, 1h)
| render timechart
```

**Use case**: Measure how long it takes from ticket creation in Dataverse to the data appearing in the SQL reporting warehouse. The target is < 15 minutes (one sync cycle). If P95 exceeds 30 minutes, investigate sync failures or queue backlog.

## Alerting Channels

| Channel | Used For | Configuration |
|---|---|---|
| **Email** | All alerts (Warning + Critical) | Azure Monitor Action Group → Email action → `helpdesk-oncall@contoso.com` distribution list |
| **Microsoft Teams** | All alerts (posted to incident channel) | Azure Monitor Action Group → Webhook action → Teams incoming webhook on `#helpdesk-incidents` channel |
| **PagerDuty** | Critical alerts only (pages on-call engineer) | Azure Monitor Action Group → Webhook action → PagerDuty Events API v2 integration key |
| **ServiceNow** (optional) | Auto-create incident tickets for Critical alerts | Azure Monitor Action Group → ITSM action → ServiceNow connector (if organization uses ServiceNow for IT operations) |

### Channel Routing Logic

```
Warning Alert
    → Email (helpdesk-oncall@contoso.com)
    → Teams (#helpdesk-incidents)
    → No page

Critical Alert
    → Email (helpdesk-oncall@contoso.com)
    → Teams (#helpdesk-incidents)
    → PagerDuty (page on-call)
    → ServiceNow (auto-create incident)
```

**Why both Teams and email**: Teams is the primary real-time channel, but email ensures alerts are not missed if Teams is down (Teams and Azure Monitor are independent services). PagerDuty provides phone/SMS escalation for critical alerts that go unacknowledged.

## On-Call Rotation

### Recommended Structure

| Role | Count | Schedule | Responsibilities |
|---|---|---|---|
| **Primary on-call** | 1 person | Weekly rotation (Monday 9 AM → Monday 9 AM) | First responder for all alerts. Acknowledge within 15 minutes. Triage and resolve or escalate. |
| **Secondary on-call** | 1 person | Weekly rotation (offset by 1 week from primary) | Backup if primary does not acknowledge within 30 minutes. Automatically paged by PagerDuty escalation policy. |
| **Engineering lead** | 1 person | Permanent (escalation only) | Escalation point for Major Incidents (L3+). Makes architectural decisions during incidents. |

### Rotation Rules

- **Minimum team size**: 4 engineers to sustain a weekly rotation without burnout (each person is on-call 1 week in 4)
- **Handoff**: Monday 9 AM local time. Outgoing on-call posts a summary of any active issues in `#helpdesk-incidents`
- **Quiet hours**: 10 PM - 7 AM local time. During quiet hours, only Critical alerts page. Warning alerts queue until morning.
- **Compensation**: On-call time compensated per organizational policy. Incident response during quiet hours qualifies for time-in-lieu.
- **Swap policy**: Engineers can swap on-call weeks via PagerDuty self-service. Swaps must be completed 48 hours before the rotation starts.

### Escalation Timeline

```
T+0 min     Alert fires → Primary on-call paged
T+15 min    No acknowledgment → Secondary on-call paged
T+30 min    No acknowledgment → Engineering lead paged + email to IT Director
T+60 min    No resolution → Automatic escalation to L3 (Major Incident)
```

## Telemetry Standards

Every Azure Function must log consistent telemetry to enable the dashboards and queries above. These standards are enforced via a shared `TelemetryHelper` class.

### Required Custom Properties (on every function invocation)

| Property | Type | Example | Purpose |
|---|---|---|---|
| `FunctionName` | string | `"DataverseSyncToSQL"` | Already logged by Azure Functions runtime, but included explicitly for custom events |
| `Environment` | string | `"Production"` | Distinguish Dev/Test/Prod telemetry in shared Application Insights |
| `CorrelationId` | string (GUID) | `"a1b2c3d4-..."` | Trace a single operation across function → Dataverse → SQL |
| `TriggerType` | string | `"Timer"`, `"HTTP"`, `"Queue"` | Filter by trigger type in dashboards |

### Required Custom Metrics (per function type)

**Sync functions** (`DataverseSyncToSQL`):

| Metric | Type | Description |
|---|---|---|
| `RowsSynced` | int | Number of rows upserted in this sync cycle |
| `RowsDeleted` | int | Number of rows soft-deleted in this sync cycle |
| `SyncDurationMs` | long | Total sync duration in milliseconds |
| `ChangeTokenAge` | string | Delta token timestamp — indicates how far behind the sync is |

**Email processing** (`EmailToTicket`):

| Metric | Type | Description |
|---|---|---|
| `EmailsProcessed` | int | Number of emails parsed in this invocation |
| `TicketsCreated` | int | Number of tickets successfully created |
| `ParseFailures` | int | Number of emails that could not be parsed (logged individually as warnings) |
| `BacklogSize` | int | Number of unprocessed emails remaining in the mailbox |

**Health check** (`HealthCheck`):

| Metric | Type | Description |
|---|---|---|
| `DataverseLatencyMs` | long | WhoAmI call duration |
| `SqlLatencyMs` | long | SELECT 1 call duration |
| `KeyVaultLatencyMs` | long | GetSecret call duration |

**Webhook receiver** (`WebhookReceiver`):

| Metric | Type | Description |
|---|---|---|
| `PayloadSizeBytes` | int | Inbound payload size |
| `ProcessingDurationMs` | long | Time to process the webhook |
| `WebhookSource` | string | Identifier for the sending system |

### Logging Levels

| Level | When to Use | Example |
|---|---|---|
| `Information` | Normal operation milestones | "Sync completed: 47 rows upserted, 2 deleted" |
| `Warning` | Recoverable issues that may need attention | "Email parse failed for message ID abc123 — no subject line. Skipped." |
| `Error` | Unrecoverable failures in the current operation | "Dataverse API returned 500 for ticket create. Retry exhausted." |
| `Critical` | System-level failure requiring immediate attention | "Managed identity token acquisition failed. All Dataverse calls will fail." |

**Rule**: Never log at `Error` or `Critical` without including the exception object. The exception stack trace is essential for diagnosis.

### Example: Instrumented Function

```csharp
[Function("DataverseSyncToSQL")]
public async Task Run([TimerTrigger("0 */15 * * * *")] TimerInfo timer)
{
    var correlationId = Guid.NewGuid().ToString();
    using var scope = _logger.BeginScope(new Dictionary<string, object>
    {
        ["CorrelationId"] = correlationId,
        ["Environment"] = _config["Environment"],
        ["TriggerType"] = "Timer"
    });

    var sw = Stopwatch.StartNew();
    try
    {
        var result = await _syncService.ExecuteAsync();
        sw.Stop();

        _telemetry.TrackEvent("SyncCompleted", new Dictionary<string, string>
        {
            ["CorrelationId"] = correlationId,
            ["ChangeTokenAge"] = result.TokenAge
        }, new Dictionary<string, double>
        {
            ["RowsSynced"] = result.RowsUpserted,
            ["RowsDeleted"] = result.RowsDeleted,
            ["SyncDurationMs"] = sw.ElapsedMilliseconds
        });

        _logger.LogInformation(
            "Sync completed: {RowsUpserted} upserted, {RowsDeleted} deleted in {Duration}ms",
            result.RowsUpserted, result.RowsDeleted, sw.ElapsedMilliseconds);
    }
    catch (Exception ex)
    {
        sw.Stop();
        _logger.LogError(ex,
            "Sync failed after {Duration}ms. CorrelationId: {CorrelationId}",
            sw.ElapsedMilliseconds, correlationId);
        throw; // Let Azure Functions retry policy handle it
    }
}
```
