# Runbook: Power BI Stale Data

## Severity: P3

## Detection

- **Alert**: Application Insights fires `powerbi-stale-data` when the `SyncState` table shows `LastSyncTime` more than 1 hour old, or when the Power BI dataset refresh fails.
- **User Report**: A manager reports that Power BI dashboard numbers do not match what agents see in the model-driven app. Typical complaint: "The SLA dashboard says 95% but we know we missed several tickets today."
- **Monitoring**: Power BI Service → Dataset → Refresh history shows failed refreshes.

## Impact

- Operational dashboards display outdated ticket counts, SLA compliance percentages, queue depths, and resolution times.
- Executive summary reports used for staffing and budget decisions are inaccurate.
- Row-level security filters in Power BI may show stale team membership if the user dimension is outdated.
- No impact on transactional operations — ticket creation, updates, routing, and SLA enforcement in Dataverse and Power Automate are unaffected.

## Diagnosis Steps

1. **Determine which layer is stale.** The data pipeline has three stages, and the stale point could be any of them:

   | Stage | Source | Destination | Mechanism |
   |---|---|---|---|
   | 1. Sync | Dataverse | Azure SQL base tables | `DataverseSyncToSQL` Azure Function (timer-triggered) |
   | 2. Aggregation | Azure SQL base tables | Azure SQL aggregation tables | Stored procedures (`sp_AggregateTicketMetrics`, etc.) |
   | 3. Refresh | Azure SQL aggregation tables | Power BI dataset | DirectQuery (real-time) or Import (scheduled refresh) |

2. **Check Stage 1 — Dataverse to SQL sync.** Query the `SyncState` table:

   ```sql
   SELECT TableName, LastSyncTime, SyncToken, ErrorMessage
   FROM dbo.SyncState
   ORDER BY LastSyncTime DESC;
   ```

   If `LastSyncTime` is more than 15 minutes old, the sync function has stalled. Follow the [Sync Failure runbook](./sync-failure.md) for full diagnosis.

3. **Check Stage 2 — Aggregation stored procedures.** Verify the last execution time:

   ```sql
   SELECT
       OBJECT_NAME(object_id) AS proc_name,
       last_execution_time,
       execution_count
   FROM sys.dm_exec_procedure_stats
   WHERE OBJECT_NAME(object_id) LIKE 'sp_Aggregate%'
   ORDER BY last_execution_time DESC;
   ```

   If the stored procedures have not run recently, they may have been skipped by the SQL Agent job or the orchestrating function.

4. **Check Stage 3 — Power BI dataset refresh.** Open Power BI Service → Workspace → Dataset → Refresh history. Look for:
   - **Failed refresh**: Note the error message. Common causes: expired SQL credentials, gateway offline (if using on-premises gateway), query timeout.
   - **No recent refresh**: The scheduled refresh may be disabled or misconfigured.
   - **DirectQuery**: If the dataset uses DirectQuery, there is no scheduled refresh — the issue is in Stage 1 or Stage 2.

5. **Check DirectQuery connection health.** If Power BI uses DirectQuery to Azure SQL, verify the connection:
   - Open Power BI Service → Dataset → Settings → Data source credentials.
   - Confirm the credentials are valid and not expired.
   - Check Azure SQL firewall rules — Power BI Service IPs must be allowed.

6. **Check row-level security (RLS).** If data appears stale only for certain managers, the issue may be an RLS role mapping mismatch rather than a data freshness problem. Verify the user-to-role mapping in the Power BI dataset.

## Resolution Steps

1. **If the sync function has stalled (Stage 1)**: Follow the [Sync Failure runbook](./sync-failure.md). Once the sync is restored, Stages 2 and 3 will pick up the fresh data automatically (if using DirectQuery) or on the next refresh (if using Import mode).

2. **If aggregation stored procedures have not run (Stage 2)**: Manually execute them:

   ```sql
   EXEC dbo.sp_AggregateTicketMetrics;
   EXEC dbo.sp_AggregateSLACompliance;
   EXEC dbo.sp_AggregateAgentPerformance;
   ```

   If the stored procedures fail, check for:
   - Lock contention (the sync function may be writing while the sproc tries to read).
   - Missing data in base tables (the sync may have partially completed).
   - Schema changes (a recent deployment may have altered columns the sproc references).

3. **If the Power BI dataset refresh failed (Stage 3 — Import mode)**:
   - If credentials expired: Update credentials in Power BI Service → Dataset → Settings → Data source credentials. Use the Azure SQL managed identity connection or update the SQL username/password.
   - If the gateway is offline: Restart the on-premises data gateway service. If no gateway is needed (cloud-only Azure SQL), verify the firewall rules.
   - Manually trigger a refresh: Power BI Service → Dataset → Refresh now.

4. **If DirectQuery credentials have expired (Stage 3 — DirectQuery mode)**:

   Update the data source credentials in Power BI Service. If using SQL authentication, rotate the password in Azure SQL and update both Key Vault and the Power BI connection:

   ```bash
   az sql server update \
     --name helpdesk-sql \
     --resource-group helpdesk-rg \
     --admin-password "<new-password>"
   ```

5. **Verify recovery**: Open the Power BI dashboard and confirm:
   - Ticket counts match the model-driven app.
   - SLA percentages reflect recent resolutions.
   - The "Last Updated" timestamp (if displayed) shows a recent time.

## Escalation Path

| Condition | Escalate To |
|---|---|
| Sync function stalled for more than 2 hours | See [Sync Failure runbook](./sync-failure.md) escalation path |
| Power BI Service refresh repeatedly fails after credential update | Power BI Administrator |
| On-premises data gateway is offline and cannot be restarted | Infrastructure team |
| Executives are citing inaccurate numbers in decisions | IT Service Manager (issue a data freshness advisory) |
| RLS misconfiguration exposes data across business units | Security Team (P1 escalation) |

## Prevention

1. **Sync monitoring alerts**: The `sync-overdue` alert (30-minute threshold) catches Stage 1 failures. Add a second alert at 15 minutes for early warning.
2. **Scheduled stored procedure execution**: Run aggregation stored procedures on a fixed schedule (every 10 minutes via SQL Agent or Azure Functions timer) rather than relying on manual execution.
3. **Power BI refresh failure alerts**: Configure Power BI Service to send email notifications on dataset refresh failure. Route these to the platform team distribution list.
4. **Credential rotation calendar**: Track all credential expiry dates (SQL credentials, service principal secrets, gateway keys) in a shared calendar with 30-day advance reminders.
5. **End-to-end data freshness test**: A weekly automated test that creates a ticket in Dataverse, waits for it to appear in the Power BI dataset, and alerts if the end-to-end latency exceeds 15 minutes.

## Related Alerts

| Alert Name | Condition | Severity |
|---|---|---|
| `powerbi-stale-data` | SyncState.LastSyncTime > 1 hour old | Warning |
| `sync-overdue` | No successful DataverseSyncToSQL run in 30 minutes | Warning |
| `aggregation-sproc-failed` | Aggregation stored procedure execution failed | Warning |
| `powerbi-refresh-failed` | Power BI dataset scheduled refresh failed | Warning |
| `sql-credential-expiry-30d` | Azure SQL credential expires within 30 days | Warning |
