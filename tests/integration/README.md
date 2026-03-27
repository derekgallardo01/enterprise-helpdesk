# Integration Tests

## Overview

Integration tests verify end-to-end behavior of the Enterprise Help Desk system against live Dataverse and Azure SQL test environments. These tests are NOT run in CI/CD pipelines -- they require authenticated access to test environments.

## Prerequisites

- PowerShell 7+ with the following modules:
  - `Microsoft.Xrm.Data.PowerShell` (for Dataverse connectivity)
  - `SqlServer` (for Azure SQL connectivity)
- Azure AD credentials with access to the test Dataverse environment
- Network access to:
  - `helpdesk-test.crm.dynamics.com` (Dataverse test org)
  - `helpdesk-sql-test.database.windows.net` (Azure SQL test warehouse)
  - `helpdesk-functions-test.azurewebsites.net` (Azure Functions test slot)
- .NET 10.0 SDK (for xUnit-based integration tests)

## Configuration

Test parameters are stored in `test.runsettings`:

| Parameter | Description |
|---|---|
| `DataverseUrl` | URL of the Dataverse test organization |
| `FunctionAppUrl` | Base URL of the test Function App |
| `SqlConnectionString` | Connection string for the test SQL warehouse |

Override these via environment variables or by editing `test.runsettings` directly.

## How to Run

### 1. Set up test data

```powershell
# Creates test categories, subcategories, SLA profiles, and 10 test tickets
.\setup.ps1
```

### 2. Run .NET unit tests

```bash
cd functions/HelpDesk.Functions.Tests
dotnet test --settings ../../tests/integration/test.runsettings
```

### 3. Run integration tests manually

Integration tests are currently script-based. Run each script individually:

```powershell
# Security / RBAC tests
..\security\rbac-tests.ps1

# Performance tests (requires k6 installed)
k6 run ..\performance\dashboard-load.js
k6 run ..\performance\ticket-creation.js
k6 run ..\performance\sync-benchmark.js
```

### 4. Tear down test data

```powershell
.\teardown.ps1
```

## Test Environments

| Environment | Purpose | Refresh Cadence |
|---|---|---|
| DEV | Developer sandbox | On-demand |
| TEST | Integration testing | Weekly from PROD snapshot |
| UAT | User acceptance testing | Before each release |
| PROD | Production | N/A |

## Notes

- All test records are prefixed with `[TEST]` in the title for easy identification and cleanup.
- The setup script is idempotent -- it checks for existing records before creating.
- Teardown only deletes records with the `[TEST]` prefix to avoid affecting other data.
