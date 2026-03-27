// Enterprise Help Desk Portal — Main Infrastructure Template
// Deploys all Azure resources required for the help desk system.
//
// Usage:
//   az deployment group create \
//     --resource-group helpdesk-rg \
//     --template-file infra/main.bicep \
//     --parameters infra/parameters/dev.bicepparam

targetScope = 'resourceGroup'

// ──────────────────────────────────────────────
// Parameters
// ──────────────────────────────────────────────

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Base name prefix for resources (e.g., helpdesk)')
param baseName string = 'helpdesk'

@description('Dataverse environment URL (e.g., https://org.crm.dynamics.com)')
param dataverseUrl string

@description('Entra ID tenant ID')
param tenantId string = subscription().tenantId

@description('App registration client ID for Dataverse S2S auth')
param dataverseClientId string

@description('App registration client ID for Microsoft Graph')
param graphClientId string

@description('Azure SQL administrator Entra ID group object ID')
param sqlAdminGroupObjectId string

@description('Azure SQL administrator Entra ID group display name')
param sqlAdminGroupName string

@description('Tags applied to all resources')
param tags object = {
  project: 'enterprise-helpdesk'
  environment: environment
  managedBy: 'bicep'
}

// ──────────────────────────────────────────────
// Variables
// ──────────────────────────────────────────────

var uniqueSuffix = uniqueString(resourceGroup().id, baseName)
var functionAppName = '${baseName}-func-${environment}-${uniqueSuffix}'
var sqlServerName = '${baseName}-sql-${environment}-${uniqueSuffix}'
var sqlDatabaseName = '${baseName}-reporting'
var appInsightsName = '${baseName}-ai-${environment}'
var logAnalyticsName = '${baseName}-logs-${environment}'
var keyVaultName = '${baseName}kv${environment}${substring(uniqueSuffix, 0, 6)}'
var storageName = 'hdst${environment}${substring(uniqueSuffix, 0, 10)}'

// ──────────────────────────────────────────────
// Modules
// ──────────────────────────────────────────────

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-${environment}'
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    tags: tags
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-${environment}'
  params: {
    location: location
    keyVaultName: keyVaultName
    tenantId: tenantId
    tags: tags
  }
}

module sql 'modules/sql.bicep' = {
  name: 'sql-${environment}'
  params: {
    location: location
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    environment: environment
    sqlAdminGroupObjectId: sqlAdminGroupObjectId
    sqlAdminGroupName: sqlAdminGroupName
    tenantId: tenantId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    tags: tags
  }
}

module functionApp 'modules/functionapp.bicep' = {
  name: 'functionapp-${environment}'
  params: {
    location: location
    functionAppName: functionAppName
    storageName: storageName
    environment: environment
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    keyVaultUri: keyVault.outputs.keyVaultUri
    sqlConnectionString: sql.outputs.connectionString
    dataverseUrl: dataverseUrl
    dataverseClientId: dataverseClientId
    graphClientId: graphClientId
    tenantId: tenantId
    tags: tags
  }
}

// Grant Function App managed identity access to Key Vault
module keyVaultAccess 'modules/keyvault-access.bicep' = {
  name: 'keyvault-access-${environment}'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: functionApp.outputs.functionAppPrincipalId
  }
}

// SQL managed identity access must be granted via T-SQL after deployment.
// See infra/modules/sql-access.bicep for the required commands:
//   CREATE USER [<functionAppName>] FROM EXTERNAL PROVIDER;
//   ALTER ROLE db_datareader ADD MEMBER [<functionAppName>];
//   ALTER ROLE db_datawriter ADD MEMBER [<functionAppName>];

// ──────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────

@description('Function App default hostname')
output functionAppUrl string = functionApp.outputs.functionAppUrl

@description('Function App managed identity principal ID')
output functionAppPrincipalId string = functionApp.outputs.functionAppPrincipalId

@description('Azure SQL Server fully qualified domain name')
output sqlServerFqdn string = sql.outputs.sqlServerFqdn

@description('Azure SQL Database name')
output sqlDatabaseName string = sqlDatabaseName

@description('Application Insights connection string')
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri
