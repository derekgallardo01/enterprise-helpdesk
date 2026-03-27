# Enterprise Help Desk — GDPR & Data Protection Compliance

## Overview

This document defines how the Enterprise Help Desk system complies with the EU General Data Protection Regulation (GDPR) and related data protection requirements. It covers the full lifecycle of personal data — from collection through processing, storage, and eventual deletion — across all three data stores (Dataverse, Azure SQL, SharePoint) and supporting services (Azure Functions, Application Insights).

**Scope**: All personal data processed by the Help Desk system, including data about ticket requesters, IT agents, managers, and any PII incidentally captured in ticket content.

## 1. Data Protection Principles (GDPR Article 5)

| Principle | Article | How the System Complies |
|---|---|---|
| **Lawfulness, fairness, transparency** | 5(1)(a) | All data processing is grounded in legitimate interest (IT service delivery) or contractual necessity (employment). Privacy notice displayed on the self-service portal and canvas app. |
| **Purpose limitation** | 5(1)(b) | Data collected for IT service management is used only for ticket resolution, SLA tracking, and operational reporting. No secondary marketing or profiling use. |
| **Data minimization** | 5(1)(c) | Only the minimum fields required for ticket routing and resolution are collected. No unnecessary demographic data. Ticket forms enforce required-only fields. |
| **Accuracy** | 5(1)(d) | User identity is sourced from Entra ID (the authoritative directory). No manual name/email entry — lookups auto-populate from `systemuser`. Stale accounts are disabled upstream in Entra ID. |
| **Storage limitation** | 5(1)(e) | Retention policies enforce automatic anonymization of closed tickets after 2 years. Application Insights auto-purges after 90 days. See Section 5 for full retention schedule. |
| **Integrity and confidentiality** | 5(1)(f) | Dataverse row-level security, column-level security on internal comments, managed identity for Azure SQL (no passwords), Key Vault for secrets, TLS 1.2+ everywhere. See [security-model.md](security-model.md). |
| **Accountability** | 5(2) | Dataverse field-level audit logging enabled on all custom tables. Azure audit logs centralized in Log Analytics. This document, the DSAR procedure, and retention automation constitute the accountability record. |

## 2. Complete Data Map

Every location where personal data resides in the system:

| Data Element | Store | Table / Location | Retention | Legal Basis | Controller |
|---|---|---|---|---|---|
| User name / email | Dataverse | `hd_Ticket.hd_requestedby` | Active + 2 years | Legitimate interest | Organization |
| User name / email | Dataverse | `hd_TicketComment.createdby` | Active + 2 years | Legitimate interest | Organization |
| User name / email | Dataverse | `hd_Ticket.hd_assignedto` | Active + 2 years | Legitimate interest | Organization |
| User name / email | Dataverse | `hd_Asset.hd_assignedto` | Active employment | Contract | Organization |
| User name / email | Azure SQL | `TicketFact.RequestedByEmail` | Active + 3 years | Legitimate interest | Organization |
| User name / email | Azure SQL | `AgentDim.Email` | Active employment | Legitimate interest | Organization |
| User department | Dataverse | `systemuser.department` | Active employment | Contract | Organization |
| User department | Azure SQL | `DepartmentDim` | Indefinite (aggregated) | Legitimate interest | Organization |
| Ticket content (may contain PII) | Dataverse | `hd_Ticket.hd_description` | Active + 2 years | Legitimate interest | Organization |
| Ticket content (may contain PII) | Dataverse | `hd_Ticket.hd_resolutionnotes` | Active + 2 years | Legitimate interest | Organization |
| Comment content (may contain PII) | Dataverse | `hd_TicketComment.hd_commentbody` | Active + 2 years | Legitimate interest | Organization |
| KB article content | SharePoint | KB site pages | Published lifetime | Legitimate interest | Organization |
| Email content | Azure Functions | Application Insights logs | 90 days | Legitimate interest | Organization |
| User IP addresses | Application Insights | Request telemetry | 90 days | Legitimate interest | Organization |
| Manager chain | Dataverse | `hd_Department.hd_manager` | Active employment | Contract | Organization |
| Satisfaction ratings | Dataverse | `hd_Ticket.hd_satisfactionrating` | Active + 2 years | Legitimate interest | Organization |
| Audit trail (who changed what) | Dataverse | Audit log tables | 7 years | Legal obligation | Organization |

**Data flows across stores**:

```
User submits ticket (Dataverse)
        |
        v
Power Automate routes ticket (reads user profile via Graph)
        |
        v
Azure Function syncs to SQL (delta every 15 min)
        |
        v
Power BI reads from SQL (DirectQuery)
        |
Agent comments logged in Dataverse
        |
Email notifications via Power Automate (transient, not stored beyond App Insights)
```

## 3. Data Subject Access Request (DSAR) Procedure

### Step 1: Request Intake

- **Channels**: Dedicated email address (`privacy@contoso.com`) or internal DSAR form on the SharePoint intranet.
- **Logging**: Every DSAR is logged as a ticket in Dataverse with `hd_category = Access & Permissions` and a dedicated subcategory `DSAR Request`. This ensures tracking and SLA enforcement.
- **Acknowledgment**: Automated email sent within 24 hours confirming receipt and providing a reference number.

### Step 2: Identity Verification

1. Confirm the requestor's identity via Entra ID — match the request email to a valid `systemuser` record.
2. If the request comes from an external email, require government-issued ID or secondary verification before proceeding.
3. Log the verification method and date in the DSAR ticket.

### Step 3: Data Discovery Across All Stores

Execute the following queries to compile all personal data for the subject:

**Dataverse**:
```
FetchXML query: All hd_Ticket rows where hd_requestedby = {userId}
FetchXML query: All hd_TicketComment rows on the above tickets
FetchXML query: All hd_Asset rows where hd_assignedto = {userId}
FetchXML query: Audit log entries for the above records
```

**Azure SQL**:
```sql
SELECT * FROM dbo.TicketFact WHERE RequestedById = '{userId}';
SELECT * FROM dbo.AgentDim WHERE AgentId = '{userId}';
```

**SharePoint**:
```
Microsoft Search query: author:{userEmail} site:{kbSiteUrl}
SharePoint audit log export for the user
```

**Application Insights**:
```kusto
requests
| where timestamp > ago(90d)
| where user_Id == "{userId}" or client_IP == "{knownIP}"
| project timestamp, name, url, client_IP, duration
```

### Step 4: Data Compilation

1. Export all discovered data into a portable format:
   - **Dataverse records**: JSON export via Web API (`$select` only relevant columns)
   - **Azure SQL records**: CSV export
   - **SharePoint content**: PDF export of authored pages
   - **Application Insights**: CSV export of query results
2. Package all exports into a single ZIP file.
3. Review the package for any third-party PII that should be excluded (other users' names in ticket comments).
4. Redact third-party PII before delivery.

### Step 5: Response Timeline

| Milestone | Deadline | GDPR Article |
|---|---|---|
| Acknowledge receipt | 24 hours | Best practice |
| Complete data discovery | 14 days | Internal SLA |
| Deliver response to data subject | 30 calendar days | Article 12(3) |
| Extension (complex requests) | +60 days (90 total) | Article 12(3), with written justification |

### Step 6: Template Response Letter

```
Subject: Data Subject Access Request — Reference [DSAR-XXXXXX]

Dear [Name],

In response to your data subject access request received on [date], we have
compiled all personal data held about you within our IT Help Desk system.

The attached archive contains:
- All IT support tickets you have submitted ([count] tickets)
- All comments you have authored on those tickets
- IT assets assigned to you ([count] assets)
- Your user profile data as held in our directory
- Application telemetry associated with your account (last 90 days)

Data stores searched: Microsoft Dataverse, Azure SQL, SharePoint Online,
Azure Application Insights.

If you believe any data is missing or inaccurate, or if you wish to exercise
your right to rectification or erasure, please reply to this email.

Regards,
[Data Protection Officer / Privacy Team]
```

## 4. Right to Erasure (Right to be Forgotten)

### Step 1: Determine Eligibility

Not all erasure requests must be honored. Evaluate against GDPR Article 17(3) exceptions:

| Scenario | Erasure Required? | Justification |
|---|---|---|
| Former employee, no legal hold | Yes | No overriding legitimate interest |
| Current employee | No | Active contractual relationship |
| Tickets under legal hold / litigation | No | Article 17(3)(e) — legal claims |
| Tickets required for regulatory audit | No | Article 17(3)(b) — legal obligation |
| Anonymized data (no PII) | N/A | Already not personal data |

Document the determination in the DSAR ticket with the legal basis for approval or refusal.

### Step 2: Anonymization Procedure

**Why anonymize, not delete**: Deleting tickets would break SLA compliance data, trend analysis, and agent performance metrics. Anonymization preserves the statistical record while removing PII. See [security-model.md](security-model.md) for the existing precedent.

#### Dataverse

1. Query all `hd_Ticket` rows where `hd_requestedby = {userId}`.
2. Replace PII fields with `[REDACTED]`:
   - `hd_title` → `[REDACTED]`
   - `hd_description` → `[REDACTED]`
   - `hd_resolutionnotes` → `[REDACTED]`
3. Clear the `hd_requestedby` lookup (set to null) or point to a system "Anonymized User" record.
4. Query all `hd_TicketComment` rows on those tickets where `createdby = {userId}`.
5. Replace `hd_commentbody` with `[REDACTED]`.
6. Query all `hd_Asset` rows where `hd_assignedto = {userId}` and clear the assignment.

#### Azure SQL

1. Update `TicketFact` rows:
   ```sql
   UPDATE dbo.TicketFact
   SET Title = '[REDACTED]',
       RequestedById = '00000000-0000-0000-0000-000000000000'
   WHERE RequestedById = '{userId}';
   ```
2. Update or remove the user from `AgentDim` (if the user was an agent):
   ```sql
   UPDATE dbo.AgentDim
   SET DisplayName = '[REDACTED]',
       Email = '[REDACTED]'
   WHERE AgentId = '{userId}';
   ```
3. Re-aggregate any affected reporting periods to ensure dashboards reflect anonymized data.

#### SharePoint

1. Search for KB articles authored by or attributing the user.
2. Remove user-attributable content (author bylines, contributor mentions).
3. SharePoint version history retains author metadata — submit a support request to Microsoft for purge if required by the erasure scope.

#### Application Insights

1. Use the Application Insights Data Purge API:
   ```
   POST https://management.azure.com/subscriptions/{subId}/resourceGroups/{rg}/providers/microsoft.insights/components/{appInsightsName}/purge
   Body: {
     "table": "requests",
     "filters": [
       { "column": "user_Id", "operator": "==", "value": "{userId}" }
     ]
   }
   ```
2. Note: Purge is only available on workspace-based Application Insights instances. Purge operations take up to 30 days to complete.

### Step 3: Verification

1. Re-run all data discovery queries from the DSAR procedure (Section 3, Step 3).
2. Confirm that no PII for the subject is returned from any store.
3. Document the verification results in the DSAR ticket.

### Step 4: Audit Log Entry

1. Record the erasure action in the DSAR ticket:
   - Date of erasure
   - Stores affected
   - Number of records anonymized
   - Verification result
   - Performed by (admin name)
2. This audit log entry itself does **not** contain the erased PII — only the action metadata.

## 5. Data Retention Policy

| Data Type | Active Retention | Archive | Purge | Mechanism |
|---|---|---|---|---|
| Open tickets | Indefinite | N/A | N/A | Remains active until resolved |
| Closed tickets | 2 years from closure | Years 2-7 (read-only, Dataverse) | After 7 years | Retention automation (Section 6) |
| Ticket comments | Same as parent ticket | Same as parent ticket | Same as parent ticket | Cascade with parent |
| Internal comments | 1 year after ticket closure | None | After 1 year | Retention automation |
| Audit logs (Dataverse) | 1 year hot storage | Years 1-7 (Azure Blob Storage) | After 7 years | Export + delete job |
| Application Insights | 90 days | None | Auto-purge at 90 days | Application Insights retention setting |
| SQL aggregations | Indefinite (anonymized) | N/A | N/A | No PII in aggregated data |
| SQL fact table (with PII) | Active + 3 years | None | Anonymize after 3 years | Retention automation |
| KB articles | Published lifetime | Archive after 3 years inactive | Manual review | Content owner responsibility |
| Email-to-ticket raw content | 90 days (App Insights) | None | Auto-purge | Application Insights retention |

### Retention States

```
Ticket Lifecycle:

  [Open / Active]  ──>  [Closed]  ──>  [Retained (2 years)]  ──>  [Archived (read-only)]  ──>  [Purged (7 years)]
                                               |
                                    PII anonymized at 2-year mark
                                    Statistical data preserved
```

## 6. Retention Automation

An Azure Function timer trigger runs weekly (Sunday 02:00 UTC) to enforce retention policy.

### Function: `RetentionEnforcement`

**Trigger**: Timer (`0 0 2 * * 0` — weekly on Sunday)

**Steps**:

1. **Identify expired tickets**:
   ```sql
   -- Tickets closed more than 2 years ago, not yet anonymized
   SELECT hd_ticketid, hd_requestedby
   FROM hd_Ticket
   WHERE hd_status IN (7, 8)  -- Closed or Cancelled
     AND modifiedon < DATEADD(YEAR, -2, GETUTCDATE())
     AND hd_title != '[REDACTED]'
   ```

2. **Anonymize PII in Dataverse** (per ticket):
   - Replace `hd_title`, `hd_description`, `hd_resolutionnotes` with `[REDACTED]`
   - Clear `hd_requestedby` lookup
   - Replace all child `hd_TicketComment.hd_commentbody` with `[REDACTED]`

3. **Update corresponding Azure SQL records**:
   ```sql
   UPDATE dbo.TicketFact
   SET Title = '[REDACTED]',
       RequestedById = '00000000-0000-0000-0000-000000000000'
   WHERE TicketId IN ({anonymizedTicketIds});
   ```

4. **Purge internal comments** (1-year policy):
   ```sql
   DELETE FROM hd_TicketComment
   WHERE hd_commenttype = 2  -- Internal
     AND hd_ticket IN (
       SELECT hd_ticketid FROM hd_Ticket
       WHERE hd_status IN (7, 8)
         AND modifiedon < DATEADD(YEAR, -1, GETUTCDATE())
     );
   ```

5. **Archive audit logs** older than 1 year:
   - Export Dataverse audit log entries to Azure Blob Storage (JSON format)
   - Blob path: `audit-archive/{year}/{month}/audit-{date}.json`
   - Delete exported entries from Dataverse audit log

6. **Generate retention report**:
   - Tickets anonymized this run: count
   - Internal comments purged: count
   - Audit log entries archived: count
   - Errors encountered: details
   - Report stored in Blob Storage and emailed to the Data Protection Officer

### Error Handling

- If any individual ticket anonymization fails, log the error and continue with the next ticket.
- If the Azure SQL update fails, queue the ticket IDs for retry on the next run.
- If the entire function fails, Application Insights alert triggers notification to the platform admin.

## 7. Data Processing Agreements

The following Data Processing Agreements (DPAs) are required for GDPR compliance:

| Processor | Services | DPA Status | Review Cadence |
|---|---|---|---|
| Microsoft (Azure) | Azure Functions, Azure SQL, Application Insights, Key Vault | Microsoft Online Services DPA (automatic with Enterprise Agreement) | Annual review |
| Microsoft (M365) | Dataverse, Power Platform, SharePoint, Teams, Entra ID | Microsoft Online Services DPA (automatic with Enterprise Agreement) | Annual review |
| Microsoft (Power BI) | Reporting and analytics | Covered under M365 DPA | Annual review |

**Key DPA provisions to verify**:

1. **Sub-processor transparency**: Microsoft publishes a sub-processor list; review for changes quarterly.
2. **Data residency**: Confirm Dataverse environment and Azure resources are in the same geographic region as the M365 tenant. No cross-border transfer without Standard Contractual Clauses (SCCs).
3. **Breach notification**: Microsoft commits to notifying customers of data breaches within 72 hours per GDPR Article 33.
4. **Audit rights**: Enterprise Agreement includes audit provisions for data processing compliance.
5. **Data return/deletion**: Upon contract termination, Microsoft provides data export and deletes within 180 days.

**No third-party processors**: The system architecture intentionally avoids non-Microsoft services. All data stays within the Microsoft cloud boundary, simplifying DPA management to a single processor relationship.

## 8. Privacy Impact Assessment

### Assessment Summary

| Processing Activity | Data Categories | Data Subjects | Risk Level | Mitigations |
|---|---|---|---|---|
| Ticket creation and management | Name, email, department, free-text descriptions | Employees (requesters) | **Medium** | Row-level security, 2-year retention, anonymization |
| Agent assignment and workload tracking | Name, email, team, performance metrics | IT staff (agents) | **Medium** | Business Unit security, aggregated reporting |
| SLA and performance reporting | Ticket metadata, resolution times, satisfaction scores | Employees, agents | **Low** | Anonymized after retention period, aggregated in SQL |
| Knowledge base authoring | Author name, content | IT staff (authors) | **Low** | Standard SharePoint permissions, no sensitive PII |
| Email-to-ticket parsing | Email sender, subject, body | Employees | **Medium** | 90-day retention in App Insights, no persistent email storage |
| Copilot Studio bot interaction | User identity, conversation content | Employees | **Medium** | Conversations processed by Microsoft, covered under M365 DPA |
| Application telemetry | IP address, user agent, request paths | All users | **Low** | 90-day auto-purge, no behavioral profiling |

### Risk: Free-Text PII in Ticket Descriptions

**Likelihood**: High — users routinely include phone numbers, employee IDs, or other PII in ticket descriptions.

**Impact**: Medium — PII in free text is harder to discover and anonymize than structured fields.

**Mitigations**:
1. Ticket submission form includes a privacy notice: "Do not include sensitive personal information (national ID numbers, financial data, health information) in ticket descriptions."
2. Retention automation anonymizes the entire `hd_description` field (replacing with `[REDACTED]`), which captures embedded PII regardless of format.
3. Agents are trained to move sensitive information to internal comments (shorter retention) rather than leaving it in the ticket description.

### Risk: Cross-Border Data Transfer

**Likelihood**: Low — architecture deploys all resources in the tenant's home region.

**Impact**: High — non-compliant transfer would violate GDPR Chapter V.

**Mitigations**:
1. Dataverse environment provisioned in the tenant's geographic region.
2. Azure resources deployed to the same region via ARM templates with location constraints.
3. No third-party integrations that could route data outside the region.
4. Conditional Access policies restrict sign-in locations (see [security-model.md](security-model.md)).

### Risk: Inadequate Erasure Across Distributed Stores

**Likelihood**: Medium — three data stores plus Application Insights means erasure must touch four systems.

**Impact**: High — incomplete erasure violates GDPR Article 17.

**Mitigations**:
1. DSAR procedure (Section 3) includes explicit discovery queries for every store.
2. Erasure procedure (Section 4) includes verification step that re-runs discovery to confirm completeness.
3. Retention automation (Section 6) acts as a backstop — even if a manual erasure misses a record, the automated job will anonymize it at the retention boundary.
4. Quarterly audit: run a sample of 10 past erasure requests and verify no PII remains.

### Assessment Approval

| Role | Name | Date | Decision |
|---|---|---|---|
| Data Protection Officer | ___________________ | __________ | Approved / Conditionally Approved / Rejected |
| IT Manager | ___________________ | __________ | Reviewed |
| Security Lead | ___________________ | __________ | Reviewed |
| Business Owner | ___________________ | __________ | Reviewed |

**Next review date**: 12 months from approval, or upon significant system change (whichever comes first).
