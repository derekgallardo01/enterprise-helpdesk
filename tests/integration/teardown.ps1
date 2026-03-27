<#
.SYNOPSIS
    Tears down test data from the Dataverse test environment.

.DESCRIPTION
    Connects to the Dataverse test organization and deletes:
    - All hd_ticket records where hd_title starts with "[TEST]"
    - All hd_slaprofile records where hd_name starts with "[TEST]"
    - Test subcategories and categories created by setup.ps1

    Uses the record IDs file from setup.ps1 if available, otherwise
    queries Dataverse directly for [TEST]-prefixed records.

.PARAMETER DataverseUrl
    URL of the Dataverse test organization. Default: https://helpdesk-test.crm.dynamics.com

.EXAMPLE
    .\teardown.ps1
    .\teardown.ps1 -DataverseUrl "https://helpdesk-dev.crm.dynamics.com"
#>

[CmdletBinding()]
param(
    [string]$DataverseUrl = "https://helpdesk-test.crm.dynamics.com"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
# Connect to Dataverse
# ---------------------------------------------------------------
Write-Host "Connecting to Dataverse at $DataverseUrl..." -ForegroundColor Cyan
Import-Module Microsoft.Xrm.Data.PowerShell -ErrorAction Stop

$conn = Connect-CrmOnline -ServerUrl $DataverseUrl -ForceOAuth
if (-not $conn.IsReady) {
    throw "Failed to connect to Dataverse: $($conn.LastCrmError)"
}
Write-Host "Connected successfully." -ForegroundColor Green

$deletedCounts = @{
    Tickets       = 0
    SLAProfiles   = 0
    Subcategories = 0
    Categories    = 0
}

# ---------------------------------------------------------------
# Helper: Delete records matching a FetchXML filter
# ---------------------------------------------------------------
function Remove-TestRecords {
    param(
        [string]$EntityName,
        [string]$FilterField,
        [string]$FilterPattern
    )

    $fetchXml = @"
<fetch>
    <entity name="$EntityName">
        <attribute name="${EntityName}id" />
        <attribute name="$FilterField" />
        <filter>
            <condition attribute="$FilterField" operator="like" value="$FilterPattern" />
        </filter>
    </entity>
</fetch>
"@

    $records = Get-CrmRecordsByFetch -conn $conn -Fetch $fetchXml
    $count = 0

    foreach ($record in $records.CrmRecords) {
        $id = $record.("${EntityName}id")
        $name = $record.$FilterField
        try {
            Remove-CrmRecord -conn $conn -EntityLogicalName $EntityName -Id $id
            Write-Host "  [DELETED] $EntityName '$name' ($id)" -ForegroundColor Red
            $count++
        }
        catch {
            Write-Host "  [FAILED] Could not delete $EntityName '$name' ($id): $_" -ForegroundColor Yellow
        }
    }

    return $count
}

# ---------------------------------------------------------------
# Delete test tickets (must be deleted before categories/subcategories)
# ---------------------------------------------------------------
Write-Host "`nDeleting test tickets..." -ForegroundColor Cyan
$deletedCounts.Tickets = Remove-TestRecords -EntityName "hd_ticket" `
    -FilterField "hd_title" -FilterPattern "[TEST]%"

# ---------------------------------------------------------------
# Delete test SLA profiles
# ---------------------------------------------------------------
Write-Host "`nDeleting test SLA profiles..." -ForegroundColor Cyan
$deletedCounts.SLAProfiles = Remove-TestRecords -EntityName "hd_slaprofile" `
    -FilterField "hd_name" -FilterPattern "[TEST]%"

# ---------------------------------------------------------------
# Delete test subcategories (created by setup.ps1)
# Load record IDs from setup output if available
# ---------------------------------------------------------------
$idsFile = Join-Path $PSScriptRoot "test-record-ids.json"
if (Test-Path $idsFile) {
    Write-Host "`nLoading record IDs from $idsFile..." -ForegroundColor Cyan
    $recordIds = Get-Content $idsFile | ConvertFrom-Json

    Write-Host "`nDeleting test subcategories from ID list..." -ForegroundColor Cyan
    foreach ($id in $recordIds.Subcategories) {
        try {
            Remove-CrmRecord -conn $conn -EntityLogicalName "hd_subcategory" -Id $id
            Write-Host "  [DELETED] hd_subcategory $id" -ForegroundColor Red
            $deletedCounts.Subcategories++
        }
        catch {
            Write-Host "  [SKIPPED] hd_subcategory $id (may not exist): $_" -ForegroundColor Yellow
        }
    }

    Write-Host "`nDeleting test categories from ID list..." -ForegroundColor Cyan
    foreach ($id in $recordIds.Categories) {
        try {
            Remove-CrmRecord -conn $conn -EntityLogicalName "hd_category" -Id $id
            Write-Host "  [DELETED] hd_category $id" -ForegroundColor Red
            $deletedCounts.Categories++
        }
        catch {
            Write-Host "  [SKIPPED] hd_category $id (may not exist or has dependents): $_" -ForegroundColor Yellow
        }
    }

    # Clean up the IDs file
    Remove-Item $idsFile -Force
    Write-Host "`nRemoved $idsFile" -ForegroundColor Yellow
}
else {
    Write-Host "`nNo record IDs file found at $idsFile." -ForegroundColor Yellow
    Write-Host "Subcategories and categories from setup.ps1 were not deleted." -ForegroundColor Yellow
    Write-Host "Run setup.ps1 first to generate the IDs file, or delete them manually." -ForegroundColor Yellow
}

# ---------------------------------------------------------------
# Output summary
# ---------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Teardown Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tickets deleted:       $($deletedCounts.Tickets)"
Write-Host "SLA profiles deleted:  $($deletedCounts.SLAProfiles)"
Write-Host "Subcategories deleted: $($deletedCounts.Subcategories)"
Write-Host "Categories deleted:    $($deletedCounts.Categories)"
