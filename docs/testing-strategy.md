# Enterprise Help Desk — Testing Strategy

## Overview

This document defines the testing approach across all layers of the Enterprise Help Desk Portal. Testing is organized by type (unit, integration, security, performance, accessibility) with clear ownership, tooling, and pass/fail criteria.

## Testing Pyramid

```
           /  E2E  \          ← 5 scenarios, manual + automated
          / Security \        ← 10 checks, per release
         / Integration \      ← 20 tests, automated
        / Performance    \    ← 5 benchmarks, per release
       /   Unit Tests     \   ← 50+ tests, per commit
      /____________________\
```

## 1. Unit Tests

### Azure Functions (.NET 10)

**Framework:** xUnit + Moq + FluentAssertions
**Project:** `functions/HelpDesk.Functions.Tests/`

| Test Class | Tests | What It Covers |
|-----------|-------|---------------|
| `EmailToTicketTests` | 8 | Priority keyword detection (urgent/critical/emergency), HTML sanitization, user lookup, malformed email handling |
| `DataverseSyncServiceTests` | 10 | Delta sync token management, batch processing, dimension sync, pagination, error handling per-row |
| `WebhookReceiverTests` | 8 | HMAC signature validation, ServiceNow field mapping, Jira field mapping, idempotency check, malformed payload |
| `AIClassificationServiceTests` | 5 | Category classification, confidence scoring, structured output parsing, API error handling |
| `HealthCheckTests` | 4 | All-healthy response, Dataverse-down response, SQL-down response, partial-degraded response |

**Mocking strategy:**
- Mock `DataverseService` (no live Dataverse calls in unit tests)
- Mock `SqlConnection` via `IDbConnectionFactory` interface
- Mock `HttpClient` for Azure OpenAI calls
- Mock `GraphServiceClient` for Graph API calls

**Run:** `dotnet test functions/HelpDesk.Functions.Tests/`

### SPFx (TypeScript / React)

**Framework:** Jest + React Testing Library
**Config:** `spfx/helpdesk-spfx/jest.config.js`

| Test File | Tests | What It Covers |
|----------|-------|---------------|
| `TicketService.test.ts` | 8 | getTickets with filters, getTicketById, createTicket, addComment, error responses, pagination |
| `KBService.test.ts` | 5 | Graph search query formation, result mapping, feedback submission, empty results, API errors |
| `StatusBadge.test.tsx` | 8 | All 8 status values render correct badge color and label |
| `PriorityIcon.test.tsx` | 4 | All 4 priority values render correct icon and color |
| `TicketFilters.test.tsx` | 5 | Filter state management, OData query generation, reset, cascading category/subcategory |
| `TicketDataGrid.test.tsx` | 6 | Column rendering, sort handler, row click handler, pagination, empty state, loading skeleton |

**Mocking strategy:**
- Mock `AadHttpClient` via SPFx test utilities
- Mock `MSGraphClientV3` for Graph API calls
- Mock `SPHttpClient` for SharePoint API calls

**Run:** `cd spfx/helpdesk-spfx && npm test`

### Pass Criteria
- All tests pass
- Code coverage >80% for services, >70% for components
- No test relies on external service availability

## 2. Integration Tests

**Framework:** xUnit (Functions) + custom test harness
**Project:** `tests/integration/`
**Environment:** Runs against `HelpDesk-Test` Dataverse environment + test Azure SQL database

### Test Scenarios

| # | Scenario | Steps | Expected Result |
|---|----------|-------|----------------|
| 1 | End-to-end ticket creation | Create ticket via Dataverse API → wait 60s → query Azure SQL TicketFact | Ticket exists in SQL with matching fields |
| 2 | Ticket routing | Create ticket with Category=Hardware → wait 30s | Ticket has AssignedTeam=Hardware Support, DueDate set per SLA profile |
| 3 | SLA breach detection | Create ticket with DueDate in past → trigger SLA escalation flow | hd_slabreach=true, notification sent |
| 4 | Email-to-ticket | POST to EmailToTicket endpoint with mock email payload | Ticket created with correct title, description, priority |
| 5 | Webhook (ServiceNow) | POST ServiceNow payload to WebhookReceiver | Ticket created with mapped fields, no duplicate on replay |
| 6 | Webhook (Jira) | POST Jira payload to WebhookReceiver | Ticket created with mapped fields |
| 7 | Graph user sync | Trigger GraphSyncUserProfiles → check Dataverse departments | Departments exist in hd_Department, agent data updated |
| 8 | Dimension sync | Trigger DataverseSyncToSQL → check all dimension tables | CategoryDim, SubcategoryDim, DepartmentDim, AgentDim populated |
| 9 | Aggregation refresh | Trigger sync → check aggregation tables | TicketVolumeDaily, SLAComplianceMonthly, AgentPerformanceWeekly reflect current data |
| 10 | AI classification | POST ticket to ClassifyTicket endpoint | Returns valid category, subcategory, priority with confidence score |

### Test Data Management

- **Setup:** `tests/integration/setup.ps1` — Creates test Dataverse records (5 categories, 15 subcategories, 3 SLA profiles, 5 departments, 10 test users)
- **Teardown:** `tests/integration/teardown.ps1` — Deletes all records with `hd_title` prefix `[TEST]`
- **Isolation:** All test tickets use title prefix `[TEST]` and are excluded from production reporting via SQL WHERE clause

### Run
```bash
dotnet test tests/integration/ --filter "Category=Integration" --settings tests/integration/test.runsettings
```

### Pass Criteria
- All 10 scenarios pass
- No test takes >120 seconds
- No test leaves orphaned data in Test environment

## 3. Security Tests

**Frequency:** Every release + quarterly comprehensive audit
**Environment:** `HelpDesk-Test` environment with 4 test users (one per security role)

### RBAC Verification Matrix

| # | Test | User Role | Action | Expected |
|---|------|-----------|--------|----------|
| 1 | Requester reads own ticket | HD-Requester | GET /hd_tickets?$filter=hd_requestedby eq 'self' | 200 OK, returns own tickets only |
| 2 | Requester reads other's ticket | HD-Requester | GET /hd_tickets({other-user-ticket-id}) | 403 Forbidden |
| 3 | Requester reads internal comment | HD-Requester | GET /hd_ticketcomments?$select=hd_commentbody&$filter=hd_commenttype eq 2 | hd_commentbody returns null (column security) |
| 4 | Agent reads BU tickets | HD-Agent | GET /hd_tickets (no filter) | Returns only Business Unit scoped tickets |
| 5 | Agent reads other BU ticket | HD-Agent | GET /hd_tickets({other-bu-ticket-id}) | 403 Forbidden |
| 6 | Agent reads internal comment | HD-Agent | GET /hd_ticketcomments?$select=hd_commentbody&$filter=hd_commenttype eq 2 | hd_commentbody returns value |
| 7 | Manager reads all tickets | HD-Manager | GET /hd_tickets (no filter) | Returns organization-wide tickets |
| 8 | Requester creates ticket | HD-Requester | POST /hd_tickets | 201 Created, hd_requestedby = self |
| 9 | Requester deletes ticket | HD-Requester | DELETE /hd_tickets({own-ticket-id}) | 403 Forbidden (no delete permission) |
| 10 | Unauthenticated webhook | Anonymous | POST /api/WebhookReceiver (invalid HMAC) | 401 Unauthorized |

### OWASP Top 10 Checklist

| # | Vulnerability | Test | Status |
|---|--------------|------|--------|
| 1 | Injection | SQL injection in OData $filter parameters | Mitigated (Dataverse parameterizes) |
| 2 | Broken Authentication | S2S certificate expiration monitoring | Alert configured |
| 3 | Sensitive Data Exposure | PII in Application Insights logs | Verify telemetry initializer redacts emails |
| 4 | XML External Entities | Webhook payload parsing | Verify JSON-only, no XML deserialization |
| 5 | Broken Access Control | Cross-BU ticket access | Verified by RBAC tests above |
| 6 | Security Misconfiguration | Function app CORS settings | Verify allowed origins whitelist |
| 7 | XSS | HTML in ticket description rendered in SPFx | Verify DOMPurify sanitization |
| 8 | Insecure Deserialization | Webhook receiver JSON parsing | Verify System.Text.Json (safe by default) |
| 9 | Known Vulnerabilities | NuGet/npm dependency audit | `dotnet list package --vulnerable`, `npm audit` |
| 10 | Insufficient Logging | Failed auth attempts logged | Verify Application Insights captures 401/403 |

### Run
```bash
# Dependency vulnerability scan
dotnet list functions/HelpDesk.Functions/HelpDesk.Functions.csproj package --vulnerable
cd spfx/helpdesk-spfx && npm audit

# RBAC tests (PowerShell script against Dataverse Web API)
pwsh tests/security/rbac-tests.ps1 -Environment "https://helpdesk-test.crm.dynamics.com"
```

### Pass Criteria
- All 10 RBAC tests pass
- Zero high/critical vulnerabilities in dependency audit
- All OWASP checks verified or mitigated

## 4. Performance Tests

**Framework:** k6 (load testing) + Azure Load Testing (managed service)
**Scripts:** `tests/performance/`

### Benchmarks

| # | Scenario | Tool | Target | Load |
|---|----------|------|--------|------|
| 1 | Dashboard page load | k6 | <2s P95 | 100 concurrent users |
| 2 | Ticket creation (API) | k6 | <500ms P95 | 50 concurrent requests |
| 3 | KB search (Graph API) | k6 | <1s P95 | 50 concurrent searches |
| 4 | DataverseSyncToSQL full sync | Timer | <5 min for 5,000 tickets | N/A (batch job) |
| 5 | Webhook processing | k6 | <1s P95 | 20 concurrent webhooks |

### k6 Test Script (Example)

```javascript
// tests/performance/dashboard-load.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 50 },   // ramp up
    { duration: '3m', target: 100 },   // sustained load
    { duration: '1m', target: 0 },     // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],  // 95% of requests < 2s
    http_req_failed: ['rate<0.01'],     // <1% failure rate
  },
};

export default function () {
  const res = http.get(`${__ENV.BASE_URL}/api/health`);
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
```

### Run
```bash
# Install k6
# Run load test against staging
k6 run --env BASE_URL=https://helpdesk-functions-staging.azurewebsites.net tests/performance/dashboard-load.js
```

### Pass Criteria
- All P95 targets met
- Zero errors during sustained load
- Azure SQL DTU stays <80% during test
- No Dataverse API throttling (429 responses)

### Results Documentation
After each test run, update `docs/performance-benchmarks.md` with:
- Date, environment, configuration
- Results table (P50, P95, P99, max, error rate)
- Comparison to previous run
- Bottleneck analysis if targets missed

## 5. Accessibility Tests

**Standard:** WCAG 2.1 Level AA
**Tools:** axe-core (automated), manual keyboard/screen reader testing
**Scope:** SPFx web parts + Canvas app

### Automated Testing

```bash
# Install axe-core CLI
npm install -g @axe-core/cli

# Run against SPFx workbench
axe https://localhost:4321/temp/workbench.html --tags wcag2a,wcag2aa
```

### Manual Testing Checklist

| # | Criterion | Test | Pass/Fail |
|---|-----------|------|-----------|
| 1 | Keyboard navigation | Tab through all interactive elements in ticket dashboard | |
| 2 | Focus indicators | Visible focus ring on all focusable elements | |
| 3 | Screen reader (NVDA) | Navigate ticket list, read status badges, open detail panel | |
| 4 | Color contrast | All text meets 4.5:1 ratio (normal text), 3:1 (large text) | |
| 5 | Color-only information | Status/priority conveyed by text label, not only color | |
| 6 | Form labels | All form inputs have associated labels | |
| 7 | Error messages | Form validation errors announced to screen readers | |
| 8 | Responsive layout | Dashboard usable at 200% zoom | |
| 9 | Skip navigation | "Skip to main content" link present | |
| 10 | ARIA landmarks | Main, navigation, complementary roles defined | |

### Pass Criteria
- Zero critical or serious axe-core violations
- All 10 manual checks pass
- Fluent UI v9 components used without overriding accessible defaults

## 6. End-to-End Tests

**Frequency:** Before each production release
**Approach:** Manual test script executed by QA or automated via Playwright

### E2E Test Scenarios

| # | Scenario | Actor | Steps | Expected |
|---|----------|-------|-------|----------|
| 1 | Employee submits ticket | Requester | Open Canvas app → fill form → submit | Ticket created, confirmation shown, routing fires |
| 2 | Agent triages ticket | Agent | Open model-driven app → view unassigned → assign to self → change status | Ticket assigned, requester notified via Teams |
| 3 | Agent resolves ticket | Agent | Open assigned ticket → add resolution notes → set Resolved | Resolution date stamped, requester notified, satisfaction survey appears |
| 4 | Employee rates service | Requester | Open Canvas app → My Tickets → resolved ticket → rate 4 stars | Rating saved, visible in Power BI |
| 5 | Bot creates ticket | Employee | Open Teams → chat with bot → "I need help with VPN" → confirm category | Ticket created with AI classification, ticket number returned |

### Run
```bash
# If automated via Playwright
npx playwright test tests/e2e/
```

## Test Environment Matrix

| Environment | Unit | Integration | Security | Performance | E2E |
|-------------|------|-------------|----------|-------------|-----|
| Local (dev machine) | Yes | No | No | No | No |
| HelpDesk-Dev | Yes | Yes | No | No | Yes (manual) |
| HelpDesk-Test | No | Yes | Yes | Yes | Yes |
| HelpDesk-Prod | No | No | No | No | Smoke test only |

## CI/CD Test Gates

```
Feature Branch → PR:
  ✓ Unit tests pass (Functions + SPFx)
  ✓ Dependency vulnerability scan clean
  ✓ Lint pass

Merge to main:
  ✓ All above
  ✓ Integration tests pass (against Test environment)
  ✓ Security RBAC tests pass

Deploy to Production:
  ✓ All above
  ✓ Performance benchmarks met
  ✓ Accessibility audit clean
  ✓ E2E smoke test pass
  ✓ CAB approval obtained
```
