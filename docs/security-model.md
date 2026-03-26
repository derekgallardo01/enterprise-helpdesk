# Enterprise Help Desk — Security & Governance Model

## Security Principles

1. **Platform-enforced, not app-enforced**: All access control is defined in Dataverse security roles, not in app UI logic. Hiding a button is not security. Security roles prevent access regardless of which client (Power Apps, SPFx, API, Graph) accesses the data.
2. **Least privilege**: Every role gets the minimum CRUD depth needed. Requesters see only their own tickets.
3. **Single identity plane**: Entra ID is the sole identity provider. No service accounts with passwords, no API keys in app settings.
4. **Defense in depth**: Row-level security + column-level security + DLP policies + managed identity + Key Vault + audit logging.

## Security Roles

### HD - Requester (All Authenticated Employees)

| Table | Create | Read | Write | Delete | Append | AppendTo |
|---|---|---|---|---|---|---|
| `hd_Ticket` | User | User | User* | None | User | User |
| `hd_TicketComment` | User | User** | None | None | User | User |
| `hd_Category` | None | Organization | None | None | None | None |
| `hd_Subcategory` | None | Organization | None | None | None | None |
| `hd_Asset` | None | User | None | None | None | None |
| `hd_KBArticleRef` | None | Organization | None | None | None | None |

*Write restricted to own tickets when status = New (business rule)
**Read restricted to comments where `hd_commenttype = Public` on own tickets (column-level security)

### HD - Agent (IT Support Staff)

| Table | Create | Read | Write | Delete | Append | AppendTo |
|---|---|---|---|---|---|---|
| `hd_Ticket` | Organization | Business Unit | Business Unit | None | BU | BU |
| `hd_TicketComment` | Organization | Business Unit | Business Unit | None | BU | BU |
| `hd_Category` | None | Organization | None | None | None | None |
| `hd_Subcategory` | None | Organization | None | None | None | None |
| `hd_Asset` | None | Organization | Business Unit | None | BU | BU |
| `hd_KBArticleRef` | Organization | Organization | Organization | Organization | Org | Org |
| `hd_SLAProfile` | None | Organization | None | None | None | None |

### HD - Manager (IT Managers)

| Table | Create | Read | Write | Delete | Append | AppendTo |
|---|---|---|---|---|---|---|
| `hd_Ticket` | Organization | Organization | Organization | None | Org | Org |
| `hd_TicketComment` | Organization | Organization | Organization | None | Org | Org |
| `hd_Category` | Organization | Organization | Organization | Organization | Org | Org |
| `hd_Subcategory` | Organization | Organization | Organization | Organization | Org | Org |
| `hd_Asset` | Organization | Organization | Organization | None | Org | Org |
| `hd_Department` | None | Organization | Organization | None | Org | Org |
| `hd_SLAProfile` | Organization | Organization | Organization | Organization | Org | Org |

### HD - Admin (System Administrators)

Full CRUD at Organization level on all custom tables. Can manage security roles, business rules, environment settings, and perform hard deletes (for GDPR compliance).

## Column-Level Security

### Internal Comments Profile

**Problem**: `hd_TicketComment` rows with `hd_commenttype = Internal` contain agent-to-agent notes that requesters must never see — even via API access.

**Solution**: Column-level security profile `HD - Internal Comment Access` applied to `hd_commentbody`:
- **HD - Agent** and above: Read + Update allowed
- **HD - Requester**: No access (column appears null in API responses)

This is enforced at the Dataverse platform level, not in the app UI.

## Business Unit Structure

```
Root BU (Organization)
├── IT Support
│   ├── Hardware Support
│   ├── Software Support
│   ├── Network Support
│   └── Access Management
├── Engineering
├── Finance
├── Human Resources
├── Marketing
└── Operations
```

Agents are assigned to IT Support sub-BUs. Their `Business Unit` read depth means a Hardware Support agent sees all hardware tickets but not software tickets (unless assigned to them directly).

Managers have `Organization` read depth — they see everything.

## Environment Strategy

| Environment | Type | Purpose | DLP Policy | Access |
|---|---|---|---|---|
| `HelpDesk-Dev` | Developer | Building, experimenting, debugging | Permissive | Developers only |
| `HelpDesk-Test` | Sandbox | UAT, integration testing, data validation | Moderate | Developers + QA |
| `HelpDesk-Prod` | Production | Live users, real data | Strict | All users via roles |

### Why 3 Environments

A managed solution imported to Prod **cannot be edited there**. All changes must flow through Dev → Test → Prod. This prevents:
- "Hotfix in production" culture
- Untracked changes
- "Someone modified the flow and now it's broken"

The DLP policy escalation (permissive → moderate → strict) mirrors real consulting engagements.

## DLP (Data Loss Prevention) Policies

### Production Environment

**Business Data Group** (connectors that can interact with each other):
- Dataverse
- Office 365 Outlook
- Office 365 Users
- SharePoint
- Microsoft Teams
- Approvals
- Custom Connector (Help Desk API)

**Blocked Connectors**:
| Connector | Why Blocked |
|---|---|
| HTTP | Can call any URL with any payload. Forces use of authenticated custom connector instead. No unaudited external calls. |
| Twitter / Facebook / Social | No business justification. Prevents data exfiltration to social platforms. |
| Dropbox / Google Drive | Forces document storage through SharePoint (governed, auditable, within M365 boundary). |
| SMTP | Forces email through Office 365 Outlook (auditable, compliant). |

### Dev Environment

All connectors allowed. Developers need flexibility to test integrations.

### Test Environment

Moderate restrictions: social and third-party file connectors blocked, HTTP allowed for API testing.

## ALM (Application Lifecycle Management)

### Pipeline

```
Dev Environment          Source Control         Test Environment      Prod Environment
      |                       |                       |                     |
 Build/test in        Export unmanaged          Import managed         Import managed
 unmanaged      -->   solution XML to    -->   solution + run   -->   solution after
 solution             GitHub/DevOps            automated tests        approval gate
                      (version controlled)     + UAT sign-off
```

### Component Pipelines

| Component | Build | Package | Deploy |
|---|---|---|---|
| Power Platform | Solution export (unmanaged) | Power Platform Build Tools pack | Managed import per environment |
| SPFx | `npm run build` | `npm run package-solution` (.sppkg) | App Catalog via SharePoint ALM APIs |
| Azure Functions | `dotnet publish` | GitHub Actions artifact | Function App (staging slot → swap) |
| Azure SQL | Migration scripts | Sequential SQL execution | `sqlcmd` or EF Core migrations |

### Why Managed Solutions in Prod

Managed solutions are **locked** — components cannot be edited in production. This is the enterprise ALM pattern:
- Changes are traceable (source control)
- Rollback is possible (import previous version)
- No unauthorized modifications in prod
- Consistent environments (Test and Prod have the same solution)

## Audit & Compliance

### Dataverse Audit

- **Enabled on all custom tables**
- **Field-level**: Every change logged with who, when, old value, new value
- **Retention**: 7 years (configurable via Power Platform admin center)
- **Access**: Audit History visible on each record, exportable for compliance reviews

### GDPR Right to Deletion

Power Automate flow triggered by a GDPR deletion request:
1. Query all `hd_Ticket` rows where `hd_requestedby = targetUser`
2. Replace PII columns with `[REDACTED]`: title, description, resolution notes
3. Query all `hd_TicketComment` rows on those tickets
4. Replace `hd_commentbody` with `[REDACTED]`
5. Log the anonymization action with timestamp

**Why anonymize, not delete**: Deleting tickets would break SLA compliance data, trend analysis, and agent performance metrics. Anonymization preserves the statistical record while removing PII.

### Azure Security

| Resource | Security Mechanism |
|---|---|
| Azure Functions → Azure SQL | Managed identity (no connection strings) |
| Azure Functions → Dataverse | S2S app registration (client certificate, not secret) |
| Secrets (if any) | Azure Key Vault with RBAC access policies |
| Function App | HTTPS only, minimum TLS 1.2 |
| Azure SQL | Entra ID authentication, no SQL auth enabled |
| Diagnostic logs | Sent to Log Analytics workspace for centralized monitoring |

### Data Residency

Dataverse environment created in the same geographic region as the M365 tenant (e.g., United States for US-based organizations). Azure resources deployed to the same region. No cross-border data transfer.

## Conditional Access (Entra ID)

Recommended policies for enterprise deployments:

| Policy | Scope | Condition | Control |
|---|---|---|---|
| Require MFA | All users accessing Power Apps | Any sign-in | MFA required |
| Block unmanaged devices | Agents accessing model-driven app | Non-compliant device | Block access |
| Location restriction | Admin role | Outside corporate network | Block or MFA step-up |
| Session timeout | All Power Apps | Idle > 60 minutes | Force re-authentication |

These are configured in Entra ID Conditional Access, not in the application. They apply across all surfaces (Power Apps, SharePoint, Teams, SPFx, API).
