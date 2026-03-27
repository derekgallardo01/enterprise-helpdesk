# Power Automate Flows -- Enterprise Help Desk

This document defines all six cloud flows included in the HelpDesk solution. Each flow runs in the context of the HelpDesk service account and uses the Dataverse connector with the `hd_` publisher prefix.

---

## 1. Ticket Routing

| Property | Value |
|---|---|
| **Flow Name** | HD - Ticket Routing |
| **Type** | Automated cloud flow |
| **Trigger** | Dataverse -- When a row is added (table: `hd_ticket`) |
| **Owner** | HelpDesk Service Account |
| **Solution** | HelpDesk 1.0.0.0 |

### Description

Automatically assigns a newly created ticket to the correct support team and sets the SLA due date based on the ticket's category and subcategory.

### Step-by-Step Logic

1. **Trigger: When a row is added** -- Fires when a new `hd_ticket` row is created. Selects columns: `hd_ticketid`, `hd_category`, `hd_subcategory`, `hd_priority`.

2. **Get Category** -- Dataverse: Get a row by ID from `hd_category` using the trigger's `hd_category` lookup value. Select columns: `hd_name`, `hd_defaultteam`.

3. **Condition: Subcategory provided?** -- Check whether `hd_subcategory` is not null.
   - **Yes branch:**
     1. **Get Subcategory** -- Dataverse: Get a row by ID from `hd_subcategory`. Select columns: `hd_name`, `hd_slaprofile`.
     2. **Get SLA Profile** -- Dataverse: Get a row by ID from `hd_slaprofile` using the subcategory's `hd_slaprofile` lookup. Select columns: `hd_firstresponseminutes`, `hd_resolutionminutes`, `hd_businesshoursonly`.
     3. **Calculate Due Date** -- Compose: `addMinutes(utcNow(), outputs('Get_SLA_Profile')?['hd_resolutionminutes'])`.
     4. **Update Ticket with SLA** -- Dataverse: Update row on `hd_ticket`:
        - `hd_assignedteam` = Category's `hd_defaultteam`
        - `hd_status` = 2 (Assigned)
        - `hd_duedate` = Calculated due date
   - **No branch:**
     1. **Use Default SLA** -- Dataverse: List rows from `hd_slaprofile` where `hd_name eq 'Default'`. Take first result.
     2. **Calculate Default Due Date** -- Compose: `addMinutes(utcNow(), first(outputs('Use_Default_SLA')?['value'])?['hd_resolutionminutes'])`.
     3. **Update Ticket with Default SLA** -- Dataverse: Update row on `hd_ticket`:
        - `hd_assignedteam` = Category's `hd_defaultteam`
        - `hd_status` = 2 (Assigned)
        - `hd_duedate` = Default due date

### Error Handling

- **Scope: Try** wraps all steps after the trigger.
- **Scope: Catch** (configured to run after Try -- has failed/timed-out):
  1. Log error details to a "HD - Flow Errors" SharePoint list (FlowName, ErrorMessage, TicketId, Timestamp).
  2. Send email to `helpdesk-admins@contoso.com` with the error details.
  3. Add an internal comment to the ticket: "Automatic routing failed. Manual assignment required."

### Input/Output Variables

| Variable | Direction | Type | Description |
|---|---|---|---|
| `varDueDate` | Internal | DateTime | Calculated SLA due date |
| `varSLAMinutes` | Internal | Integer | Resolution minutes from SLA profile |

---

## 2. SLA Escalation

| Property | Value |
|---|---|
| **Flow Name** | HD - SLA Escalation |
| **Type** | Scheduled cloud flow |
| **Trigger** | Recurrence -- Every 15 minutes |
| **Owner** | HelpDesk Service Account |

### Description

Checks for tickets that have breached their SLA due date. Flags them and sends notifications to the assigned team and management.

### Step-by-Step Logic

1. **Trigger: Recurrence** -- Every 15 minutes, no end date.

2. **List Breached Tickets** -- Dataverse: List rows from `hd_ticket` with filter:
   ```
   hd_duedate lt @{utcNow()}
   and hd_slabreach eq false
   and Microsoft.Dynamics.CRM.ContainValues(PropertyName='hd_status',PropertyValues=['1','2','3','4','5'])
   ```
   Select columns: `hd_ticketid`, `hd_ticketnumber`, `hd_title`, `hd_assignedto`, `hd_assignedteam`, `hd_duedate`, `hd_priority`.

3. **Apply to each** -- Iterate over breached tickets:
   1. **Flag SLA Breach** -- Dataverse: Update row on `hd_ticket`:
      - `hd_slabreach` = true
   2. **Add Internal Comment** -- Dataverse: Add a row to `hd_ticketcomment`:
      - `hd_ticket` = current ticket ID
      - `hd_commentbody` = "SLA BREACH: This ticket has exceeded its due date of {hd_duedate}. Escalation triggered."
      - `hd_commenttype` = 2 (Internal)
   3. **Condition: Priority is Critical or High?**
      - **Yes:** Post adaptive card to Teams channel "IT Support - Escalations" with ticket details and a direct link.
      - **No:** Send email notification to the assigned agent with ticket details.

### Error Handling

- **Configure run after** on Apply-to-each: continue on item failure so one bad ticket does not block others.
- Final **Condition: any failures?** -- if `length(body('Filter_Failed'))` > 0, send summary email to admins.

### Input/Output Variables

| Variable | Direction | Type | Description |
|---|---|---|---|
| `varBreachedCount` | Internal | Integer | Count of newly breached tickets for logging |

---

## 3. Ticket Assigned Notification

| Property | Value |
|---|---|
| **Flow Name** | HD - Ticket Assigned Notification |
| **Type** | Automated cloud flow |
| **Trigger** | Dataverse -- When a row is modified (table: `hd_ticket`, filter on `hd_assignedto`) |

### Description

Sends a Teams adaptive card to the newly assigned agent when a ticket is assigned or reassigned.

### Step-by-Step Logic

1. **Trigger: When a row is modified** -- Column filter: `hd_assignedto`. Select columns: `hd_ticketid`, `hd_ticketnumber`, `hd_title`, `hd_priority`, `hd_status`, `hd_assignedto`, `hd_category`, `hd_description`.

2. **Condition: AssignedTo is not null** -- Skip if the agent was unassigned (field cleared).
   - **Yes branch:**
     1. **Get Assigned User** -- Office 365 Users: Get user profile (V2) using `hd_assignedto` lookup value.
     2. **Get Category Name** -- Dataverse: Get a row by ID from `hd_category`. Select: `hd_name`.
     3. **Map Priority Label** -- Switch on `hd_priority`:
        - 1 = "Critical", 2 = "High", 3 = "Medium", 4 = "Low"
     4. **Post Adaptive Card to Teams** -- Microsoft Teams: Post adaptive card in a chat with the assigned user.
        Card content:
        - Header: "New Ticket Assigned to You"
        - Ticket number, title, category, priority (with color indicator)
        - Truncated description (first 200 characters)
        - Action button: "Open Ticket" linking to model-driven app deep link
        - Action button: "Acknowledge" that triggers a secondary flow to set status = In Progress

### Error Handling

- Scope with catch block. On failure, fall back to a plain-text Teams chat message (lower risk of formatting failures).

### Input/Output Variables

| Variable | Direction | Type | Description |
|---|---|---|---|
| `varPriorityLabel` | Internal | String | Human-readable priority |
| `varDeepLink` | Internal | String | Model-driven app URL for the ticket |

---

## 4. Status Changed Notification

| Property | Value |
|---|---|
| **Flow Name** | HD - Status Changed Notification |
| **Type** | Automated cloud flow |
| **Trigger** | Dataverse -- When a row is modified (table: `hd_ticket`, filter on `hd_status`) |

### Description

Notifies the ticket requester via Teams message whenever the ticket status changes.

### Step-by-Step Logic

1. **Trigger: When a row is modified** -- Column filter: `hd_status`. Select columns: `hd_ticketid`, `hd_ticketnumber`, `hd_title`, `hd_status`, `hd_requestedby`, `hd_resolutionnotes`.

2. **Get Requester** -- Office 365 Users: Get user profile (V2) using `hd_requestedby`.

3. **Map Status Label** -- Switch on `hd_status`:
   - 1 = "New", 2 = "Assigned", 3 = "In Progress", 4 = "Waiting on You", 5 = "Waiting on Third Party", 6 = "Resolved", 7 = "Closed", 8 = "Cancelled"

4. **Post Teams Chat Message** -- Microsoft Teams: Post message in a chat with the requester.
   Message:
   ```
   Your ticket **{hd_ticketnumber}** — "{hd_title}" has been updated to **{varStatusLabel}**.
   ```

5. **Condition: Status = Resolved (6)?**
   - **Yes:**
     1. Append resolution notes to the message.
     2. **Send Satisfaction Survey Link** -- Post a second Teams message with an adaptive card containing a 1-5 star rating selector and a "Submit" action that calls a child flow to write `hd_satisfactionrating`.

### Error Handling

- Scope-based try/catch. On failure, send fallback email via Outlook connector to the requester's email address.

### Input/Output Variables

| Variable | Direction | Type | Description |
|---|---|---|---|
| `varStatusLabel` | Internal | String | Human-readable status name |
| `varRequesterEmail` | Internal | String | Requester email for fallback |

---

## 5. Comment Added Notification

| Property | Value |
|---|---|
| **Flow Name** | HD - Comment Added Notification |
| **Type** | Automated cloud flow |
| **Trigger** | Dataverse -- When a row is added (table: `hd_ticketcomment`) |

### Description

Sends an email to the ticket requester when a new public comment is added to their ticket.

### Step-by-Step Logic

1. **Trigger: When a row is added** -- Table: `hd_ticketcomment`. Select columns: `hd_ticketcommentid`, `hd_ticket`, `hd_commentbody`, `hd_commenttype`, `createdby`.

2. **Condition: Is Public Comment?** -- Check `hd_commenttype eq 1`.
   - **No:** Terminate (do not notify on internal comments).
   - **Yes:** Continue.

3. **Get Parent Ticket** -- Dataverse: Get a row by ID from `hd_ticket` using `hd_ticket` lookup. Select: `hd_ticketnumber`, `hd_title`, `hd_requestedby`.

4. **Get Requester** -- Office 365 Users: Get user profile (V2) using `hd_requestedby`.

5. **Get Comment Author** -- Office 365 Users: Get user profile (V2) using `createdby`.

6. **Condition: Author is not the Requester?** -- Skip notification if the requester commented on their own ticket.
   - **Yes:**
     1. **Send Email** -- Office 365 Outlook: Send an email (V2).
        - To: Requester email
        - Subject: `[{hd_ticketnumber}] New comment on: {hd_title}`
        - Body: HTML template with comment body, author display name, timestamp, and "View Ticket" link.

### Error Handling

- Scope-based try/catch. On failure, log to SharePoint error list. Do not retry (email is non-critical).

### Input/Output Variables

| Variable | Direction | Type | Description |
|---|---|---|---|
| `varIsPublic` | Internal | Boolean | Whether the comment is public |

---

## 6. Stamp Resolution Date

| Property | Value |
|---|---|
| **Flow Name** | HD - Stamp Resolution Date |
| **Type** | Automated cloud flow |
| **Trigger** | Dataverse -- When a row is modified (table: `hd_ticket`, filter on `hd_status`) |

### Description

When a ticket's status changes to Resolved (6), stamps the `hd_resolutiondate` field with the current UTC timestamp. This is implemented as a flow rather than a business rule because business rules cannot reliably set `utcNow()`.

### Step-by-Step Logic

1. **Trigger: When a row is modified** -- Column filter: `hd_status`. Select columns: `hd_ticketid`, `hd_status`, `hd_resolutiondate`.

2. **Condition: Status = 6 (Resolved)?**
   - **No:** Terminate (success, no action needed).
   - **Yes:**
     1. **Condition: Resolution date already set?** -- Prevents overwriting if the ticket was re-resolved.
        - **Yes:** Terminate (success, keep original date).
        - **No:**
          1. **Update Ticket** -- Dataverse: Update row on `hd_ticket`:
             - `hd_resolutiondate` = `utcNow()`

3. **Condition: First Response not stamped?** -- Check if `hd_firstresponseat` is null.
   - **Yes:** Also stamp `hd_firstresponseat` = `utcNow()` (edge case where agent resolves immediately without prior comment).

### Error Handling

- Scope-based try/catch. On failure, add internal comment: "Failed to stamp resolution date. Manual update required." and notify admins.

### Input/Output Variables

| Variable | Direction | Type | Description |
|---|---|---|---|
| `varNow` | Internal | DateTime | Captured `utcNow()` to ensure consistent timestamp across updates |

---

## Shared Configuration

### Environment Variables (defined in HelpDesk solution)

| Variable | Type | Default | Description |
|---|---|---|---|
| `hd_AdminEmail` | String | helpdesk-admins@contoso.com | Error notification recipients |
| `hd_TeamsEscalationChannelId` | String | (set per environment) | Teams channel for SLA escalation posts |
| `hd_ModelDrivenAppUrl` | String | (set per environment) | Base URL for deep links into the model-driven app |
| `hd_ErrorLogListUrl` | String | (set per environment) | SharePoint list URL for flow error logging |

### Connection References

| Name | Connector | Description |
|---|---|---|
| `hd_DataverseConnection` | Microsoft Dataverse | Read/write tickets, comments, categories |
| `hd_Office365UsersConnection` | Office 365 Users | Resolve user profile details |
| `hd_OutlookConnection` | Office 365 Outlook | Send email notifications |
| `hd_TeamsConnection` | Microsoft Teams | Post adaptive cards and chat messages |
| `hd_SharePointConnection` | SharePoint | Write to error logging list |
