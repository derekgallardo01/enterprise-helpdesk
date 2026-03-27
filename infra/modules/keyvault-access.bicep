// Key Vault access module: Grants RBAC role to Function App managed identity

@description('Key Vault name')
param keyVaultName string

@description('Principal ID of the Function App managed identity')
param principalId string


// ──────────────────────────────────────────────
// Role Assignment: Key Vault Secrets User
// ──────────────────────────────────────────────

// Built-in role: Key Vault Secrets User (4633458b-17de-408a-b874-0445c86b69e6)
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
