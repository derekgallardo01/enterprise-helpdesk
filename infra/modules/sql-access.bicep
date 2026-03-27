// SQL access module: Documents managed identity access setup for Azure SQL
//
// NOTE: Azure SQL managed identity access cannot be fully configured via Bicep/ARM.
// The managed identity must be granted database roles via T-SQL after deployment.
// This module documents the required steps and can be extended with deployment scripts.

@description('SQL Server name')
param sqlServerName string

@description('Function App name (used as the managed identity name)')
param functionAppName string

@description('Function App managed identity principal ID')
param functionAppPrincipalId string

// ──────────────────────────────────────────────
// Post-Deployment SQL Script (run manually or via deployment script)
// ──────────────────────────────────────────────
//
// After deploying this template, run the following T-SQL against the database:
//
//   CREATE USER [<functionAppName>] FROM EXTERNAL PROVIDER;
//   ALTER ROLE db_datareader ADD MEMBER [<functionAppName>];
//   ALTER ROLE db_datawriter ADD MEMBER [<functionAppName>];
//   GO
//
// This grants the Function App's managed identity read/write access to the
// reporting database. The identity authenticates via DefaultAzureCredential
// with Authentication=Active Directory Managed Identity in the connection string.
//
// To verify access after granting:
//   SELECT dp.name, dp.type_desc, rp.name AS role_name
//   FROM sys.database_principals dp
//   JOIN sys.database_role_members drm ON dp.principal_id = drm.member_principal_id
//   JOIN sys.database_principals rp ON drm.role_principal_id = rp.principal_id
//   WHERE dp.name = '<functionAppName>';
