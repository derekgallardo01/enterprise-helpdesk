# Infrastructure — Enterprise Help Desk

## Monthly Cost: ~$5/month idle

## Quick Shutdown
```powershell
az group delete --name helpdesk-rg --yes --no-wait
```

## Azure Resources

**Resource Group:** `helpdesk-rg` (centralus)

| Resource | Type | SKU | Monthly Cost |
|----------|------|-----|-------------|
| helpdesk-func-dev-z3fneilrvkquu | Function App | Consumption (Y1) | $0 |
| helpdesk-func-dev-z3fneilrvkquu-plan | App Service Plan | Dynamic (Y1) | $0 |
| helpdesk-sql-dev-z3fneilrvkquu | SQL Server | Entra-only auth | $0 |
| helpdesk-reporting | SQL Database | Basic | **~$5** |
| helpdeskkvdevz3fnei | Key Vault | Standard | $0 |
| helpdesk-ai-dev | Application Insights | Workspace-based | $0 |
| helpdesk-logs-dev | Log Analytics | Per-GB | $0 |
| hdstdevz3fneilrvk | Storage Account | Standard_LRS | $0 |
| helpdesk-openai-dev | Azure OpenAI | S0 (pay-per-token) | $0 idle |

## Entra ID App Registrations

| App | Client ID | Secret Location |
|-----|-----------|----------------|
| HelpDesk-Functions-S2S | 14508eea-b75f-4890-b3db-7452516118c6 | Key Vault: DataverseClientSecret |
| HelpDesk-SPFx-Dataverse | bfc5eb6f-0c57-49c8-8fc2-b6f018415cbf | None (delegated) |
| HelpDesk-Functions-Graph | a7056559-abd7-4f63-b2e4-6f87d0084295 | Key Vault: GraphClientSecret |

## External Dependencies

| Service | Tenant | URL | Cost |
|---------|--------|-----|------|
| Dataverse (Power Platform) | DerekGallardo01gmail | org2d0673ab.crm.dynamics.com | $0 (Developer Plan) |
| SharePoint (M365 Trial) | MusicGenie | musicgenie.sharepoint.com | $0 (trial expires ~April 27, 2026) |
| Dataverse (MusicGenie) | MusicGenie | orgfda62156.crm.dynamics.com | $0 (Developer Plan) |

## Recreation Steps

This project uses **Bicep IaC** — full deployment is automated:

```powershell
# 1. Deploy all Azure resources
az group create --name helpdesk-rg --location centralus
az deployment group create --resource-group helpdesk-rg --template-file infra/main.bicep --parameters infra/parameters/dev.bicepparam --name helpdesk-deploy

# 2. Add SQL firewall rule
$myIp = (Invoke-RestMethod "https://api.ipify.org")
az sql server firewall-rule create --resource-group helpdesk-rg --server <sql-server-name-from-output> --name AllowMyIP --start-ip-address $myIp --end-ip-address $myIp

# 3. Initialize SQL schema
$sqlcmd = "C:\Program Files\SqlCmd\sqlcmd.exe"
$server = "<sql-server-fqdn-from-output>"
& $sqlcmd -S $server -d helpdesk-reporting --authentication-method=ActiveDirectoryDefault -i sql/schema.sql
& $sqlcmd -S $server -d helpdesk-reporting --authentication-method=ActiveDirectoryDefault -i sql/migrations/001-add-sync-state.sql
& $sqlcmd -S $server -d helpdesk-reporting --authentication-method=ActiveDirectoryDefault -i sql/seed-date-dim.sql
& $sqlcmd -S $server -d helpdesk-reporting --authentication-method=ActiveDirectoryDefault -i sql/aggregation-sprocs.sql

# 4. Grant Function App managed identity SQL access
& $sqlcmd -S $server -d helpdesk-reporting --authentication-method=ActiveDirectoryDefault -Q "CREATE USER [<function-app-name>] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [<function-app-name>]; ALTER ROLE db_datawriter ADD MEMBER [<function-app-name>];"

# 5. Set DataverseConnectionString
# Use the REST API approach (az functionapp config appsettings has pipe character issues in PowerShell)

# 6. Deploy Functions
cd functions/HelpDesk.Functions
dotnet publish -c Release -o ../deploy-out
Copy-Item host.json ../deploy-out/host.json -Force
# Zip and upload to blob storage, set WEBSITE_RUN_FROM_PACKAGE

# Full step-by-step: see docs/deployment-guide.md
```

## Verified Working Endpoints

| Endpoint | URL |
|----------|-----|
| Health Check | `https://helpdesk-func-dev-z3fneilrvkquu.azurewebsites.net/api/healthcheck` |
| Response | `{"status":"healthy","dataverse":true,"sql":true}` |

## Function App Settings Required

| Setting | Value |
|---------|-------|
| DataverseConnectionString | AuthType=ClientSecret;Url=https://org2d0673ab.crm.dynamics.com;ClientId=...;ClientSecret=...;TenantId=... |
| SqlConnectionString | Server=tcp:...;Database=helpdesk-reporting;Authentication=Active Directory Managed Identity;... |
| AzureOpenAI:Endpoint | https://helpdesk-openai-dev.openai.azure.com/ |
| AzureOpenAI:DeploymentName | gpt-4o-mini |
