<#
.SYNOPSIS
    Generates 1,000 realistic test tickets in Dataverse for load/UAT testing.

.DESCRIPTION
    Creates 1,000 tickets with:
    - Random distribution across categories, priorities, and statuses
    - Realistic date ranges (last 90 days)
    - Some with SLA breaches, some resolved, some with satisfaction ratings
    - 3-5 comments per ticket

    Run this script against a TEST environment only. All tickets are prefixed
    with [SEED] for easy identification and bulk deletion.

.PARAMETER DataverseUrl
    URL of the Dataverse test organization.

.PARAMETER TicketCount
    Number of tickets to generate. Default: 1000.

.EXAMPLE
    .\generate-test-tickets.ps1
    .\generate-test-tickets.ps1 -TicketCount 500 -DataverseUrl "https://helpdesk-dev.crm.dynamics.com"
#>

[CmdletBinding()]
param(
    [string]$DataverseUrl = "https://helpdesk-test.crm.dynamics.com",
    [int]$TicketCount = 1000
)

$ErrorActionPreference = "Stop"
Import-Module Microsoft.Xrm.Data.PowerShell -ErrorAction Stop

# ---------------------------------------------------------------
# Connect to Dataverse
# ---------------------------------------------------------------
Write-Host "Connecting to Dataverse at $DataverseUrl..." -ForegroundColor Cyan
$conn = Connect-CrmOnline -ServerUrl $DataverseUrl -ForceOAuth
if (-not $conn.IsReady) {
    throw "Failed to connect to Dataverse: $($conn.LastCrmError)"
}
Write-Host "Connected successfully." -ForegroundColor Green

# ---------------------------------------------------------------
# Lookup existing categories, subcategories, and agents
# ---------------------------------------------------------------
Write-Host "Loading reference data..." -ForegroundColor Cyan

$categories = Get-CrmRecords -conn $conn -EntityLogicalName "hd_category" `
    -Fields "hd_categoryid", "hd_name" -TopCount 50
$categoryList = $categories.CrmRecords
Write-Host "  Found $($categoryList.Count) categories"

$subcategories = Get-CrmRecords -conn $conn -EntityLogicalName "hd_subcategory" `
    -Fields "hd_subcategoryid", "hd_name", "hd_category" -TopCount 200
$subcategoryList = $subcategories.CrmRecords
Write-Host "  Found $($subcategoryList.Count) subcategories"

# Build category -> subcategories map
$catSubMap = @{}
foreach ($sub in $subcategoryList) {
    $catId = $sub.hd_category_Property.Value.Id.ToString()
    if (-not $catSubMap.ContainsKey($catId)) {
        $catSubMap[$catId] = @()
    }
    $catSubMap[$catId] += $sub
}

# Get agents for assignment
$agentFetch = @"
<fetch top="50">
    <entity name="systemuser">
        <attribute name="systemuserid" />
        <attribute name="fullname" />
        <link-entity name="systemuserroles" from="systemuserid" to="systemuserid" link-type="inner">
            <link-entity name="role" from="roleid" to="roleid" link-type="inner">
                <filter>
                    <condition attribute="name" operator="like" value="%Help Desk%" />
                </filter>
            </link-entity>
        </link-entity>
    </entity>
</fetch>
"@
$agents = Get-CrmRecordsByFetch -conn $conn -Fetch $agentFetch
$agentList = $agents.CrmRecords
Write-Host "  Found $($agentList.Count) agents"

if ($categoryList.Count -eq 0) {
    throw "No categories found. Run integration/setup.ps1 first."
}
if ($agentList.Count -eq 0) {
    Write-Host "  WARNING: No agents found. Tickets will not be assigned." -ForegroundColor Yellow
}

# ---------------------------------------------------------------
# Seed data arrays
# ---------------------------------------------------------------
$titleTemplates = @(
    "[SEED] Cannot connect to {0}"
    "[SEED] {0} not working after update"
    "[SEED] Need access to {0}"
    "[SEED] {0} performance is slow"
    "[SEED] Error when using {0}"
    "[SEED] Request for new {0}"
    "[SEED] {0} license renewal needed"
    "[SEED] {0} configuration change request"
    "[SEED] Intermittent {0} issue"
    "[SEED] {0} outage reported"
    "[SEED] Unable to install {0}"
    "[SEED] {0} permissions request"
    "[SEED] {0} password reset needed"
    "[SEED] {0} training request"
    "[SEED] {0} hardware replacement"
)

$subjects = @(
    "VPN", "WiFi", "Outlook", "SharePoint", "Teams", "OneDrive",
    "Laptop", "Monitor", "Printer", "Phone", "Adobe Acrobat",
    "Visual Studio", "Power BI", "Azure DevOps", "SAP", "Salesforce",
    "Active Directory", "MFA", "Badge Access", "Conference Room Equipment"
)

$descriptionTemplates = @(
    "User reports issues with {0}. The problem started {1} and occurs {2}."
    "Multiple users in {3} are experiencing {0} problems. This is affecting {4} people."
    "Requesting {0} for {5}. Business justification: {6}."
    "After the latest update, {0} is no longer functioning correctly. Error: {7}."
    "{0} has been unreliable since {1}. Tried basic troubleshooting without success."
)

$timeframes = @("yesterday", "last Monday", "two days ago", "this morning", "last week", "after the maintenance window")
$frequencies = @("intermittently", "constantly", "every few hours", "only in the morning", "when connected to VPN")
$locations = @("Building A", "Building B 3rd floor", "the remote office", "the Seattle campus", "the finance department")
$peopleCounts = @("3", "5", "10", "the entire team", "about 20")
$roles = @("a new team member", "the marketing team", "my department", "a contractor", "the executive assistant")
$justifications = @("project deadline", "compliance requirement", "client presentation", "quarterly reporting", "new hire onboarding")
$errors = @("Error 500", "Access Denied", "Timeout", "Connection refused", "License expired", "File not found")

$commentTemplates = @(
    "Thank you for reporting this issue. We are looking into it."
    "I have escalated this to the {0} team for further investigation."
    "Could you please provide more details about when this issue occurs?"
    "We have identified the root cause. A fix is being deployed."
    "This issue has been resolved. Please confirm if everything is working."
    "Temporary workaround: {1}. A permanent fix is in progress."
    "Similar issue was reported by another user. Linking tickets for tracking."
    "Scheduled maintenance window for this fix: {2}."
    "Applied the fix. Monitoring for 24 hours before closing."
    "User confirmed the issue is resolved. Closing ticket."
)

$teams = @("Network", "Desktop Support", "Application Support", "Security", "Infrastructure", "Cloud Services")
$workarounds = @("restart the application", "clear browser cache", "use the web version", "connect via ethernet", "use an alternate printer")
$maintenanceWindows = @("tonight 10pm-12am", "this Saturday 6am-8am", "next Tuesday during lunch", "this weekend")

# ---------------------------------------------------------------
# Probability distributions
# ---------------------------------------------------------------
# Priority: 5% Critical, 15% High, 50% Medium, 30% Low
function Get-RandomPriority {
    $r = Get-Random -Minimum 0 -Maximum 100
    if ($r -lt 5) { return 1 }       # Critical
    if ($r -lt 20) { return 2 }      # High
    if ($r -lt 70) { return 3 }      # Medium
    return 4                          # Low
}

# Status: 20% New, 30% Active, 5% Pending, 25% Resolved, 15% Closed, 5% Cancelled
function Get-RandomStatus {
    $r = Get-Random -Minimum 0 -Maximum 100
    if ($r -lt 20) { return 1 }      # New
    if ($r -lt 50) { return 3 }      # Active
    if ($r -lt 55) { return 4 }      # Pending
    if ($r -lt 80) { return 6 }      # Resolved
    if ($r -lt 95) { return 7 }      # Closed
    return 8                          # Cancelled
}

# Source: 40% Portal, 30% Email, 15% Teams, 10% Phone, 5% Walk-up
function Get-RandomSource {
    $r = Get-Random -Minimum 0 -Maximum 100
    if ($r -lt 40) { return 1 }
    if ($r -lt 70) { return 2 }
    if ($r -lt 85) { return 3 }
    if ($r -lt 95) { return 4 }
    return 5
}

function Get-RandomItem($array) {
    return $array[(Get-Random -Minimum 0 -Maximum $array.Count)]
}

function Get-RandomDate {
    param([int]$DaysBack = 90)
    $daysAgo = Get-Random -Minimum 0 -Maximum $DaysBack
    $hoursAgo = Get-Random -Minimum 0 -Maximum 24
    return (Get-Date).AddDays(-$daysAgo).AddHours(-$hoursAgo).ToUniversalTime()
}

# ---------------------------------------------------------------
# Generate tickets
# ---------------------------------------------------------------
Write-Host "`nGenerating $TicketCount test tickets..." -ForegroundColor Cyan
$startTime = Get-Date
$createdCount = 0
$errorCount = 0

for ($i = 1; $i -le $TicketCount; $i++) {
    try {
        # Pick random category and matching subcategory
        $cat = Get-RandomItem $categoryList
        $catId = $cat.hd_categoryid
        $catSubs = $catSubMap[$catId.ToString()]
        $sub = if ($catSubs -and $catSubs.Count -gt 0) { Get-RandomItem $catSubs } else { $null }

        $subject = Get-RandomItem $subjects
        $title = (Get-RandomItem $titleTemplates) -f $subject
        $description = (Get-RandomItem $descriptionTemplates) -f $subject, `
            (Get-RandomItem $timeframes), (Get-RandomItem $frequencies), `
            (Get-RandomItem $locations), (Get-RandomItem $peopleCounts), `
            (Get-RandomItem $roles), (Get-RandomItem $justifications), `
            (Get-RandomItem $errors)

        $priority = Get-RandomPriority
        $status = Get-RandomStatus
        $source = Get-RandomSource
        $createdOn = Get-RandomDate -DaysBack 90

        # SLA breach: 15% of tickets
        $slaBreach = (Get-Random -Minimum 0 -Maximum 100) -lt 15

        # Satisfaction rating for resolved/closed tickets: 70% have one
        $satisfactionRating = $null
        if ($status -in @(6, 7) -and (Get-Random -Minimum 0 -Maximum 100) -lt 70) {
            # Weighted: mostly 4-5, some 3, few 1-2
            $r = Get-Random -Minimum 0 -Maximum 100
            if ($r -lt 5) { $satisfactionRating = 1 }
            elseif ($r -lt 15) { $satisfactionRating = 2 }
            elseif ($r -lt 30) { $satisfactionRating = 3 }
            elseif ($r -lt 60) { $satisfactionRating = 4 }
            else { $satisfactionRating = 5 }
        }

        # Build ticket fields
        $fields = @{
            "hd_title"       = $title
            "hd_description" = $description
            "hd_category"    = (New-CrmEntityReference -EntityLogicalName "hd_category" -Id $catId)
            "hd_priority"    = (New-CrmOptionSetValue -Value $priority)
            "hd_status"      = (New-CrmOptionSetValue -Value $status)
            "hd_source"      = (New-CrmOptionSetValue -Value $source)
            "hd_slabreach"   = $slaBreach
        }

        if ($sub) {
            $fields["hd_subcategory"] = New-CrmEntityReference -EntityLogicalName "hd_subcategory" -Id $sub.hd_subcategoryid
        }

        if ($agentList.Count -gt 0) {
            $agent = Get-RandomItem $agentList
            $fields["hd_assignedto"] = New-CrmEntityReference -EntityLogicalName "systemuser" -Id $agent.systemuserid
        }

        if ($satisfactionRating) {
            $fields["hd_satisfactionrating"] = $satisfactionRating
        }

        # Resolution date for resolved/closed tickets
        if ($status -in @(6, 7)) {
            $resMinutes = Get-Random -Minimum 30 -Maximum 4320  # 30 min to 3 days
            $fields["hd_resolutiondate"] = $createdOn.AddMinutes($resMinutes)
        }

        # First response (80% of non-new tickets)
        if ($status -ne 1 -and (Get-Random -Minimum 0 -Maximum 100) -lt 80) {
            $responseMinutes = Get-Random -Minimum 5 -Maximum 480  # 5 min to 8 hours
            $fields["hd_firstresponseat"] = $createdOn.AddMinutes($responseMinutes)
        }

        # Due date (based on priority SLA)
        $slaHours = switch ($priority) { 1 { 4 } 2 { 8 } 3 { 24 } 4 { 72 } }
        $fields["hd_duedate"] = $createdOn.AddHours($slaHours)

        # Create the ticket
        $ticketId = New-CrmRecord -conn $conn -EntityLogicalName "hd_ticket" -Fields $fields

        # Add 3-5 comments per ticket
        $commentCount = Get-Random -Minimum 3 -Maximum 6
        for ($c = 1; $c -le $commentCount; $c++) {
            $commentBody = (Get-RandomItem $commentTemplates) -f `
                (Get-RandomItem $teams), (Get-RandomItem $workarounds), (Get-RandomItem $maintenanceWindows)

            $isInternal = (Get-Random -Minimum 0 -Maximum 100) -lt 30  # 30% internal

            $commentFields = @{
                "hd_ticketid"   = (New-CrmEntityReference -EntityLogicalName "hd_ticket" -Id $ticketId)
                "hd_body"       = $commentBody
                "hd_isinternal" = $isInternal
            }

            New-CrmRecord -conn $conn -EntityLogicalName "hd_ticketcomment" -Fields $commentFields | Out-Null
        }

        $createdCount++

        # Progress indicator
        if ($createdCount % 50 -eq 0) {
            $elapsed = (Get-Date) - $startTime
            $rate = [math]::Round($createdCount / $elapsed.TotalMinutes, 1)
            Write-Host "  Created $createdCount / $TicketCount tickets ($rate/min)..." -ForegroundColor Gray
        }
    }
    catch {
        $errorCount++
        Write-Host "  ERROR creating ticket $i : $_" -ForegroundColor Red
        if ($errorCount -gt 50) {
            throw "Too many errors ($errorCount). Aborting."
        }
    }
}

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
$elapsed = (Get-Date) - $startTime
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Seed Data Generation Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tickets created:  $createdCount"
Write-Host "Errors:           $errorCount"
Write-Host "Duration:         $([math]::Round($elapsed.TotalMinutes, 1)) minutes"
Write-Host "Rate:             $([math]::Round($createdCount / $elapsed.TotalMinutes, 1)) tickets/min"
Write-Host "`nAll tickets prefixed with [SEED] for easy cleanup."
Write-Host "To delete: Remove all hd_ticket where hd_title LIKE '[SEED]%'"
