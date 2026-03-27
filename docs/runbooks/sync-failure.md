# Runbook: DataverseSyncToSQL Failure

## Severity: P2

## Detection

- **Alert**: Application Insights fires `sync-overdue` when no successful `DataverseSyncToSQL` execution is recorded in the last 30 minutes.
- **User Report**: Managers report Power BI dashboards showing stale data — KPI numbers do not reflect tickets resolved in the last hour.
- **Monitoring**: The `SyncState` table in Azure SQL shows `LastSyncTime` more than 30 minutes old.

## Impact

- Power BI operational dashboards display stale ticket counts, SLA percentages, and queue depths.
- Executive summary reports are inaccurate — decisions may be made on outdated data.
- Aggregation stored procedures produce incorrect output because they operate on stale base tables.
- No impact on transactional operations — agents can still create, update, and resolve tickets in Power Apps. The model-driven app, Power Automate flows, and Copilot Studio bot are unaffected.

## Diagnosis Steps

1. Check the Azure Functions monitor for the `DataverseSyncToSQL` function. Open Azure Portal → Function App → Functions → DataverseSyncToSQL → Monitor. Look for:
   - Failed invocations (red entries) — note the error message.
   - Missing invocations (no entries in the expected time window) — the timer trigger may be disabled or the function app may be stopped.

2. Query Application Insights for recent exceptions:

   ```kusto
   exceptions
   | where timestamp > ago(1h)
   | where cloud_RoleName == "helpdesk-functions"
   | where operation_Name == "DataverseSyncToSQL"
   | order by timestamp desc
   | take 20
   ```

3. Check Dataverse change tracking status. If change tracking was disabled on a table (e.g., during a solution import), the sync function cannot retrieve deltas. Verify in Power Platform admin center → Tables → Ticket → Properties → Track changes = Enabled.

4. Check Azure SQL connectivity. The function uses managed identity to authenticate. Verify the managed identity still has access:

   ```sql
   SELECT dp.name, dp.type_desc, pe.permission_name
   FROM sys.database_principals dp
   JOIN sys.database_permissions pe ON dp.principal_id = pe.grantee_principal_id
   WHERE dp.name = 'helpdesk-functions';
   ```

5. Check Azure SQL database space. If the database has hit its size limit, inserts will fail:

   ```sql
   SELECT
       (SELECT SUM(size) * 8 / 1024 FROM sys.database_files WHERE type = 0) AS data_size_mb,
       (SELECT DATABASEPROPERTYEX(DB_NAME(), 'MaxSizeInBytes')) / 1024 / 1024 AS max_size_mb;
   ```

6. Check the `SyncState` table for the current sync token:

   ```sql
   SELECT TableName, LastSyncTime, SyncToken, ErrorMessage
   FROM dbo.SyncState
   ORDER BY LastSyncTime DESC;
   ```

   If `ErrorMessage` is populated, it indicates the last failure reason.

7. Check if the Function App itself is running. In Azure Portal → Function App → Overview, verify Status = Running. Check if the app was stopped by a deployment, scale-down, or manual action.

## Resolution Steps

1. **If the function app is stopped**: Start it from Azure Portal → Function App → Overview → Start.

2. **If the timer trigger is disabled**: Re-enable it from Azure Portal → Function App → Functions → DataverseSyncToSQL → Enable.

3. **If the sync token is corrupted** (error message mentions "invalid change tracking token" or "RetrieveEntityChanges failed"):

   ```sql
   UPDATE dbo.SyncState
   SET SyncToken = NULL, ErrorMessage = NULL
   WHERE TableName = 'hd_ticket';
   ```

   This forces a full re-sync on the next execution. For large datasets, consider running this during off-hours as a full sync will generate significant Dataverse API calls.

4. **If Azure SQL is out of space**: Scale the database tier or clean up old data:

   ```bash
   az sql db update \
     --name helpdesk-reporting \
     --server helpdesk-sql \
     --resource-group helpdesk-rg \
     --service-objective S1
   ```

5. **If Dataverse change tracking was disabled**: Re-enable it in Power Platform admin center → Tables → select table → Properties → Enable Track changes. Then reset the sync token (step 3) to force a full re-sync.

6. **If managed identity access was revoked**: Re-grant access in Azure SQL:

   ```sql
   CREATE USER [helpdesk-functions] FROM EXTERNAL PROVIDER;
   ALTER ROLE db_datareader ADD MEMBER [helpdesk-functions];
   ALTER ROLE db_datawriter ADD MEMBER [helpdesk-functions];
   GRANT EXECUTE TO [helpdesk-functions];
   ```

7. **Manually trigger the function** to verify the fix:

   ```bash
   az functionapp function invoke \
     --name helpdesk-functions \
     --resource-group helpdesk-rg \
     --function-name DataverseSyncToSQL
   ```

8. **Verify recovery**: Confirm the `SyncState` table shows an updated `LastSyncTime` and no `ErrorMessage`. Check Power BI dashboards to confirm data is current.

## Escalation Path

| Condition | Escalate To |
|---|---|
| Sync has been down more than 2 hours | Platform Team Lead |
| Dataverse change tracking cannot be re-enabled (solution lock) | Power Platform Admin |
| Azure SQL database is consistently near capacity | Database Administrator |
| Full re-sync causes Dataverse API throttling | See [Dataverse API Throttling runbook](./dataverse-api-throttling.md) |
| Executives are making decisions on stale data | IT Service Manager (communicate data freshness) |

## Prevention

1. **Canary test monitoring**: A lightweight health-check function that queries `SyncState.LastSyncTime` every 5 minutes and fires an alert if it is more than 15 minutes old — well before the 30-minute threshold.
2. **Sync duration alerts**: Track p95 sync duration in Application Insights. Alert if it exceeds 80% of the timer interval (e.g., sync takes 4+ minutes on a 5-minute timer).
3. **SyncState table health check**: A daily automated check that verifies all expected tables have recent sync tokens and no error messages.
4. **Database capacity alerts**: Azure SQL alert when database utilization exceeds 80% of the tier limit.
5. **Change tracking validation**: After every managed solution import, verify that change tracking is still enabled on all synced tables.

## Related Alerts

| Alert Name | Condition | Severity |
|---|---|---|
| `sync-overdue` | No successful DataverseSyncToSQL run in 30 minutes | Warning |
| `sync-failed` | DataverseSyncToSQL execution failed | Critical |
| `sync-duration-high` | Sync execution time > 4 minutes | Warning |
| `sql-storage-80pct` | Azure SQL storage utilization > 80% | Warning |
| `powerbi-stale-data` | Power BI dataset refresh failed | Warning |
