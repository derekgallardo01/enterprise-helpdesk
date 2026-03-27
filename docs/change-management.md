# Enterprise Help Desk — Change Management Process

## Overview

This document defines the change management process for the Enterprise Help Desk system. All changes to production — whether Dataverse schema updates, Power Automate flows, SPFx deployments, Azure Functions, or Power BI reports — follow a structured process to minimize risk and ensure traceability.

**Guiding principle**: No untracked changes in production. Every change is requested, reviewed, approved, tested, and documented.

## 1. Change Categories

| Category | Approval | Lead Time | Examples |
|---|---|---|---|
| **Standard** (pre-approved) | No CAB required | Same day | SPFx bug fix (patch version), Power Automate flow parameter tweak, Power BI report filter change, KB article update |
| **Normal** (CAB approval) | CAB vote required | 1-2 weeks | New Power Automate flow, Dataverse schema change (new column/table), new security role, Azure Function code change, new SPFx web part |
| **Emergency** (expedited) | Incident commander + 1 CAB member | Immediate | Production outage fix, security vulnerability patch, data corruption remediation |

### Standard Change Criteria

A change qualifies as Standard only if **all** of the following are true:
- The change type has been pre-approved by the CAB (listed in the Standard Change Catalog)
- The change has been successfully performed at least once before
- The change has a documented, tested rollback procedure
- The change affects no security roles, no schema, and no integrations
- Estimated risk: Low

### Emergency Change Criteria

A change qualifies as Emergency only if **any** of the following are true:
- Production system is down or severely degraded
- Active security vulnerability is being exploited
- Data integrity is compromised
- Regulatory compliance is at immediate risk

Emergency changes still require documentation — but the documentation can be completed within 48 hours **after** the change is implemented.

## 2. Change Advisory Board (CAB)

### Members

| Role | Responsibility | Veto Power |
|---|---|---|
| **IT Manager** | Business impact assessment, resource allocation | No |
| **Platform Admin** | Technical feasibility, implementation oversight | No |
| **Security Lead** | Security and compliance review | **Yes** — on any security-impacting change |
| **Business Owner** | User impact assessment, communication approval | No |

### Meeting Cadence

| Meeting | Schedule | Duration | Purpose |
|---|---|---|---|
| Weekly CAB | Tuesdays, 10:00 AM (local time) | 30 minutes | Review and vote on Normal change requests |
| Emergency CAB | As needed (Teams call) | 15 minutes | Approve/reject emergency changes |
| Monthly CAB Review | First Tuesday of month | 60 minutes | Review change metrics, post-implementation reviews, process improvements |

### Quorum and Voting

- **Quorum**: 3 of 4 members (or their designated delegates)
- **Decision**: Majority vote approves the change
- **Security veto**: Security Lead can veto any change that introduces security risk. Veto can be overridden only by IT Manager + Business Owner jointly, with documented risk acceptance.
- **Tie-breaking**: IT Manager casts the deciding vote
- **Absent members**: Must submit written vote (email or Teams message) before the meeting, or delegate authority

## 3. Change Request Template

Every Normal and Emergency change requires a Change Request (CR) record. Tracked in Dataverse as a ticket with `hd_category = Change Management`.

```
================================================================
CHANGE REQUEST
================================================================

CR ID:          CR-{SEQNUM:4}  (auto-generated)
Title:          [Brief description of the change]
Requestor:      [Name and role]
Date Submitted: [YYYY-MM-DD]
Category:       [ ] Standard  [ ] Normal  [ ] Emergency
Target Date:    [YYYY-MM-DD]

----------------------------------------------------------------
1. DESCRIPTION OF CHANGE
----------------------------------------------------------------
[What is being changed, in which component(s), and how]

----------------------------------------------------------------
2. BUSINESS JUSTIFICATION
----------------------------------------------------------------
[Why this change is needed — link to a ticket, user request, or
 business requirement]

----------------------------------------------------------------
3. IMPACT ASSESSMENT
----------------------------------------------------------------
Users Affected:     [ ] None  [ ] Agents only  [ ] All users
Downtime Expected:  [ ] None  [ ] <5 min  [ ] 5-30 min  [ ] >30 min
Components Changed: [ ] Dataverse  [ ] Power Automate  [ ] SPFx
                    [ ] Azure Functions  [ ] Azure SQL  [ ] Power BI
                    [ ] SharePoint  [ ] Security Roles  [ ] Other

----------------------------------------------------------------
4. RISK ASSESSMENT
----------------------------------------------------------------
Risk Level:     [ ] Low  [ ] Medium  [ ] High
Risk Factors:   [List specific risks]
Mitigations:    [How risks are addressed]

----------------------------------------------------------------
5. IMPLEMENTATION PLAN
----------------------------------------------------------------
Step 1: [Action] — [Who] — [Estimated time]
Step 2: [Action] — [Who] — [Estimated time]
Step 3: [Action] — [Who] — [Estimated time]
...
Total estimated duration: [X minutes/hours]

----------------------------------------------------------------
6. ROLLBACK PLAN
----------------------------------------------------------------
Trigger:    [What condition triggers rollback]
Step 1:     [Rollback action]
Step 2:     [Rollback action]
Estimated rollback time: [X minutes]

----------------------------------------------------------------
7. TESTING COMPLETED
----------------------------------------------------------------
[ ] Unit testing in Dev environment
[ ] Integration testing in Test environment
[ ] UAT sign-off from business user
[ ] Security review (if security-impacting)
[ ] Performance testing (if performance-impacting)
[ ] Rollback tested in Test environment

----------------------------------------------------------------
8. APPROVALS
----------------------------------------------------------------
Platform Admin:  [ ] Approved  [ ] Rejected    Date: ________
Security Lead:   [ ] Approved  [ ] Rejected    Date: ________
IT Manager:      [ ] Approved  [ ] Rejected    Date: ________
Business Owner:  [ ] Approved  [ ] Rejected    Date: ________

CAB Decision:    [ ] Approved  [ ] Rejected  [ ] Deferred
CAB Date:        ________
Notes:           ________________________________________
================================================================
```

## 4. Change Windows

### Standard Change Windows

| Window | Schedule | Components | Justification |
|---|---|---|---|
| **Primary** | Tuesday - Thursday, 10:00 PM - 2:00 AM UTC | All components | Mid-week minimizes weekend staffing needs; overnight minimizes user impact |
| **Secondary** | Saturday, 8:00 AM - 12:00 PM UTC | Infrastructure only (SQL, Functions) | For changes requiring extended downtime |

### Emergency Changes

- **Any time**, with incident commander approval and at least one CAB member notified.
- Post-change documentation required within 48 hours.

### Blackout Periods

No Normal changes during:

| Period | Reason |
|---|---|
| Last week of each quarter | Financial close, audit activity |
| Company all-hands / major events | Maximum user activity |
| First 2 business days after a major release | Stabilization period |
| Holiday weeks (company-defined) | Reduced support staff |

Standard and Emergency changes are exempt from blackout restrictions (Standard because they are low-risk; Emergency by definition).

## 5. Release Process

### Environment Pipeline

```
Dev Environment              Test Environment            Prod Environment
(Unmanaged solution)         (Managed solution)          (Managed solution)
       |                            |                           |
  Continuous                   Weekly                      Bi-weekly
  deployment from          promotion every              release cycle
  feature branches         Wednesday                    (change window)
       |                            |                           |
  Developer builds          QA + UAT testing             Managed import
  and tests locally         (Thu - Mon)                  after CAB approval
       |                            |                           |
  Export unmanaged          Integration testing          Post-deploy
  solution to               with all components          verification
  source control                                         + smoke tests
```

### Release Cadence

| Environment | Cadence | Trigger | Gating |
|---|---|---|---|
| **Dev** | Continuous | Developer commit / save | None — developers work freely |
| **Test** | Weekly (Wednesday) | Managed solution import | Dev solution exports cleanly, no build errors |
| **Prod** | Bi-weekly (every other Tuesday night) | Managed solution import during change window | CAB approval + all testing checkboxes passed |

### Component-Specific Deployment

| Component | Dev → Test | Test → Prod | Deployment Method |
|---|---|---|---|
| Dataverse (schema, BPFs, rules) | Managed solution import | Managed solution import | Power Platform Build Tools (Azure DevOps) or PAC CLI |
| Power Automate flows | Included in managed solution | Included in managed solution | Solution import (connection references updated per environment) |
| SPFx web parts | Upload .sppkg to test App Catalog | Upload .sppkg to prod App Catalog | `npm run package-solution` → SharePoint ALM API |
| Azure Functions | Deploy to staging slot | Swap staging → production slot | GitHub Actions → `az functionapp deployment slot swap` |
| Azure SQL | Run migration scripts | Run migration scripts | Sequential SQL execution via `sqlcmd` or EF Core migrations |
| Power BI | Publish .pbix to test workspace | Publish .pbix to prod workspace | Power BI REST API or manual publish |

## 6. Rollback Procedures

Every change must have a documented rollback plan. Below are the standard rollback procedures per component:

### Dataverse (Managed Solution)

| Step | Action | Time |
|---|---|---|
| 1 | Identify the previous managed solution version in source control | 2 min |
| 2 | Import the previous version as a managed solution (overwrites current) | 5-10 min |
| 3 | Verify schema, business rules, and security roles are restored | 5 min |
| 4 | If import fails, restore from environment backup (point-in-time) | 30-60 min |
| **Total** | | **12-75 min** |

**Note**: Dataverse managed solution import is additive for new components — it cannot remove a column or table added in the newer version. For destructive rollbacks, use environment backup restore. See [security-model.md](security-model.md) for the ALM details.

### Azure Functions

| Step | Action | Time |
|---|---|---|
| 1 | Identify that the current production slot has the failing code | 1 min |
| 2 | Swap production slot back to the previous staging slot: `az functionapp deployment slot swap -g {rg} -n {app} --slot staging` | 2 min |
| 3 | Verify function health via Application Insights | 2 min |
| **Total** | | **5 min** |

**Why staging slots work**: Before every production deployment, the current production code is in the staging slot (swapped out). Swapping back restores the previous version instantly.

### SPFx Web Parts

| Step | Action | Time |
|---|---|---|
| 1 | Retrieve the previous .sppkg from source control or build artifacts | 2 min |
| 2 | Upload to the SharePoint App Catalog (overwrites current version) | 3 min |
| 3 | The update propagates to all sites using the web part within 15 minutes | 15 min |
| 4 | Verify by loading the SharePoint portal page | 2 min |
| **Total** | | **22 min** |

### Power Automate Flows

| Step | Action | Time |
|---|---|---|
| 1 | Turn off the new/modified flow | 1 min |
| 2 | If the previous version was a separate flow, turn it back on | 1 min |
| 3 | If the flow was updated in-place, import the previous managed solution version (which contains the old flow definition) | 5-10 min |
| 4 | Verify flow is running and triggers are firing | 3 min |
| **Total** | | **5-15 min** |

### Azure SQL

| Step | Action | Time |
|---|---|---|
| 1 | If the change was a migration script, execute the corresponding rollback script | 2-5 min |
| 2 | If no rollback script exists, use point-in-time restore: `az sql db restore --dest-name {db}-restored --time {beforeChangeUTC}` | 15-30 min |
| 3 | Rename databases to swap restored into production | 5 min |
| 4 | Verify data integrity and Power BI connectivity | 5 min |
| **Total** | | **7-45 min** |

### Power BI

| Step | Action | Time |
|---|---|---|
| 1 | Open the previous .pbix file from source control | 2 min |
| 2 | Publish to the production workspace (overwrites current) | 3 min |
| 3 | Verify report loads and data refreshes correctly | 3 min |
| **Total** | | **8 min** |

## 7. Release Notes Template

Every production release must include release notes published to the Help Desk SharePoint site.

```markdown
# Release [version] — [YYYY-MM-DD]

## Changes
- [Standard/Normal] Description of change (CR-XXXX)
- [Standard/Normal] Description of change (CR-XXXX)
- [Emergency] Description of change (CR-XXXX) — deployed [date] during incident INC-XXXX

## Components Updated
- [ ] Dataverse solution (v X.X.X.X)
- [ ] Power Automate flows
- [ ] SPFx web parts (v X.X.X)
- [ ] Azure Functions
- [ ] Azure SQL schema
- [ ] Power BI reports

## Impact
- Users affected: [All users / Agents only / Managers only / None]
- Downtime: [None / X minutes during change window]

## Known Issues
- [Issue description] — Workaround: [steps]. Fix planned for [next release].

## Rollback
- If critical issues are detected within 24 hours of release:
  1. [Component-specific rollback steps]
  2. Notify CAB via Teams channel
  3. Create incident ticket for tracking

## Approval
- CAB approval: CR-XXXX, CR-XXXX
- Deployed by: [Name]
- Verified by: [Name]
```

### Release Notes Distribution

| Audience | Channel | Timing |
|---|---|---|
| All users | SharePoint news post on Help Desk portal | Within 1 hour of deployment |
| IT agents | Teams channel (#helpdesk-releases) | Immediately after deployment |
| IT management | Email summary | Morning after deployment |

## 8. Communication Plan

### Pre-Change Communication

| Timing | Audience | Channel | Content |
|---|---|---|---|
| 48 hours before | Affected users | Email (via Power Automate) | Change summary, expected impact, downtime window |
| 48 hours before | IT agents | Teams channel | Technical details, what to expect, escalation path |
| 24 hours before | All users (if downtime) | SharePoint banner notification | "Scheduled maintenance on [date] from [time] to [time]" |
| 1 hour before | IT agents | Teams channel | "Deployment starting in 1 hour. Escalation contact: [Name]" |

### During Change

| Action | Responsibility | Channel |
|---|---|---|
| Update status page | Platform Admin | SharePoint maintenance page |
| Monitor deployment | Platform Admin | Azure Portal + Application Insights |
| Escalate issues | Platform Admin → IT Manager | Teams call |
| User-facing updates (if extended) | Business Owner | Email + SharePoint banner |

### Post-Change Communication

| Timing | Audience | Channel | Content |
|---|---|---|---|
| Immediately after | IT agents | Teams channel | "Deployment complete. Verify and report issues to #helpdesk-releases." |
| Within 1 hour | All users | Email (if downtime occurred) | "Maintenance complete. Systems are operational." |
| Next business morning | All users | SharePoint news post | Release notes (Section 7 template) |
| Within 1 week | CAB | Monthly review agenda | Post-implementation review findings |

### Emergency Communication

| Timing | Audience | Channel | Content |
|---|---|---|---|
| Immediately | IT agents | Teams channel broadcast (@channel) | "Emergency change in progress: [brief description]. Incident: INC-XXXX." |
| During incident | Affected users | SharePoint banner + email | "We are aware of [issue]. Resolution in progress. ETA: [time]." |
| After resolution | All affected | Email | "Issue resolved. Root cause: [brief]. Preventive measures: [brief]." |
| Within 48 hours | CAB | Emergency post-mortem meeting | Full root cause analysis, timeline, preventive actions |

### Communication Templates

Maintained in the SharePoint Help Desk site under `/SitePages/Templates/`:
- `pre-change-notification.html` — Pre-change email template
- `maintenance-banner.html` — SharePoint banner template
- `post-change-confirmation.html` — Post-change email template
- `emergency-notification.html` — Emergency broadcast template

## Appendix: Change Management Metrics

Track the following metrics monthly to measure process health:

| Metric | Target | Source |
|---|---|---|
| Change success rate | >95% | CR records (successful vs. rolled back) |
| Emergency change rate | <10% of all changes | CR records |
| Mean time to implement (Normal) | <2 weeks from request | CR records |
| Rollback rate | <5% | CR records |
| Changes causing incidents | 0 | Incident-to-CR correlation |
| CAB meeting attendance | >75% | Meeting minutes |
| Post-implementation review completion | 100% for Normal/Emergency | Review records |
