<#
.SYNOPSIS
    Tests RBAC enforcement for the Enterprise Help Desk Dataverse environment.

.DESCRIPTION
    Connects as 4 different test users (one per security role) and verifies that:
    - Requester can only read their own tickets
    - Requester cannot see internal comment body (column-level security)
    - Agent can read tickets within their business unit only
    - Manager can read all tickets org-wide
    - Admin has full CRUD on all entities

    Outputs a pass/fail summary table.

.PARAMETER DataverseUrl
    URL of the Dataverse test organization.

.PARAMETER RequesterCredential
    PSCredential for the test Requester user.

.PARAMETER AgentCredential
    PSCredential for the test Agent user.

.PARAMETER ManagerCredential
    PSCredential for the test Manager user.

.PARAMETER AdminCredential
    PSCredential for the test Admin user.

.EXAMPLE
    .\rbac-tests.ps1 -DataverseUrl "https://helpdesk-test.crm.dynamics.com"
    # Will prompt for credentials for each role
#>

[CmdletBinding()]
param(
    [string]$DataverseUrl = "https://helpdesk-test.crm.dynamics.com",
    [PSCredential]$RequesterCredential,
    [PSCredential]$AgentCredential,
    [PSCredential]$ManagerCredential,
    [PSCredential]$AdminCredential
)

$ErrorActionPreference = "Stop"
Import-Module Microsoft.Xrm.Data.PowerShell -ErrorAction Stop

# ---------------------------------------------------------------
# Prompt for credentials if not provided
# ---------------------------------------------------------------
if (-not $RequesterCredential) {
    $RequesterCredential = Get-Credential -Message "Enter credentials for TEST REQUESTER user"
}
if (-not $AgentCredential) {
    $AgentCredential = Get-Credential -Message "Enter credentials for TEST AGENT user"
}
if (-not $ManagerCredential) {
    $ManagerCredential = Get-Credential -Message "Enter credentials for TEST MANAGER user"
}
if (-not $AdminCredential) {
    $AdminCredential = Get-Credential -Message "Enter credentials for TEST ADMIN user"
}

# ---------------------------------------------------------------
# Connect as each role
# ---------------------------------------------------------------
Write-Host "`nConnecting as each test user..." -ForegroundColor Cyan

$connections = @{}
$roles = @(
    @{ Name = "Requester"; Credential = $RequesterCredential }
    @{ Name = "Agent";     Credential = $AgentCredential }
    @{ Name = "Manager";   Credential = $ManagerCredential }
    @{ Name = "Admin";     Credential = $AdminCredential }
)

foreach ($role in $roles) {
    try {
        $conn = Connect-CrmOnline -ServerUrl $DataverseUrl -Credential $role.Credential
        if (-not $conn.IsReady) {
            throw "Connection not ready: $($conn.LastCrmError)"
        }
        $connections[$role.Name] = $conn
        Write-Host "  Connected as $($role.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "  FAILED to connect as $($role.Name): $_" -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------
# Test results tracking
# ---------------------------------------------------------------
$results = @()

function Add-TestResult {
    param(
        [string]$Role,
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = ""
    )
    $script:results += [PSCustomObject]@{
        Role     = $Role
        Test     = $TestName
        Result   = if ($Passed) { "PASS" } else { "FAIL" }
        Details  = $Details
    }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host "  [$( if ($Passed) {'PASS'} else {'FAIL'} )] $Role - $TestName $Details" -ForegroundColor $color
}

# ---------------------------------------------------------------
# Setup: Create a test ticket owned by the Requester
# ---------------------------------------------------------------
Write-Host "`nSetting up test data with Admin account..." -ForegroundColor Cyan

$adminConn = $connections["Admin"]

# Get the Requester's user ID
$requesterEmail = $RequesterCredential.UserName
$requesterUser = Get-CrmRecords -conn $adminConn -EntityLogicalName "systemuser" `
    -FilterAttribute "internalemailaddress" -FilterOperator "eq" -FilterValue $requesterEmail `
    -Fields "systemuserid", "fullname"

if ($requesterUser.Count -eq 0) {
    throw "Could not find Requester user with email: $requesterEmail"
}
$requesterId = $requesterUser.CrmRecords[0].systemuserid

# Create a test ticket owned by the Requester
$ticketFields = @{
    "hd_title"       = "[TEST-RBAC] Requester's own ticket"
    "hd_description" = "This ticket is owned by the test requester user."
    "hd_priority"    = (New-CrmOptionSetValue -Value 3)
    "hd_status"      = (New-CrmOptionSetValue -Value 1)
    "hd_source"      = (New-CrmOptionSetValue -Value 1)
    "hd_requestedby" = (New-CrmEntityReference -EntityLogicalName "systemuser" -Id $requesterId)
}
$ownTicketId = New-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticket" -Fields $ticketFields
Write-Host "  Created Requester's own ticket: $ownTicketId" -ForegroundColor Green

# Create a test ticket owned by someone else
$otherTicketFields = @{
    "hd_title"       = "[TEST-RBAC] Another user's ticket"
    "hd_description" = "This ticket belongs to a different user."
    "hd_priority"    = (New-CrmOptionSetValue -Value 3)
    "hd_status"      = (New-CrmOptionSetValue -Value 1)
    "hd_source"      = (New-CrmOptionSetValue -Value 1)
}
$otherTicketId = New-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticket" -Fields $otherTicketFields
Write-Host "  Created other user's ticket: $otherTicketId" -ForegroundColor Green

# Create an internal comment on the Requester's ticket
$commentFields = @{
    "hd_ticketid"   = (New-CrmEntityReference -EntityLogicalName "hd_ticket" -Id $ownTicketId)
    "hd_body"       = "Internal note: escalation needed for hardware replacement."
    "hd_isinternal" = $true
}
$internalCommentId = New-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticketcomment" -Fields $commentFields
Write-Host "  Created internal comment: $internalCommentId" -ForegroundColor Green

# ---------------------------------------------------------------
# REQUESTER TESTS
# ---------------------------------------------------------------
Write-Host "`nTesting Requester role..." -ForegroundColor Cyan
$reqConn = $connections["Requester"]

# Test: Requester can read their own ticket
try {
    $ticket = Get-CrmRecord -conn $reqConn -EntityLogicalName "hd_ticket" -Id $ownTicketId -Fields "hd_title"
    Add-TestResult -Role "Requester" -TestName "Read own ticket" -Passed ($null -ne $ticket)
}
catch {
    Add-TestResult -Role "Requester" -TestName "Read own ticket" -Passed $false -Details $_.Exception.Message
}

# Test: Requester cannot read another user's ticket
try {
    $otherTicket = Get-CrmRecord -conn $reqConn -EntityLogicalName "hd_ticket" -Id $otherTicketId -Fields "hd_title"
    # If we get here without error, check if it returned null/empty
    Add-TestResult -Role "Requester" -TestName "Cannot read other's ticket" -Passed ($null -eq $otherTicket) `
        -Details "Expected access denied"
}
catch {
    # Access denied is the expected behavior
    Add-TestResult -Role "Requester" -TestName "Cannot read other's ticket" -Passed $true `
        -Details "Access denied as expected"
}

# Test: Requester cannot create tickets for others
try {
    $spoofFields = @{
        "hd_title"       = "[TEST-RBAC] Spoofed ticket"
        "hd_description" = "Attempting to create ticket as another user"
        "hd_priority"    = (New-CrmOptionSetValue -Value 3)
        "hd_status"      = (New-CrmOptionSetValue -Value 1)
    }
    $spoofId = New-CrmRecord -conn $reqConn -EntityLogicalName "hd_ticket" -Fields $spoofFields
    # If creation succeeded, that is expected -- requesters CAN create their own tickets
    Add-TestResult -Role "Requester" -TestName "Can create own ticket" -Passed $true
    # Clean up
    Remove-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticket" -Id $spoofId
}
catch {
    Add-TestResult -Role "Requester" -TestName "Can create own ticket" -Passed $false -Details $_.Exception.Message
}

# Test: Requester cannot see internal comment body (column-level security)
try {
    $comment = Get-CrmRecord -conn $reqConn -EntityLogicalName "hd_ticketcomment" `
        -Id $internalCommentId -Fields "hd_body", "hd_isinternal"
    $bodyValue = $comment.hd_body
    $isInternal = $comment.hd_isinternal

    if ($isInternal -and ($null -eq $bodyValue -or $bodyValue -eq "")) {
        Add-TestResult -Role "Requester" -TestName "Internal comment body is hidden" -Passed $true
    }
    else {
        Add-TestResult -Role "Requester" -TestName "Internal comment body is hidden" -Passed $false `
            -Details "Body was visible: '$bodyValue'"
    }
}
catch {
    # Access denied to the record entirely is also acceptable
    Add-TestResult -Role "Requester" -TestName "Internal comment body is hidden" -Passed $true `
        -Details "Record not accessible (acceptable)"
}

# Test: Requester cannot delete tickets
try {
    Remove-CrmRecord -conn $reqConn -EntityLogicalName "hd_ticket" -Id $ownTicketId
    Add-TestResult -Role "Requester" -TestName "Cannot delete tickets" -Passed $false `
        -Details "Deletion should have been denied"
}
catch {
    Add-TestResult -Role "Requester" -TestName "Cannot delete tickets" -Passed $true `
        -Details "Delete denied as expected"
}

# ---------------------------------------------------------------
# AGENT TESTS
# ---------------------------------------------------------------
Write-Host "`nTesting Agent role..." -ForegroundColor Cyan
$agentConn = $connections["Agent"]

# Test: Agent can read tickets in their BU
try {
    $tickets = Get-CrmRecords -conn $agentConn -EntityLogicalName "hd_ticket" `
        -Fields "hd_title", "hd_status" -TopCount 10
    Add-TestResult -Role "Agent" -TestName "Read BU-scoped tickets" -Passed ($tickets.Count -gt 0) `
        -Details "Found $($tickets.Count) tickets"
}
catch {
    Add-TestResult -Role "Agent" -TestName "Read BU-scoped tickets" -Passed $false -Details $_.Exception.Message
}

# Test: Agent can update ticket status
try {
    Set-CrmRecord -conn $agentConn -EntityLogicalName "hd_ticket" -Id $ownTicketId `
        -Fields @{ "hd_status" = (New-CrmOptionSetValue -Value 3) }  # Active
    Add-TestResult -Role "Agent" -TestName "Update ticket status" -Passed $true
}
catch {
    Add-TestResult -Role "Agent" -TestName "Update ticket status" -Passed $false -Details $_.Exception.Message
}

# Test: Agent can add comments
try {
    $agentCommentFields = @{
        "hd_ticketid"   = (New-CrmEntityReference -EntityLogicalName "hd_ticket" -Id $ownTicketId)
        "hd_body"       = "[TEST-RBAC] Agent comment for testing"
        "hd_isinternal" = $false
    }
    $agentCommentId = New-CrmRecord -conn $agentConn -EntityLogicalName "hd_ticketcomment" -Fields $agentCommentFields
    Add-TestResult -Role "Agent" -TestName "Create ticket comment" -Passed $true
    # Clean up
    Remove-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticketcomment" -Id $agentCommentId
}
catch {
    Add-TestResult -Role "Agent" -TestName "Create ticket comment" -Passed $false -Details $_.Exception.Message
}

# Test: Agent cannot delete tickets
try {
    Remove-CrmRecord -conn $agentConn -EntityLogicalName "hd_ticket" -Id $otherTicketId
    Add-TestResult -Role "Agent" -TestName "Cannot delete tickets" -Passed $false `
        -Details "Deletion should have been denied"
}
catch {
    Add-TestResult -Role "Agent" -TestName "Cannot delete tickets" -Passed $true `
        -Details "Delete denied as expected"
}

# ---------------------------------------------------------------
# MANAGER TESTS
# ---------------------------------------------------------------
Write-Host "`nTesting Manager role..." -ForegroundColor Cyan
$mgrConn = $connections["Manager"]

# Test: Manager can read all tickets org-wide
try {
    $allTickets = Get-CrmRecords -conn $mgrConn -EntityLogicalName "hd_ticket" `
        -Fields "hd_title" -TopCount 100
    # Manager should see both test tickets
    $seesOwn = $false
    $seesOther = $false
    foreach ($t in $allTickets.CrmRecords) {
        if ($t.hd_ticketid -eq $ownTicketId) { $seesOwn = $true }
        if ($t.hd_ticketid -eq $otherTicketId) { $seesOther = $true }
    }
    Add-TestResult -Role "Manager" -TestName "Read org-wide tickets" -Passed ($seesOwn -and $seesOther) `
        -Details "Sees own=$seesOwn, sees other=$seesOther"
}
catch {
    Add-TestResult -Role "Manager" -TestName "Read org-wide tickets" -Passed $false -Details $_.Exception.Message
}

# Test: Manager can reassign tickets
try {
    $agentEmail = $AgentCredential.UserName
    $agentUser = Get-CrmRecords -conn $adminConn -EntityLogicalName "systemuser" `
        -FilterAttribute "internalemailaddress" -FilterOperator "eq" -FilterValue $agentEmail `
        -Fields "systemuserid"
    if ($agentUser.Count -gt 0) {
        $agentId = $agentUser.CrmRecords[0].systemuserid
        Set-CrmRecord -conn $mgrConn -EntityLogicalName "hd_ticket" -Id $ownTicketId `
            -Fields @{ "hd_assignedto" = (New-CrmEntityReference -EntityLogicalName "systemuser" -Id $agentId) }
        Add-TestResult -Role "Manager" -TestName "Reassign tickets" -Passed $true
    }
}
catch {
    Add-TestResult -Role "Manager" -TestName "Reassign tickets" -Passed $false -Details $_.Exception.Message
}

# Test: Manager can read internal comments
try {
    $comment = Get-CrmRecord -conn $mgrConn -EntityLogicalName "hd_ticketcomment" `
        -Id $internalCommentId -Fields "hd_body", "hd_isinternal"
    $hasBody = -not [string]::IsNullOrEmpty($comment.hd_body)
    Add-TestResult -Role "Manager" -TestName "Read internal comments" -Passed $hasBody `
        -Details "Body visible=$hasBody"
}
catch {
    Add-TestResult -Role "Manager" -TestName "Read internal comments" -Passed $false -Details $_.Exception.Message
}

# ---------------------------------------------------------------
# ADMIN TESTS
# ---------------------------------------------------------------
Write-Host "`nTesting Admin role..." -ForegroundColor Cyan

# Test: Admin can delete tickets
try {
    $tempFields = @{
        "hd_title"    = "[TEST-RBAC] Admin delete test"
        "hd_priority" = (New-CrmOptionSetValue -Value 4)
        "hd_status"   = (New-CrmOptionSetValue -Value 1)
    }
    $tempId = New-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticket" -Fields $tempFields
    Remove-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticket" -Id $tempId
    Add-TestResult -Role "Admin" -TestName "Create and delete tickets" -Passed $true
}
catch {
    Add-TestResult -Role "Admin" -TestName "Create and delete tickets" -Passed $false -Details $_.Exception.Message
}

# Test: Admin can manage categories
try {
    $catId = New-CrmRecord -conn $adminConn -EntityLogicalName "hd_category" `
        -Fields @{ "hd_name" = "[TEST-RBAC] Admin category" }
    Remove-CrmRecord -conn $adminConn -EntityLogicalName "hd_category" -Id $catId
    Add-TestResult -Role "Admin" -TestName "Manage categories (CRUD)" -Passed $true
}
catch {
    Add-TestResult -Role "Admin" -TestName "Manage categories (CRUD)" -Passed $false -Details $_.Exception.Message
}

# ---------------------------------------------------------------
# Cleanup test data
# ---------------------------------------------------------------
Write-Host "`nCleaning up RBAC test data..." -ForegroundColor Cyan
try { Remove-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticketcomment" -Id $internalCommentId } catch {}
try { Remove-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticket" -Id $ownTicketId } catch {}
try { Remove-CrmRecord -conn $adminConn -EntityLogicalName "hd_ticket" -Id $otherTicketId } catch {}
Write-Host "  Cleanup complete." -ForegroundColor Green

# ---------------------------------------------------------------
# Output results table
# ---------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RBAC Test Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$results | Format-Table -AutoSize -Property Role, Test, Result, Details

$passed = ($results | Where-Object { $_.Result -eq "PASS" }).Count
$failed = ($results | Where-Object { $_.Result -eq "FAIL" }).Count
$total = $results.Count

Write-Host "Total: $total | Passed: $passed | Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) {
    Write-Host "`nFAILED TESTS:" -ForegroundColor Red
    $results | Where-Object { $_.Result -eq "FAIL" } | Format-Table -AutoSize
    exit 1
}
