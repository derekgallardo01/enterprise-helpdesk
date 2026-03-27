<#
.SYNOPSIS
    Sets up test data in the Dataverse test environment for integration testing.

.DESCRIPTION
    Connects to the Dataverse test organization and creates:
    - Test categories and subcategories (if not already present)
    - Test SLA profiles
    - 10 test tickets with [TEST] prefix across different categories, statuses, and priorities

    All created record IDs are output for use in teardown.

.PARAMETER DataverseUrl
    URL of the Dataverse test organization. Default: https://helpdesk-test.crm.dynamics.com

.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -DataverseUrl "https://helpdesk-dev.crm.dynamics.com"
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

$createdIds = @{
    Categories    = @()
    Subcategories = @()
    SLAProfiles   = @()
    Tickets       = @()
}

# ---------------------------------------------------------------
# Helper: Create record if not exists (by name)
# ---------------------------------------------------------------
function New-RecordIfNotExists {
    param(
        [string]$EntityName,
        [string]$NameField,
        [string]$NameValue,
        [hashtable]$AdditionalFields = @{}
    )

    $existing = Get-CrmRecords -conn $conn -EntityLogicalName $EntityName `
        -FilterAttribute $NameField -FilterOperator "eq" -FilterValue $NameValue `
        -Fields $NameField

    if ($existing.Count -gt 0) {
        Write-Host "  [EXISTS] $EntityName '$NameValue' already exists." -ForegroundColor Yellow
        return $existing.CrmRecords[0].($EntityName + "id")
    }

    $fields = @{ $NameField = $NameValue } + $AdditionalFields
    $id = New-CrmRecord -conn $conn -EntityLogicalName $EntityName -Fields $fields
    Write-Host "  [CREATED] $EntityName '$NameValue' -> $id" -ForegroundColor Green
    return $id
}

# ---------------------------------------------------------------
# Create test categories
# ---------------------------------------------------------------
Write-Host "`nCreating test categories..." -ForegroundColor Cyan

$categories = @(
    @{ Name = "Hardware"; Description = "Hardware-related issues" }
    @{ Name = "Software"; Description = "Software installation and configuration" }
    @{ Name = "Network"; Description = "Network and connectivity issues" }
    @{ Name = "Access"; Description = "Account and permission issues" }
    @{ Name = "Email"; Description = "Email and calendar issues" }
)

$categoryIds = @{}
foreach ($cat in $categories) {
    $id = New-RecordIfNotExists -EntityName "hd_category" -NameField "hd_name" -NameValue $cat.Name `
        -AdditionalFields @{ "hd_description" = $cat.Description }
    $categoryIds[$cat.Name] = $id
    $createdIds.Categories += $id
}

# ---------------------------------------------------------------
# Create test subcategories
# ---------------------------------------------------------------
Write-Host "`nCreating test subcategories..." -ForegroundColor Cyan

$subcategories = @(
    @{ Name = "Laptop"; Category = "Hardware" }
    @{ Name = "Monitor"; Category = "Hardware" }
    @{ Name = "Installation"; Category = "Software" }
    @{ Name = "License"; Category = "Software" }
    @{ Name = "VPN"; Category = "Network" }
    @{ Name = "WiFi"; Category = "Network" }
    @{ Name = "Password Reset"; Category = "Access" }
    @{ Name = "Permissions"; Category = "Access" }
    @{ Name = "Outlook"; Category = "Email" }
    @{ Name = "Shared Mailbox"; Category = "Email" }
)

$subcategoryIds = @{}
foreach ($sub in $subcategories) {
    $catRef = New-CrmEntityReference -EntityLogicalName "hd_category" -Id $categoryIds[$sub.Category]
    $id = New-RecordIfNotExists -EntityName "hd_subcategory" -NameField "hd_name" -NameValue $sub.Name `
        -AdditionalFields @{ "hd_category" = $catRef }
    $subcategoryIds[$sub.Name] = $id
    $createdIds.Subcategories += $id
}

# ---------------------------------------------------------------
# Create test SLA profiles
# ---------------------------------------------------------------
Write-Host "`nCreating test SLA profiles..." -ForegroundColor Cyan

$slaProfiles = @(
    @{ Name = "[TEST] Critical SLA";  ResponseHours = 1;  ResolutionHours = 4;  Priority = 1 }
    @{ Name = "[TEST] High SLA";      ResponseHours = 4;  ResolutionHours = 8;  Priority = 2 }
    @{ Name = "[TEST] Medium SLA";    ResponseHours = 8;  ResolutionHours = 24; Priority = 3 }
    @{ Name = "[TEST] Low SLA";       ResponseHours = 24; ResolutionHours = 72; Priority = 4 }
)

foreach ($sla in $slaProfiles) {
    $id = New-RecordIfNotExists -EntityName "hd_slaprofile" -NameField "hd_name" -NameValue $sla.Name `
        -AdditionalFields @{
            "hd_responsehours"   = $sla.ResponseHours
            "hd_resolutionhours" = $sla.ResolutionHours
            "hd_priority"        = (New-CrmOptionSetValue -Value $sla.Priority)
        }
    $createdIds.SLAProfiles += $id
}

# ---------------------------------------------------------------
# Create 10 test tickets
# ---------------------------------------------------------------
Write-Host "`nCreating 10 test tickets..." -ForegroundColor Cyan

$testTickets = @(
    @{
        Title       = "[TEST] Laptop screen flickering intermittently"
        Description = "Screen flickers every few minutes. Started after last Windows update."
        Category    = "Hardware"; Subcategory = "Laptop"
        Priority    = 3; Status = 1  # Medium, New
    }
    @{
        Title       = "[TEST] Cannot connect to VPN from home office"
        Description = "VPN client shows 'connection timed out' error since Monday morning."
        Category    = "Network"; Subcategory = "VPN"
        Priority    = 2; Status = 3  # High, Active
    }
    @{
        Title       = "[TEST] Password expired - account locked out"
        Description = "My account is locked. I cannot log in to any systems."
        Category    = "Access"; Subcategory = "Password Reset"
        Priority    = 1; Status = 3  # Critical, Active
    }
    @{
        Title       = "[TEST] Need Adobe Acrobat Pro license"
        Description = "Requesting license for Adobe Acrobat Pro for PDF editing work."
        Category    = "Software"; Subcategory = "License"
        Priority    = 4; Status = 1  # Low, New
    }
    @{
        Title       = "[TEST] Outlook keeps crashing on startup"
        Description = "Outlook crashes immediately after opening. Have tried repairing Office."
        Category    = "Email"; Subcategory = "Outlook"
        Priority    = 2; Status = 6  # High, Resolved
    }
    @{
        Title       = "[TEST] External monitor not detected after docking"
        Description = "Plugging into docking station no longer detects the external monitor."
        Category    = "Hardware"; Subcategory = "Monitor"
        Priority    = 3; Status = 1  # Medium, New
    }
    @{
        Title       = "[TEST] WiFi drops every 15 minutes in Building C"
        Description = "Multiple users in Building C 3rd floor experiencing WiFi disconnections."
        Category    = "Network"; Subcategory = "WiFi"
        Priority    = 2; Status = 3  # High, Active
    }
    @{
        Title       = "[TEST] Need access to SharePoint HR site"
        Description = "I need read access to the HR SharePoint site for benefits enrollment."
        Category    = "Access"; Subcategory = "Permissions"
        Priority    = 3; Status = 7  # Medium, Closed
    }
    @{
        Title       = "[TEST] Software installation request - Visual Studio"
        Description = "Need Visual Studio 2025 Enterprise installed on my development machine."
        Category    = "Software"; Subcategory = "Installation"
        Priority    = 3; Status = 1  # Medium, New
    }
    @{
        Title       = "[TEST] Shared mailbox not receiving external emails"
        Description = "The sales@contoso.com shared mailbox stopped receiving external emails yesterday."
        Category    = "Email"; Subcategory = "Shared Mailbox"
        Priority    = 1; Status = 3  # Critical, Active
    }
)

foreach ($ticket in $testTickets) {
    $catRef = New-CrmEntityReference -EntityLogicalName "hd_category" -Id $categoryIds[$ticket.Category]
    $subRef = New-CrmEntityReference -EntityLogicalName "hd_subcategory" -Id $subcategoryIds[$ticket.Subcategory]

    $fields = @{
        "hd_title"       = $ticket.Title
        "hd_description" = $ticket.Description
        "hd_category"    = $catRef
        "hd_subcategory" = $subRef
        "hd_priority"    = (New-CrmOptionSetValue -Value $ticket.Priority)
        "hd_status"      = (New-CrmOptionSetValue -Value $ticket.Status)
        "hd_source"      = (New-CrmOptionSetValue -Value 1)  # Portal
    }

    $id = New-CrmRecord -conn $conn -EntityLogicalName "hd_ticket" -Fields $fields
    Write-Host "  [CREATED] Ticket '$($ticket.Title)' -> $id" -ForegroundColor Green
    $createdIds.Tickets += $id
}

# ---------------------------------------------------------------
# Output summary
# ---------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Setup Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Categories created:    $($createdIds.Categories.Count)"
Write-Host "Subcategories created: $($createdIds.Subcategories.Count)"
Write-Host "SLA profiles created:  $($createdIds.SLAProfiles.Count)"
Write-Host "Tickets created:       $($createdIds.Tickets.Count)"

# Export IDs for teardown
$outputPath = Join-Path $PSScriptRoot "test-record-ids.json"
$createdIds | ConvertTo-Json -Depth 3 | Out-File -FilePath $outputPath -Encoding utf8
Write-Host "`nRecord IDs saved to: $outputPath" -ForegroundColor Yellow
Write-Host "Run teardown.ps1 to clean up test data." -ForegroundColor Yellow
