# ADR-003: SPFx Web Parts Over Power Apps Iframes in SharePoint

## Status
Accepted

## Context
The help desk needs a SharePoint-hosted portal with a ticket dashboard, KB search, and quick stats. Two approaches: embed Power Apps as iframes, or build native SPFx web parts in React/TypeScript.

## Decision
Build native SPFx web parts using React and Fluent UI v9, with Dataverse access via `AadHttpClient`.

## Rationale

| Factor | SPFx Web Part | Power Apps Iframe |
|---|---|---|
| **Load time** | < 1 second (bundled JS, no runtime init) | 3-5 seconds (Power Apps player must initialize) |
| **Theming** | Inherits SharePoint theme tokens automatically | Manual color matching; breaks on theme change |
| **Navigation** | Native SharePoint page context (breadcrumbs, back button) | Iframe isolation; no navigation integration |
| **Authentication** | `AadHttpClient` from SharePoint context (zero user prompt) | Separate Power Apps auth flow (may trigger consent popup) |
| **Bundle size** | < 100KB gzipped (tree-shaken Fluent UI v9) | ~2MB (entire Power Apps player runtime) |
| **Mobile** | Responsive within SharePoint mobile experience | Iframe scaling issues on mobile browsers |
| **Viva Connections** | ACE (Adaptive Card Extension) support for dashboard cards | No ACE equivalent |
| **Performance control** | Full control: pagination, caching, lazy loading | Power Apps controls rendering pipeline; limited optimization levers |

### The UX Penalty Compounds

A single iframe is tolerable. But the portal has multiple components on one page (ticket dashboard + KB search + stats). Three Power Apps iframes means:
- 3 × 3-5 second load times (sequential or competing for bandwidth)
- 3 separate auth flows
- 3 instances of the Power Apps player runtime (~6MB total)
- Inconsistent styling between each iframe and the SharePoint chrome

SPFx web parts share a single page context, authenticate once, and render as native page components.

### ACE for Viva Connections

The `HelpdeskQuickStats` Adaptive Card Extension is only possible with SPFx. It appears on the Viva Connections dashboard — a high-visibility surface that most candidates cannot build for. This is a portfolio differentiator.

## Consequences

- SPFx has a steeper initial learning curve than Power Apps (Yeoman generator, `AadHttpClient` setup, App Catalog deployment)
- SPFx requires a developer for changes; Power Apps can be modified by citizen developers
- SPFx web parts must be tested in the SharePoint workbench and deployed via the App Catalog
- The tradeoff is acceptable: the portal is a developer-maintained component, not a citizen-developer surface
