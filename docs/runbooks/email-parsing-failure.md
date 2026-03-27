# Runbook: Email-to-Ticket Parsing Failure

## Severity: P2

## Detection

- **Alert**: Application Insights fires `email-backlog-growing` when the shared mailbox unread count exceeds 20 (checked every 5 minutes via a canary function).
- **User Report**: End users report that they emailed helpdesk@contoso.com but no ticket was created and no confirmation was received.
- **Monitoring**: Power Automate flow run history shows consecutive failures on the email trigger flow, or the `EmailToTicket` Azure Function logs show parsing exceptions.

## Impact

- Incoming help requests via email are not being converted to tickets. The shared mailbox accumulates unread messages.
- No ticket means no SLA clock starts — impacted users receive no acknowledgment and no resolution timeline.
- If the backlog grows large enough, manual processing becomes a multi-hour effort.
- Tickets submitted through other channels (Power Apps, Teams bot) are unaffected.

## Diagnosis Steps

1. Check the Power Automate flow run history. Open Power Automate → My flows → "Email to Ticket – Trigger" (or the equivalent flow). Look for:
   - **Failed runs**: Note the error message and the specific action that failed.
   - **Suspended flow**: Power Automate suspends flows after repeated failures (typically 5 consecutive failures over 2 weeks). A suspended flow shows a banner at the top of the flow detail page.

2. If the flow is running but tickets are not created, check the `EmailToTicket` Azure Function logs:

   ```kusto
   traces
   | where timestamp > ago(2h)
   | where cloud_RoleName == "helpdesk-functions"
   | where operation_Name == "EmailToTicket"
   | where severityLevel >= 2
   | order by timestamp desc
   | take 50
   ```

3. Check shared mailbox access permissions. The flow (or function) connects to `helpdesk@contoso.com` using either a service account connection or an application permission. Verify:
   - The connection in Power Automate is not expired (Connections → verify status = Connected).
   - If using Graph API: the `Mail.Read` and `Mail.ReadWrite` application permissions are still granted.
   - The shared mailbox has not been disabled in Exchange admin center.

4. Inspect a failing email. Forward one of the unprocessed emails to yourself and examine:
   - Encoding (UTF-8, ISO-8859-1, or unusual encodings from external senders).
   - Format (HTML with nested tables, plain text, S/MIME signed, encrypted).
   - Attachments (oversized, unusual MIME types).
   - Empty subject or body.

5. Check if a recent email format change is causing parse failures. External ticketing systems, automated alerts, or new email clients may produce HTML structures the parser does not expect.

6. Verify the Dataverse connection from the function. If the `EmailToTicket` function creates the ticket directly in Dataverse, check that the S2S app registration credentials have not expired:

   ```bash
   az ad app credential list --id <app-registration-id> --query "[].{endDateTime:endDateTime}" -o table
   ```

## Resolution Steps

1. **If the Power Automate flow is suspended**: Open the flow → click "Turn on." Flows that were suspended due to repeated failures will resume from the next trigger, not re-process missed emails. Missed emails must be handled manually (step 5).

2. **If the flow connection is expired**: Open Power Automate → Connections → find the Office 365 Outlook connection → Re-authenticate. Then test the flow with a manual trigger.

3. **If the function is failing on specific email formats**: Identify the pattern in the failing emails and update the parsing logic in the `EmailToTicket` function. Common fixes:
   - Add encoding detection for non-UTF-8 emails.
   - Handle empty subject lines by defaulting to "No Subject - Email Ticket."
   - Strip S/MIME signatures before parsing body content.
   - Increase the body size limit if large emails are being rejected.

4. **If Dataverse S2S credentials have expired**: Generate a new client secret or certificate and update the Function App settings:

   ```bash
   az functionapp config appsettings set \
     --name helpdesk-functions \
     --resource-group helpdesk-rg \
     --settings "DATAVERSE_CLIENT_SECRET=<new-secret>"
   ```

   Prefer storing the secret in Key Vault and referencing it via `@Microsoft.KeyVault(SecretUri=...)`.

5. **Manually process the email backlog**: After the root cause is fixed, trigger reprocessing of accumulated emails. If the flow supports manual replay:
   - Open each failed flow run → click "Resubmit."
   - For large backlogs (50+ emails), use a PowerShell script to forward each unread email to a reprocessing alias, or invoke the `EmailToTicket` function directly via HTTP with the email content as the payload.

6. **Clear stuck flow runs**: If flow runs are in a "Running" state for more than 30 minutes, they are stuck. Cancel them from the flow run history, then re-trigger.

7. **Verify recovery**: Send a test email to helpdesk@contoso.com and confirm that a ticket is created within 5 minutes, the SLA clock starts, and the confirmation email is sent to the submitter.

## Escalation Path

| Condition | Escalate To |
|---|---|
| Flow cannot be re-enabled (platform error) | Microsoft Support (Power Automate) |
| Shared mailbox access revoked by Exchange admin | Exchange Administrator |
| Email backlog exceeds 100 messages | IT Service Manager (assign manual triage team) |
| Parsing failures require code changes to the Azure Function | Development Team Lead |
| S2S credentials expired and Key Vault access is needed | Security Team / Key Vault Administrator |

## Prevention

1. **Email format validation**: Maintain a test suite of known email formats (Outlook, Gmail, Apple Mail, automated alerts, S/MIME signed) and run parsing tests against them on every function deployment.
2. **Mailbox unread count monitoring**: The canary function checks unread count every 5 minutes. Alert at 10 (warning), 20 (critical). A healthy system should have 0 unread messages.
3. **Flow failure alerts**: Configure Power Automate to send an email to the platform team distribution list on any flow run failure.
4. **Credential expiry tracking**: Set a calendar reminder 30 days before S2S client secret or certificate expiry. Use Azure Key Vault certificate auto-rotation where possible.
5. **Connection health checks**: Weekly automated check that all Power Automate connections are in "Connected" status.

## Related Alerts

| Alert Name | Condition | Severity |
|---|---|---|
| `email-backlog-growing` | Shared mailbox unread count > 20 | Critical |
| `email-backlog-warning` | Shared mailbox unread count > 10 | Warning |
| `emailtoticket-function-failed` | EmailToTicket function execution failed | Critical |
| `flow-email-trigger-failed` | Email trigger flow run failed | Warning |
| `s2s-credential-expiry-30d` | S2S app registration credential expires within 30 days | Warning |
