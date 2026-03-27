# Enterprise Help Desk — Deployment Guide

This guide walks through deploying the full Enterprise Help Desk system from scratch. Each phase builds on the previous one — follow them in order. The entire deployment takes approximately 4-6 hours for a first-time setup.

## Prerequisites Checklist

Complete every item before starting Phase 1.

### Azure Subscription

- [ ] Active Azure subscription with Contributor access (or a resource group with Contributor + User Access Administrator).
- [ ] Resource providers registered: `Microsoft.Web`, `Microsoft.Sql`, `Microsoft.KeyVault`, `Microsoft.Insights`, `Microsoft.OperationalInsights`.

### Microsoft 365 Tenant

- [ ] M365 E3 or E5 licenses assigned to all help desk users.
- [ ] Power Apps per-user or per-app licenses assigned to agents and managers.
- [ ] Power BI Pro (or Premium Per User) licenses assigned to managers and executives who will view dashboards.
- [ ] Copilot Studio capacity or per-message allocation provisioned.
- [ ] SharePoint Online site collection for the Knowledge Base portal created or identified.

### Admin Roles

- [ ] **Azure**: Contributor on the target resource group.
- [ ] **Entra ID**: Application Administrator (to create app registrations) or Global Administrator.
- [ ] **Power Platform**: Environment Admin on the target environments (or System Administrator role in Dataverse).
- [ ] **SharePoint**: Site Collection Administrator on the target site.
- [ ] **Power BI**: Power BI Service Administrator (or Workspace Admin on the target workspace).
- [ ] **Exchange**: Exchange Administrator (to configure the shared mailbox).

### Tools

Install the following on the deployment workstation:

| Tool | Version | Install |
|---|---|---|
| Azure CLI | 2.60+ | `winget install Microsoft.AzureCLI` |
| .NET SDK | 10.x | `winget install Microsoft.DotNet.SDK.10` |
| Azure Functions Core Tools | 4.x | `npm install -g azure-functions-core-tools@4` |
| Node.js | 18.x LTS | `winget install OpenJS.NodeJS.LTS` |
| Power Platform CLI (pac) | Latest | `dotnet tool install -g Microsoft.PowerApps.CLI.Tool` |
| gulp CLI | 4.x | `npm install -g gulp-cli` |
| SharePoint Framework (SPFx) | 1.20+ | `npm install -g @microsoft/generator-sharepoint` |
| Power BI Desktop | Latest | `winget install Microsoft.PowerBIDesktop` |

Verify all tools:

```bash
az --version
dotnet --version
func --version
node --version
pac --version
gulp --version
```

---

## Phase 1: Azure Infrastructure

All Azure resources are defined in the Bicep template at `infra/main.bicep`. This deploys the Function App, Azure SQL, Key Vault, Application Insights, and supporting resources in a single operation.

### 1.1 Authenticate and Set Context

```bash
az login
az account set --subscription "<subscription-id>"
```

### 1.2 Create the Resource Group

```bash
az group create \
  --name helpdesk-rg \
  --location eastus
```

### 1.3 Deploy the Bicep Template

```bash
az deployment group create \
  --resource-group helpdesk-rg \
  --template-file infra/main.bicep \
  --parameters infra/parameters/prod.bicepparam
```

This typically takes 5-10 minutes. The template creates:

| Resource | Name | Purpose |
|---|---|---|
| Function App (Consumption) | `helpdesk-functions` | Email parsing, Dataverse-to-SQL sync, Graph integration |
| Azure SQL Server + Database | `helpdesk-sql` / `helpdesk-reporting` | Reporting warehouse (star schema) |
| Key Vault | `helpdesk-kv` | Secrets and certificates for S2S auth |
| Application Insights | `helpdesk-insights` | Telemetry, logging, alerting |
| Log Analytics Workspace | `helpdesk-logs` | Backing store for Application Insights |
| Storage Account | `helpdeskstorage` | Function App trigger state and logs |

### 1.4 Capture Output Values

```bash
az deployment group show \
  --resource-group helpdesk-rg \
  --name main \
  --query properties.outputs \
  -o json
```

Record these values — they are needed in later phases:

- `functionAppUrl` — the Function App base URL (e.g., `https://helpdesk-functions.azurewebsites.net`).
- `sqlConnectionString` — the Azure SQL connection string (managed identity format).
- `appInsightsKey` — the Application Insights instrumentation key.
- `keyVaultUri` — the Key Vault URI (e.g., `https://helpdesk-kv.vault.azure.net`).

### 1.5 Verify Resources

```bash
az resource list --resource-group helpdesk-rg --output table
```

Confirm all six resources are listed with `Succeeded` provisioning state.

---

## Phase 2: Entra ID Configuration

Three app registrations are required. Each serves a distinct integration boundary, following the principle of least privilege.

### 2.1 App Registration: Functions-S2S (Azure Functions to Dataverse)

This registration allows the Function App to call the Dataverse Web API as a service principal with the S2S quota (40,000 requests per 5 minutes).

1. Create the registration:

   ```bash
   az ad app create \
     --display-name "HelpDesk-Functions-S2S" \
     --sign-in-audience AzureADMyOrg
   ```

2. Record the `appId` from the output.

3. Add the Dataverse API permission (`user_impersonation` for Dynamics CRM):

   ```bash
   az ad app permission add \
     --id <app-id> \
     --api 00000007-0000-0000-c000-000000000000 \
     --api-permissions 78ce3f0f-a1ce-49c2-8cde-64b5c0896db4=Scope
   ```

4. Grant admin consent:

   ```bash
   az ad app permission admin-consent --id <app-id>
   ```

5. Generate a client secret (or preferably a certificate):

   ```bash
   az ad app credential reset \
     --id <app-id> \
     --display-name "helpdesk-functions-s2s" \
     --years 2
   ```

6. Store the secret in Key Vault:

   ```bash
   az keyvault secret set \
     --vault-name helpdesk-kv \
     --name "DataverseClientSecret" \
     --value "<client-secret>"
   ```

### 2.2 App Registration: SPFx-Dataverse (SharePoint to Dataverse)

This registration allows the SPFx web parts to call the Dataverse Web API using the signed-in user's identity via `AadHttpClient`.

1. Create the registration:

   ```bash
   az ad app create \
     --display-name "HelpDesk-SPFx-Dataverse" \
     --sign-in-audience AzureADMyOrg \
     --web-redirect-uris "https://<tenant>.sharepoint.com/_forms/spfxsinglesignon.aspx"
   ```

2. Add the Dataverse API permission (`user_impersonation`):

   ```bash
   az ad app permission add \
     --id <app-id> \
     --api 00000007-0000-0000-c000-000000000000 \
     --api-permissions 78ce3f0f-a1ce-49c2-8cde-64b5c0896db4=Scope
   ```

3. Grant admin consent:

   ```bash
   az ad app permission admin-consent --id <app-id>
   ```

4. Note: No client secret is needed — SPFx uses the SharePoint context to obtain tokens automatically.

### 2.3 App Registration: Functions-Graph (Azure Functions to Microsoft Graph)

This registration allows the Function App to read user profiles, manager chains, and send notifications via Microsoft Graph.

1. Create the registration:

   ```bash
   az ad app create \
     --display-name "HelpDesk-Functions-Graph" \
     --sign-in-audience AzureADMyOrg
   ```

2. Add Microsoft Graph application permissions:

   ```bash
   # User.Read.All — read user profiles and manager chains
   az ad app permission add \
     --id <app-id> \
     --api 00000003-0000-0000-c000-000000000000 \
     --api-permissions df021288-bdef-4463-88db-98f22de89214=Role

   # Mail.Send — send ticket confirmation emails
   az ad app permission add \
     --id <app-id> \
     --api 00000003-0000-0000-c000-000000000000 \
     --api-permissions b633e1c5-b582-4048-a93e-9f11b44c7e96=Role
   ```

3. Grant admin consent:

   ```bash
   az ad app permission admin-consent --id <app-id>
   ```

4. Generate a client secret and store it in Key Vault:

   ```bash
   az ad app credential reset \
     --id <app-id> \
     --display-name "helpdesk-functions-graph" \
     --years 2

   az keyvault secret set \
     --vault-name helpdesk-kv \
     --name "GraphClientSecret" \
     --value "<client-secret>"
   ```

### 2.4 Verify All Registrations

```bash
az ad app list --display-name "HelpDesk" --query "[].{name:displayName, appId:appId}" -o table
```

You should see three registrations.

---

## Phase 3: Power Platform Setup

### 3.1 Create Environments

Create three environments for the Dev-Test-Prod ALM pipeline. Each environment includes a Dataverse database.

1. Open the Power Platform admin center → Environments → New.
2. Create:
   - **HelpDesk-Dev** — Development (Sandbox type).
   - **HelpDesk-Test** — Testing (Sandbox type).
   - **HelpDesk-Prod** — Production (Production type).
3. Enable Dataverse database for each environment. Select the appropriate currency and language.

Alternatively, use the CLI:

```bash
pac admin create --name "HelpDesk-Dev" --type Sandbox --region unitedstates
pac admin create --name "HelpDesk-Test" --type Sandbox --region unitedstates
pac admin create --name "HelpDesk-Prod" --type Production --region unitedstates
```

### 3.2 Register the S2S Application User

The Azure Functions service principal must be registered as an application user in Dataverse to call the Web API.

1. Open Power Platform admin center → Environments → HelpDesk-Prod → Settings → Users + permissions → Application users.
2. Click "New app user."
3. Select the **HelpDesk-Functions-S2S** app registration.
4. Select the **HelpDesk-Prod** business unit.
5. Assign the **HD - System Service** security role (or **System Administrator** for initial setup, then scope down).

Repeat for Dev and Test environments.

### 3.3 Import the Managed Solution

```bash
pac auth create --environment "https://helpdesk-prod.crm.dynamics.com"

pac solution import \
  --path power-platform/solutions/HelpDesk/ \
  --managed true \
  --publish-changes true
```

Wait for the import to complete. Verify in Power Platform admin center → Environments → HelpDesk-Prod → Solutions that the **Help Desk** solution appears with status "Managed."

### 3.4 Seed Reference Data

After the solution is imported, seed the lookup tables with reference data:

1. **Categories and Subcategories**: Import from the provided CSV files or manually create them in the model-driven app.
   - Hardware, Software, Network, Access, Other.
   - Each category has 3-8 subcategories.

2. **SLA Profiles**: Create SLA profiles that match the organization's service level agreements.
   - P1 Critical: 1 hour response, 4 hour resolution.
   - P2 High: 4 hour response, 8 hour resolution.
   - P3 Medium: 8 hour response, 24 hour resolution.
   - P4 Low: 24 hour response, 72 hour resolution.

3. **Business Units**: If not already created, set up business units matching the IT support team structure (e.g., North America, EMEA, APAC).

### 3.5 Enable Change Tracking

Verify that change tracking is enabled on all tables that will sync to Azure SQL:

1. Open Power Platform admin center → Environments → HelpDesk-Prod → Tables.
2. For each of these tables, open Properties and confirm "Track changes" is enabled:
   - `hd_Ticket`
   - `hd_TicketComment`
   - `hd_Category`
   - `hd_Subcategory`
   - `hd_Asset`
   - `hd_SLAProfile`

---

## Phase 4: Azure Functions Deployment

### 4.1 Configure Application Settings

Set the application settings that the functions need at runtime. All secrets are referenced from Key Vault.

```bash
az functionapp config appsettings set \
  --name helpdesk-functions \
  --resource-group helpdesk-rg \
  --settings \
    "DATAVERSE_URL=https://helpdesk-prod.crm.dynamics.com" \
    "DATAVERSE_CLIENT_ID=<functions-s2s-app-id>" \
    "DATAVERSE_CLIENT_SECRET=@Microsoft.KeyVault(SecretUri=https://helpdesk-kv.vault.azure.net/secrets/DataverseClientSecret)" \
    "DATAVERSE_TENANT_ID=<tenant-id>" \
    "GRAPH_CLIENT_ID=<functions-graph-app-id>" \
    "GRAPH_CLIENT_SECRET=@Microsoft.KeyVault(SecretUri=https://helpdesk-kv.vault.azure.net/secrets/GraphClientSecret)" \
    "GRAPH_TENANT_ID=<tenant-id>" \
    "SQL_CONNECTION_STRING=Server=tcp:helpdesk-sql.database.windows.net,1433;Database=helpdesk-reporting;Authentication=Active Directory Managed Identity;" \
    "APPINSIGHTS_INSTRUMENTATIONKEY=<app-insights-key>" \
    "SYNC_BATCH_SIZE=500"
```

### 4.2 Grant Key Vault Access to the Function App

The Function App's managed identity needs Get access to Key Vault secrets:

```bash
# Get the Function App's managed identity principal ID
PRINCIPAL_ID=$(az functionapp identity show \
  --name helpdesk-functions \
  --resource-group helpdesk-rg \
  --query principalId -o tsv)

# Grant Key Vault access
az keyvault set-policy \
  --name helpdesk-kv \
  --object-id $PRINCIPAL_ID \
  --secret-permissions get list
```

### 4.3 Deploy the Function App

**Option A: GitHub Actions (recommended for ongoing deployments)**

Push to the `main` branch. The GitHub Actions workflow at `.github/workflows/functions-deploy.yml` handles build, test, and deployment automatically.

**Option B: Manual deployment**

```bash
cd functions/HelpDesk.Functions
dotnet publish -c Release -o ./publish

cd publish
func azure functionapp publish helpdesk-functions
```

### 4.4 Verify Deployment

1. Check the health endpoint:

   ```bash
   curl https://helpdesk-functions.azurewebsites.net/api/health
   ```

   Expected response: `{"status":"healthy","version":"1.0.0"}`.

2. Verify all functions are listed:

   ```bash
   az functionapp function list \
     --name helpdesk-functions \
     --resource-group helpdesk-rg \
     --output table
   ```

   Expected functions: `DataverseSyncToSQL`, `EmailToTicket`, `SyncUsers`, `WebhookReceiver`, `ClassifyTicket`, `Health`.

---

## Phase 5: SQL Database Initialization

### 5.1 Run the Schema Script

Connect to Azure SQL and execute the schema script that creates the reporting warehouse tables (star schema):

```bash
sqlcmd -S helpdesk-sql.database.windows.net \
  -d helpdesk-reporting \
  --authentication-method=ActiveDirectoryDefault \
  -i sql/schema.sql
```

This creates:
- Fact tables: `FactTicket`, `FactTicketComment`, `FactSLAEvent`.
- Dimension tables: `DimDate`, `DimCategory`, `DimAgent`, `DimPriority`, `DimStatus`.
- Sync tracking: `SyncState`.

### 5.2 Seed the Date Dimension

```bash
sqlcmd -S helpdesk-sql.database.windows.net \
  -d helpdesk-reporting \
  --authentication-method=ActiveDirectoryDefault \
  -i sql/seed-date-dim.sql
```

This populates `DimDate` with rows from 2024-01-01 through 2030-12-31, including fiscal year/quarter columns.

### 5.3 Create Aggregation Stored Procedures

```bash
sqlcmd -S helpdesk-sql.database.windows.net \
  -d helpdesk-reporting \
  --authentication-method=ActiveDirectoryDefault \
  -i sql/aggregation-sprocs.sql
```

This creates:
- `sp_AggregateTicketMetrics` — daily ticket volume, resolution time percentiles.
- `sp_AggregateSLACompliance` — SLA hit/miss rates by category and priority.
- `sp_AggregateAgentPerformance` — per-agent throughput and quality metrics.

### 5.4 Grant Managed Identity Access

The Function App's managed identity needs read/write access to push sync data, and execute access to run stored procedures:

```sql
CREATE USER [helpdesk-functions] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [helpdesk-functions];
ALTER ROLE db_datawriter ADD MEMBER [helpdesk-functions];
GRANT EXECUTE TO [helpdesk-functions];
```

The Power BI service connection needs read-only access:

```sql
CREATE USER [powerbi-service@contoso.com] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [powerbi-service@contoso.com];
```

### 5.5 Trigger Initial Sync

Manually invoke the sync function to perform the initial full load from Dataverse to Azure SQL:

```bash
az functionapp function invoke \
  --name helpdesk-functions \
  --resource-group helpdesk-rg \
  --function-name DataverseSyncToSQL
```

Monitor progress in Application Insights. The initial sync may take several minutes depending on existing data volume. Verify by checking the `SyncState` table:

```sql
SELECT TableName, LastSyncTime, ErrorMessage FROM dbo.SyncState;
```

All rows should show a recent `LastSyncTime` and `NULL` for `ErrorMessage`.

---

## Phase 6: SPFx Deployment

### 6.1 Install Dependencies and Build

```bash
cd spfx
npm install

gulp bundle --ship
gulp package-solution --ship
```

The build output is at `spfx/sharepoint/solution/helpdesk-webparts.sppkg`.

### 6.2 Upload to SharePoint App Catalog

1. Open the SharePoint admin center → More features → Apps → App Catalog.
2. If no App Catalog exists, create one.
3. Upload `helpdesk-webparts.sppkg` to the "Apps for SharePoint" library.
4. In the deployment prompt, check "Make this solution available to all sites in the organization" and click "Deploy."

Alternatively, use the CLI:

```bash
# Authenticate to SharePoint
npx @pnp/cli-microsoft365 login

# Upload and deploy
npx @pnp/cli-microsoft365 spo app add \
  --filePath spfx/sharepoint/solution/helpdesk-webparts.sppkg \
  --appCatalogUrl https://<tenant>.sharepoint.com/sites/appcatalog \
  --overwrite

npx @pnp/cli-microsoft365 spo app deploy \
  --name helpdesk-webparts.sppkg \
  --appCatalogUrl https://<tenant>.sharepoint.com/sites/appcatalog
```

### 6.3 Approve API Permission Requests

The SPFx package requests permissions to call the Dataverse Web API and Microsoft Graph. These must be approved by an admin.

1. Open SharePoint admin center → Advanced → API access.
2. Approve the pending requests:
   - **HelpDesk-SPFx-Dataverse**: `user_impersonation` on Dynamics CRM.
   - **Microsoft Graph**: `User.Read`, `User.ReadBasic.All` (for profile photos and people search).

### 6.4 Add Web Parts to Target Pages

1. Navigate to the SharePoint site that hosts the Help Desk Knowledge Base.
2. Edit the home page (or create a new page).
3. Add the following web parts:
   - **Help Desk Ticket Dashboard** — shows the user's open tickets with status, priority, and last update.
   - **Knowledge Base Search** — full-text search across KB articles with category filtering.
   - **Quick Ticket Submit** — lightweight ticket creation form for common request types.
4. Publish the page.

### 6.5 Verify SPFx Web Parts

1. Open the SharePoint page in a browser as a test user.
2. Confirm the Ticket Dashboard loads ticket data from Dataverse (not a permission error).
3. Confirm the KB Search returns results from SharePoint search.
4. Submit a test ticket via the Quick Ticket Submit web part and verify it appears in Dataverse.

---

## Phase 7: Power BI Setup

### 7.1 Open and Configure the Report

1. Open the `.pbix` file from the repository in Power BI Desktop.
2. Update the data source connection to point to the production Azure SQL database:
   - Home → Transform data → Data source settings → Change source.
   - Server: `helpdesk-sql.database.windows.net`.
   - Database: `helpdesk-reporting`.
   - Authentication: Microsoft account (or SQL login for initial setup).

3. Verify all visuals render correctly with production data.

### 7.2 Publish to Power BI Service

1. In Power BI Desktop: Home → Publish → select the target workspace.
2. Wait for the publish to complete.

### 7.3 Configure DirectQuery Credentials

If the dataset uses DirectQuery (recommended for operational dashboards):

1. Open Power BI Service → Workspace → Dataset → Settings.
2. Under "Data source credentials," click "Edit credentials."
3. Authentication method: OAuth2 (recommended) or Basic.
4. If using OAuth2, sign in with a service account that has `db_datareader` on the reporting database.
5. Privacy level: Organizational.

### 7.4 Set Up Row-Level Security (RLS)

1. In Power BI Service → Dataset → Security.
2. Map Entra ID security groups to the RLS roles defined in the report:
   - **Agents**: See tickets in their business unit only.
   - **Managers**: See tickets across their team's business units.
   - **Executives**: See all tickets (no filter).
3. Test with "Test as role" to verify data scoping.

### 7.5 Configure Scheduled Refresh (Import Mode Only)

If any tables use Import mode:

1. Power BI Service → Dataset → Settings → Scheduled refresh.
2. Enable and set the frequency (recommended: every 15 minutes during business hours).
3. Configure failure notification emails to the platform team.

### 7.6 Pin to Teams Channel

1. Open Microsoft Teams → navigate to the Help Desk team → the "Dashboards" channel.
2. Click the **+** tab → Power BI → select the published report.
3. Choose the default page (e.g., "Operational Overview").
4. Save the tab.

---

## Phase 8: Copilot Studio Setup

### 8.1 Import the Bot Definition

1. Open Copilot Studio → select the HelpDesk-Prod environment.
2. Click "Import" and select the bot export file from the repository.
3. Resolve any connection references during import (Dataverse, Power Automate).

### 8.2 Configure Knowledge Sources

1. Open the bot → Settings → Knowledge.
2. Add the SharePoint Knowledge Base site as a knowledge source. Copilot Studio will use it for generative answers.
3. Add the Dataverse FAQ table (if applicable) as a secondary source.
4. Test a few questions in the Test pane to verify answers are grounded in the KB.

### 8.3 Connect to Power Automate Flows

The bot uses Power Automate cloud flows to perform actions (create ticket, check ticket status, escalate to agent).

1. Open each topic that calls a flow.
2. Verify the flow connection is bound to the correct environment and uses the correct connection references.
3. Test each flow action from the Test pane.

### 8.4 Deploy to Teams

1. Open the bot → Channels → Microsoft Teams.
2. Click "Turn on Teams."
3. Open Teams Admin Center → Manage apps → find the Help Desk Bot → publish to the organization.
4. Optionally, pin the bot in the Teams app setup policy so it appears in every user's left rail.

### 8.5 Verify the Bot

1. Open Teams as a test user.
2. Start a conversation with the Help Desk Bot.
3. Test:
   - "I need help with my laptop" — should offer to create a ticket.
   - "What's the status of my ticket?" — should look up open tickets.
   - "How do I connect to VPN?" — should return a KB article via generative answers.

---

## Phase 9: Post-Deployment Verification

Run through this checklist to confirm the entire system is operational.

### 9.1 Health Check

```bash
curl https://helpdesk-functions.azurewebsites.net/api/health
```

Confirm: `{"status":"healthy"}`.

### 9.2 End-to-End Ticket Test

1. **Self-service submission**: Submit a test ticket via the canvas app (or SPFx Quick Ticket web part).
2. **Verify routing**: Confirm the ticket appears in the correct agent's queue in the model-driven app (correct category, priority, and business unit).
3. **Verify SLA clock**: Confirm the SLA timer started and the due date is set correctly.
4. **Agent action**: As an agent, add an internal note and a public comment. Reassign the ticket.
5. **Notification**: Confirm the requester received a Teams notification (or email) about the status change.
6. **Resolution**: Resolve the ticket. Confirm the SLA is marked as Met or Breached.

### 9.3 Email-to-Ticket Test

1. Send an email to `helpdesk@contoso.com` with a subject and body.
2. Confirm a ticket is created in Dataverse within 5 minutes.
3. Confirm a confirmation email is sent back to the sender.

### 9.4 Power BI Data Verification

1. Wait 10 minutes after creating test tickets.
2. Open the Power BI dashboard and confirm the test tickets appear in the visualizations.
3. Verify SLA compliance percentages, ticket volume, and queue depth reflect reality.

### 9.5 Bot Verification

1. Open Teams and interact with the Copilot Studio bot.
2. Confirm it can create a ticket, look up status, and answer KB questions.

### 9.6 Security Verification

1. Sign in as a **Requester** — confirm they can only see their own tickets.
2. Sign in as an **Agent** — confirm they can see tickets in their business unit but not other BUs.
3. Sign in as a **Manager** — confirm they can see tickets across their BUs and access the Power BI dashboard.

---

## Phase 10: Rollback Procedures

If a deployment causes issues, follow the per-component rollback procedures below. Each component is independently deployable and rollbackable, matching the fault isolation architecture.

### 10.1 Azure Functions Rollback

Roll back to the previous deployment slot:

```bash
# If using deployment slots
az functionapp deployment slot swap \
  --name helpdesk-functions \
  --resource-group helpdesk-rg \
  --slot staging \
  --target-slot production

# If not using slots, redeploy the previous version
func azure functionapp publish helpdesk-functions --package <previous-version.zip>
```

Alternatively, disable the specific function that is causing issues without affecting other functions:

```bash
az functionapp config appsettings set \
  --name helpdesk-functions \
  --resource-group helpdesk-rg \
  --settings "AzureWebJobs.<FunctionName>.Disabled=true"
```

### 10.2 Power Platform Solution Rollback

Managed solutions can be rolled back by importing the previous version:

```bash
pac solution import \
  --path power-platform/solutions/HelpDesk-v1.0.0/ \
  --managed true \
  --publish-changes true
```

If the solution import caused data loss or corruption, restore from the Dataverse environment backup (available for up to 28 days):

1. Open Power Platform admin center → Environments → HelpDesk-Prod → Backups.
2. Select the most recent backup before the deployment.
3. Restore to a new environment, verify, then promote.

### 10.3 Azure SQL Rollback

Roll back schema changes by running the corresponding rollback script:

```bash
sqlcmd -S helpdesk-sql.database.windows.net \
  -d helpdesk-reporting \
  --authentication-method=ActiveDirectoryDefault \
  -i sql/rollback/<version>.sql
```

If no rollback script exists, restore from a point-in-time backup:

```bash
az sql db restore \
  --dest-name helpdesk-reporting-restored \
  --name helpdesk-reporting \
  --server helpdesk-sql \
  --resource-group helpdesk-rg \
  --time "2026-03-26T10:00:00Z"
```

### 10.4 SPFx Rollback

1. Upload the previous `.sppkg` to the App Catalog (overwriting the current version).
2. Alternatively, retract the app: SharePoint admin center → App Catalog → select the app → Retract.

### 10.5 Power BI Rollback

1. Open Power BI Desktop with the previous `.pbix` file.
2. Publish to the same workspace, overwriting the current report and dataset.

### 10.6 Full System Rollback

In the event of a catastrophic deployment failure affecting multiple components:

1. **Stop the bleed**: Disable Azure Functions and turn off Power Automate flows to prevent data corruption.
2. **Assess scope**: Identify which components are affected and which are healthy.
3. **Roll back in reverse order**: Copilot Studio → Power BI → SPFx → SQL → Functions → Power Platform solution.
4. **Verify each layer**: After rolling back each component, verify it works independently before moving to the next.
5. **Communicate**: Notify stakeholders of the rollback and estimated recovery time.
6. **Post-mortem**: Document what went wrong, the root cause, and prevention measures.
