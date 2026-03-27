# Runbook: Dataverse API Throttling (429 Responses)

## Severity: P2

## Detection

- **Alert**: Application Insights fires `dataverse-429-spike` when 429 response count exceeds 50 in a 5-minute window.
- **User Report**: Agents report the model-driven app is slow, saves are failing, or the canvas self-service app shows "Something went wrong."
- **Monitoring**: Azure Functions logs show `HttpRequestException` with status 429 and `Retry-After` headers.

## Impact

- Agents cannot create, update, or resolve tickets in the model-driven app.
- Self-service portal returns errors on ticket submission.
- Power Automate flows (routing, SLA escalation) queue up and execute late, causing SLA clock drift.
- Email-to-ticket processing stalls — incoming helpdesk emails accumulate in the shared mailbox.
- SPFx web parts show loading spinners or stale data.

## Diagnosis Steps

1. Open Application Insights → Logs. Run the following query to identify the throttling pattern:

   ```kusto
   requests
   | where timestamp > ago(30m)
   | where resultCode == "429"
   | summarize count() by bin(timestamp, 1m), cloud_RoleName, operation_Name
   | order by timestamp desc
   ```

2. Identify which caller is consuming the most quota. Dataverse enforces these limits:
   - **Interactive users**: 6,000 API requests per user per 5-minute sliding window.
   - **Service-to-service (S2S)**: 40,000 API requests per 5-minute sliding window (for the Azure Functions app registration).
   - **Organization aggregate**: varies by tenant license tier.

3. Check the Dataverse admin center → Analytics → API call statistics to see whether throttling is user-level, S2S-level, or org-level.

4. In Application Insights, look for a sudden spike in a specific function or flow:

   ```kusto
   requests
   | where timestamp > ago(1h)
   | summarize total = count(), throttled = countif(resultCode == "429") by operation_Name
   | where throttled > 0
   | order by throttled desc
   ```

5. Check for runaway timer-triggered functions. Open Azure Portal → Function App → Monitor and look for functions executing more frequently than expected (e.g., `DataverseSyncToSQL` running every 30 seconds instead of every 5 minutes).

6. Check Power Automate flow run history for loops that may be generating excessive Dataverse calls (e.g., an Apply to Each over thousands of records without pagination).

## Resolution Steps

1. **If a runaway Azure Function is the cause**: Disable the specific function in the Azure Portal (Function App → Functions → select function → Disable). This stops the bleed immediately without affecting other functions.

2. **If a Power Automate flow is the cause**: Turn off the flow in the Power Platform admin center. Identify the loop or trigger that is generating excessive calls.

3. **Reduce batch sizes**: If the sync function is processing too many records per execution, reduce the `SYNC_BATCH_SIZE` application setting:

   ```bash
   az functionapp config appsettings set \
     --name helpdesk-functions \
     --resource-group helpdesk-rg \
     --settings "SYNC_BATCH_SIZE=200"
   ```

4. **Implement exponential backoff**: If the calling code does not already respect `Retry-After` headers, this is a code fix. The Dataverse SDK handles this automatically; raw HTTP calls must check for the header:

   ```csharp
   if (response.StatusCode == (HttpStatusCode)429)
   {
       var retryAfter = response.Headers.RetryAfter.Delta ?? TimeSpan.FromSeconds(30);
       await Task.Delay(retryAfter);
       // Retry the request
   }
   ```

5. **If org-level quota is exceeded**: This indicates the entire tenant is at capacity. Contact Microsoft Support to request a temporary quota increase. Provide the org ID, the time window of the incident, and the business justification.

6. **Verify recovery**: After the offending caller is stopped or throttled, wait 5 minutes for the sliding window to reset. Confirm 429 counts return to zero:

   ```kusto
   requests
   | where timestamp > ago(10m)
   | where resultCode == "429"
   | summarize count() by bin(timestamp, 1m)
   ```

## Escalation Path

| Condition | Escalate To |
|---|---|
| 429s persist after disabling the identified caller | Platform Team Lead |
| Org-level quota exceeded (not a single caller) | Microsoft Support (Premier/Unified) |
| SLA escalation flows are more than 30 minutes behind | IT Service Manager (manual SLA adjustments may be needed) |
| Incident lasts more than 1 hour | Incident Commander per P2 process |

## Prevention

1. **Quota monitoring alerts**: Configure Application Insights alerts to fire at 50% of the 5-minute quota (3,000 for interactive, 20,000 for S2S) so the team can act before hard throttling begins.
2. **Request batching in code**: Use `ExecuteMultipleRequest` in the Dataverse SDK to batch up to 1,000 operations in a single API call. The sync function should batch all SQL-sourced updates.
3. **Stagger timer-triggered functions**: Ensure timer triggers are offset (e.g., sync at :00, user sync at :02, cleanup at :04) rather than all firing simultaneously.
4. **Pagination limits**: All Power Automate flows that iterate over Dataverse records must use `Top Count` to cap the result set and paginate explicitly.
5. **Load testing**: Before deploying new flows or functions that call Dataverse, estimate the API call count per execution and compare against quota headroom.

## Related Alerts

| Alert Name | Condition | Severity |
|---|---|---|
| `dataverse-429-spike` | 429 count > 50 in 5 minutes | Warning |
| `dataverse-429-critical` | 429 count > 200 in 5 minutes | Critical |
| `function-execution-spike` | Any function invocation count > 2x baseline in 5 minutes | Warning |
| `flow-run-backlog` | Power Automate flow run queue depth > 100 | Warning |
