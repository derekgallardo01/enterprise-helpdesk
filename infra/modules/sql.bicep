// SQL module: Azure SQL Server + Database (Entra-only authentication)

@description('Azure region')
param location string

@description('SQL Server name')
param sqlServerName string

@description('SQL Database name')
param sqlDatabaseName string

@description('Environment (dev/test/prod)')
param environment string

@description('Entra ID group object ID for SQL admin')
param sqlAdminGroupObjectId string

@description('Entra ID group display name for SQL admin')
param sqlAdminGroupName string

@description('Entra ID tenant ID')
param tenantId string

@description('Log Analytics workspace ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('Resource tags')
param tags object

// ──────────────────────────────────────────────
// SKU selection by environment
// ──────────────────────────────────────────────

var skuMap = {
  dev: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
    maxSizeBytes: 2147483648 // 2 GB
  }
  test: {
    name: 'S0'
    tier: 'Standard'
    capacity: 10
    maxSizeBytes: 268435456000 // 250 GB
  }
  prod: {
    name: 'S2'
    tier: 'Standard'
    capacity: 50
    maxSizeBytes: 268435456000 // 250 GB
  }
}

var selectedSku = skuMap[environment]

// ──────────────────────────────────────────────
// SQL Server (Entra-only, no SQL auth)
// ──────────────────────────────────────────────

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: null
    administratorLoginPassword: null
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: sqlAdminGroupName
      sid: sqlAdminGroupObjectId
      tenantId: tenantId
      principalType: 'Group'
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Allow Azure services to access (required for Azure Functions with managed identity)
resource firewallAllowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ──────────────────────────────────────────────
// SQL Database
// ──────────────────────────────────────────────

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: selectedSku.name
    tier: selectedSku.tier
    capacity: selectedSku.capacity
  }
  properties: {
    maxSizeBytes: selectedSku.maxSizeBytes
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: environment == 'prod'
    readScale: environment == 'prod' ? 'Enabled' : 'Disabled'
    requestedBackupStorageRedundancy: environment == 'prod' ? 'Geo' : 'Local'
  }
}

// ──────────────────────────────────────────────
// Short-term backup retention (PITR)
// ──────────────────────────────────────────────

resource backupPolicy 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2023-08-01-preview' = {
  parent: sqlDatabase
  name: 'default'
  properties: {
    retentionDays: environment == 'prod' ? 35 : 7
    diffBackupIntervalInHours: environment == 'prod' ? 12 : 24
  }
}

// ──────────────────────────────────────────────
// Diagnostics -> Log Analytics
// ──────────────────────────────────────────────

resource sqlDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sql-diagnostics'
  scope: sqlDatabase
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
      }
      {
        category: 'QueryStoreRuntimeStatistics'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Basic'
        enabled: true
      }
    ]
  }
}

// ──────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output connectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;'
output sqlDatabaseId string = sqlDatabase.id
