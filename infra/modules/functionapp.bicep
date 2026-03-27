// Function App module: Azure Functions (.NET 10 Isolated Worker) + Storage Account

@description('Azure region')
param location string

@description('Function App name')
param functionAppName string

@description('Storage account name')
param storageName string

@description('Environment (dev/test/prod)')
param environment string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string

@description('Key Vault URI')
param keyVaultUri string

@description('Azure SQL connection string')
param sqlConnectionString string

@description('Dataverse environment URL')
param dataverseUrl string

@description('Dataverse S2S app registration client ID')
param dataverseClientId string

@description('Graph API app registration client ID')
param graphClientId string

@description('Entra ID tenant ID')
param tenantId string

@description('Resource tags')
param tags object

// ──────────────────────────────────────────────
// Plan selection by environment
// ──────────────────────────────────────────────

var usePremiumPlan = environment == 'prod'

// ──────────────────────────────────────────────
// Storage Account (required by Functions runtime)
// ──────────────────────────────────────────────

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// ──────────────────────────────────────────────
// App Service Plan
// ──────────────────────────────────────────────

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: usePremiumPlan ? {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
    family: 'EP'
    capacity: 1
  } : {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    reserved: true // Linux
  }
}

// ──────────────────────────────────────────────
// Function App
// ──────────────────────────────────────────────

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|10.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      cors: {
        allowedOrigins: [
          'https://*.sharepoint.com'
        ]
        supportCredentials: true
      }
      appSettings: [
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=core.windows.net;AccountKey=${storageAccount.listKeys().keys[0].value}' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'dotnet-isolated' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY', value: appInsightsInstrumentationKey }
        { name: 'KeyVaultUri', value: keyVaultUri }
        { name: 'SqlConnectionString', value: sqlConnectionString }
        { name: 'Dataverse__Url', value: dataverseUrl }
        { name: 'Dataverse__ClientId', value: dataverseClientId }
        { name: 'Dataverse__TenantId', value: tenantId }
        { name: 'Graph__ClientId', value: graphClientId }
        { name: 'Graph__TenantId', value: tenantId }
      ]
    }
  }
}

// ──────────────────────────────────────────────
// Staging Slot (for zero-downtime deployment)
// ──────────────────────────────────────────────

resource stagingSlot 'Microsoft.Web/sites/slots@2023-12-01' = if (environment == 'prod') {
  parent: functionApp
  name: 'staging'
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|10.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      autoSwapSlotName: 'production'
    }
  }
}

// ──────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────

output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
output functionAppResourceId string = functionApp.id
