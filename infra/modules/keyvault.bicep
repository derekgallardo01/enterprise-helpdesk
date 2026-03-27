// Key Vault module: Stores secrets for app registrations and connection strings

@description('Azure region')
param location string

@description('Key Vault name')
param keyVaultName string

@description('Entra ID tenant ID')
param tenantId string

@description('Resource tags')
param tags object

// ──────────────────────────────────────────────
// Key Vault
// ──────────────────────────────────────────────

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ──────────────────────────────────────────────
// Diagnostic Settings
// ──────────────────────────────────────────────

// Note: Log Analytics integration is configured via the monitoring module.
// Key Vault audit logs are critical for compliance.

// ──────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
