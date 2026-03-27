# User Acceptance Testing (UAT) Plan

## Enterprise Help Desk Portal

**Version:** 1.0
**Last Updated:** 2026-03-26
**Owner:** IT Service Management Team

---

## 1. Objectives

- Validate that the Enterprise Help Desk system meets business requirements from the perspective of end users
- Confirm that all user workflows operate correctly in a production-like environment
- Identify usability issues, missing features, or workflow gaps before general availability
- Gather quantitative and qualitative feedback to inform go/no-go decision

## 2. Scope

### In Scope

- Power Apps model-driven app (Agent and Manager views)
- Self-service portal (SharePoint Framework web parts)
- Copilot Studio virtual agent (Teams integration)
- Email-to-ticket conversion flow
- AI-powered ticket classification and response suggestions
- SLA tracking and escalation notifications
- Power BI dashboards (operational and executive)
- WebhookReceiver integration (ServiceNow/Jira inbound sync)

### Out of Scope

- Azure infrastructure provisioning and networking
- Dataverse schema changes during UAT
- Power Platform environment administration
- Third-party ITSM tool configuration (ServiceNow/Jira admin)

## 3. Timeline

| Phase | Duration | Dates |
|---|---|---|
| UAT Environment Setup | 2 days | Week 1, Mon-Tue |
| Pilot Group Onboarding | 1 day | Week 1, Wed |
| Active Testing Period | 8 business days | Week 1 Thu - Week 2 Fri |
| Feedback Collection | 1 day | Week 3, Mon |
| Issue Triage & Fix | 2 days | Week 3, Tue-Wed |
| Re-test Critical Fixes | 1 day | Week 3, Thu |
| Go/No-Go Decision | 1 day | Week 3, Fri |

**Total Duration:** 3 weeks (2-week pilot + 1-week wrap-up)

## 4. Pilot Group Selection

### Criteria

- **Size:** 25-50 users across the organization
- **Composition:**
  - 5-8 IT Help Desk Agents (daily users)
  - 2-3 Help Desk Managers/Supervisors
  - 15-25 End Users/Requesters from at least 4 departments
  - 2-3 Executive stakeholders (dashboard consumers)
  - 1-2 External integration testers (ServiceNow/Jira)

### Selection Priorities

- Include users from different office locations and time zones
- Mix of tech-savvy and less technical users
- Include users who currently use the existing ticketing system
- Include users with accessibility requirements
- Ensure at least 2 users per Dataverse business unit for RBAC validation

## 5. Success Criteria

| Metric | Target | Measurement Method |
|---|---|---|
| SLA Compliance | >= 95% of tickets within SLA | Power BI SLA Compliance report |
| Page Load Time | < 2 seconds (p95) | Application Insights RUM metrics |
| System Errors | < 5 errors/week during pilot | Application Insights exceptions |
| User Satisfaction | >= 4.0 / 5.0 average | Post-pilot Microsoft Forms survey |
| Ticket Creation Success | >= 99% success rate | Function App logs + Dataverse audit |
| AI Classification Accuracy | >= 80% correct category | Manual review of 50 classified tickets |
| Copilot Resolution Rate | >= 30% resolved without agent | Copilot Studio analytics |
| Dashboard Data Freshness | < 20 minutes lag | Compare Dataverse vs SQL timestamps |

## 6. Test Scenarios

### Scenario 1: End User Submits Ticket via Portal

| Step | Action | Expected Result |
|---|---|---|
| 1 | Navigate to the Help Desk portal | Portal loads within 2 seconds |
| 2 | Click "New Ticket" | Ticket form opens with pre-populated requester info |
| 3 | Enter title: "Laptop battery drains quickly" | Title accepted |
| 4 | Select category: Hardware > Laptop | Subcategories filter correctly |
| 5 | Set priority: Medium | Priority dropdown works |
| 6 | Enter description and attach a screenshot | Attachment uploads successfully |
| 7 | Submit the ticket | Confirmation with ticket number displayed |
| 8 | Check "My Tickets" view | New ticket appears with status "New" |

### Scenario 2: End User Submits Ticket via Email

| Step | Action | Expected Result |
|---|---|---|
| 1 | Send email to helpdesk@contoso.com with subject "URGENT: VPN not connecting" | Email received by shared mailbox |
| 2 | Wait 2 minutes | Ticket created automatically via Power Automate + EmailToTicket function |
| 3 | Check portal "My Tickets" | Ticket appears with title "VPN not connecting" (RE:/FW: stripped) |
| 4 | Verify priority | Priority set to "High" (keyword "URGENT" detected) |
| 5 | Verify source | Source shows "Email" |

### Scenario 3: Copilot Handles Password Reset

| Step | Action | Expected Result |
|---|---|---|
| 1 | Open Teams and message the Help Desk bot | Bot responds with greeting |
| 2 | Type "I need to reset my password" | Bot asks clarifying questions |
| 3 | Follow guided flow | Bot provides self-service password reset link |
| 4 | Confirm resolution | Bot marks interaction as resolved; no ticket created |

### Scenario 4: Agent Triages and Resolves Ticket

| Step | Action | Expected Result |
|---|---|---|
| 1 | Agent opens the Help Desk app | Dashboard shows queue with unassigned tickets |
| 2 | Select an unassigned ticket | Ticket detail form opens with AI classification suggestion |
| 3 | Accept or modify AI classification | Category/subcategory/priority updated |
| 4 | Click "Suggest Response" | AI-generated response appears with KB article links |
| 5 | Edit and send response to requester | Comment added; requester notified via email |
| 6 | Set status to "Resolved" | Resolution date auto-populated; SLA timer stops |
| 7 | Verify requester receives satisfaction survey | Email with 1-5 star rating link sent |

### Scenario 5: SLA Breach Escalation

| Step | Action | Expected Result |
|---|---|---|
| 1 | Create a Critical priority ticket | Ticket created with 4-hour SLA |
| 2 | Do not respond for 3 hours 45 minutes | Warning notification sent to assigned agent |
| 3 | Do not respond for 4 hours | SLA breached flag set; manager notified via Teams |
| 4 | Check Power BI SLA dashboard | Breach appears in the SLA Compliance report |

### Scenario 6: Manager Reviews Team Performance

| Step | Action | Expected Result |
|---|---|---|
| 1 | Manager opens Power BI dashboard | Dashboard loads with current data (< 20 min lag) |
| 2 | Filter by "This Week" | Metrics update for current week |
| 3 | Drill into agent performance | Individual agent stats visible |
| 4 | Identify ticket backlog by category | Category breakdown chart displays correctly |
| 5 | Export report to PDF | PDF exports with correct formatting |

### Scenario 7: External Webhook Creates Ticket

| Step | Action | Expected Result |
|---|---|---|
| 1 | Send ServiceNow webhook payload with valid HMAC | Ticket created in Dataverse |
| 2 | Verify field mapping | Title, description, priority, status mapped correctly |
| 3 | Send duplicate payload (same incident number) | Existing ticket updated (idempotent) |
| 4 | Send payload with invalid HMAC | 401 Unauthorized returned |

### Scenario 8: Requester Views Only Own Tickets

| Step | Action | Expected Result |
|---|---|---|
| 1 | Requester logs into portal | Only their own tickets visible |
| 2 | Attempt to access another user's ticket URL | Access denied or redirected |
| 3 | View a ticket with internal comments | Internal comment body is hidden |

### Scenario 9: Bulk Ticket Import via Seed Script

| Step | Action | Expected Result |
|---|---|---|
| 1 | Run generate-test-tickets.ps1 with 100 tickets | 100 tickets created in under 10 minutes |
| 2 | Wait for next sync cycle (15 minutes) | Tickets appear in Azure SQL TicketFact |
| 3 | Verify Power BI reflects new data | Dashboard counts increase by ~100 |

### Scenario 10: Concurrent Multi-User Load

| Step | Action | Expected Result |
|---|---|---|
| 1 | 10 users simultaneously create tickets | All tickets created successfully |
| 2 | 5 agents simultaneously update different tickets | No conflicts or data loss |
| 3 | Monitor Application Insights during peak | No 500 errors; response times < 2 seconds |

### Scenario 11: Accessibility Validation

| Step | Action | Expected Result |
|---|---|---|
| 1 | Navigate portal using keyboard only | All interactive elements reachable via Tab/Enter |
| 2 | Use screen reader on ticket list | Ticket titles and statuses read aloud correctly |
| 3 | Test with high-contrast mode | All text and controls remain visible |

## 7. Feedback Collection

### Method: Microsoft Forms Survey

Distributed to all pilot participants at the end of Week 2.

### Survey Questions

1. **Overall satisfaction:** How would you rate your overall experience with the new Help Desk system? (1-5 stars)
2. **Ease of use:** How easy was it to submit a ticket? (1-5 scale: Very Difficult to Very Easy)
3. **Ticket resolution:** Was your test ticket resolved to your satisfaction? (Yes / No / Partially)
4. **Response time:** How would you rate the speed of responses? (1-5 scale)
5. **Copilot experience:** Did the virtual agent help resolve your issue without creating a ticket? (Yes / No / Did not use)
6. **AI suggestions (Agents only):** Were the AI-suggested responses useful? (1-5 scale)
7. **Dashboard clarity (Managers only):** Could you easily find the metrics you needed? (1-5 scale)
8. **Compared to current system:** How does this compare to the existing ticketing system? (Much Worse / Worse / Same / Better / Much Better)
9. **Missing features:** What features or capabilities are missing? (Free text)
10. **Top improvement:** What is the single most important improvement you would suggest? (Free text)
11. **Bugs encountered:** Did you encounter any bugs or errors? If so, describe. (Free text)
12. **Would recommend:** Would you recommend this system for organization-wide deployment? (Yes / No / Need more time)

## 8. Go/No-Go Checklist

All items must be checked for a GO decision. Any unchecked item requires documented mitigation.

- [ ] All 11 test scenarios pass with no Critical or High severity defects open
- [ ] SLA compliance >= 95% during pilot period
- [ ] Average page load time < 2 seconds (p95)
- [ ] Fewer than 5 system errors during the pilot
- [ ] User satisfaction survey average >= 4.0 / 5.0
- [ ] AI classification accuracy >= 80% (manual review of sample)
- [ ] Copilot resolves >= 30% of interactions without agent involvement
- [ ] Data sync lag < 20 minutes (Dataverse to SQL to Power BI)
- [ ] RBAC tests pass (all 4 roles verified)
- [ ] No data loss or corruption incidents during pilot
- [ ] Performance test thresholds met (p95 < 2s dashboard, p95 < 500ms API)
- [ ] Accessibility: no blockers for keyboard/screen reader users
- [ ] Rollback plan tested and documented
- [ ] Runbook reviewed and signed off by operations team
- [ ] Pilot feedback survey response rate >= 70%

## 9. Measured Rollout Plan

### Phase 1: Pilot (Weeks 1-3)

- 25-50 users as defined in Section 4
- Full UAT test cycle
- Daily defect triage with development team
- Fixes deployed to UAT environment within 24 hours for Critical issues

### Phase 2: IT Organization-Wide (Weeks 4-5)

- Expand to all IT department users (~150 users)
- Run in parallel with existing ticketing system for 1 week
- Monitor error rates, SLA compliance, and user feedback
- Gate: No Critical defects; satisfaction >= 3.8

### Phase 3: All Employees (Weeks 6-8)

- Organization-wide rollout (~2,000+ users)
- Decommission legacy ticketing system after 2-week overlap
- Full Copilot Studio availability in Teams
- All external webhook integrations active

### Phase 4: Optimization (Weeks 9-12)

- Analyze 30 days of production data
- Tune AI classification model based on correction rates
- Optimize Power BI reports based on usage patterns
- Implement feature requests from UAT feedback

## 10. Hypercare Procedures

### Duration: 2 weeks after each rollout phase

### Daily Health Check Review

Performed every business day at 9:00 AM by the on-call support engineer:

1. **Application Insights dashboard:** Check for any new exceptions or anomalies in the last 24 hours
2. **Azure Function execution logs:** Verify EmailToTicket, WebhookReceiver, and DataverseSyncToSQL ran successfully
3. **SLA compliance check:** Query for any tickets approaching SLA breach in the next 2 hours
4. **Sync lag verification:** Compare latest `DataverseModifiedOn` in TicketFact vs current time
5. **Power BI refresh status:** Confirm dataset refreshed within the last 20 minutes
6. **Copilot Studio analytics:** Review conversation completion rate and fallback rate
7. **User-reported issues:** Check the #helpdesk-feedback Teams channel for new reports

### Escalation Matrix

| Severity | Response Time | Escalation Path |
|---|---|---|
| Critical (system down) | 15 minutes | On-call engineer -> Engineering Lead -> VP of IT |
| High (feature broken) | 1 hour | On-call engineer -> Engineering Lead |
| Medium (degraded) | 4 hours | On-call engineer -> Sprint backlog |
| Low (cosmetic) | Next sprint | Backlog |

### War Room Protocol

If 3 or more Critical issues occur within 24 hours:
1. Activate war room (dedicated Teams channel)
2. All hands from engineering team until resolved
3. Hourly status updates to stakeholders
4. Post-incident review within 48 hours

## 11. Lessons Learned Template

Complete this after each rollout phase.

### What Went Well

| Item | Details | Impact |
|---|---|---|
| | | |

### What Could Be Improved

| Item | Details | Proposed Action | Owner | Due Date |
|---|---|---|---|---|
| | | | | |

### Unexpected Issues

| Issue | Root Cause | Resolution | Prevention |
|---|---|---|---|
| | | | |

### Metrics Summary

| Metric | Target | Actual | Status |
|---|---|---|---|
| SLA Compliance | >= 95% | | |
| Page Load (p95) | < 2s | | |
| System Errors/Week | < 5 | | |
| User Satisfaction | >= 4.0 | | |
| AI Accuracy | >= 80% | | |
| Copilot Resolution | >= 30% | | |
| Sync Lag | < 20 min | | |

### Recommendations for Next Phase

1.
2.
3.

---

**Approvals**

| Role | Name | Date | Signature |
|---|---|---|---|
| Project Sponsor | | | |
| IT Service Manager | | | |
| Engineering Lead | | | |
| QA Lead | | | |
| Security Officer | | | |
