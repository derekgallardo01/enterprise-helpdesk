# ADR-004: Copilot Studio Over Bot Framework SDK

## Status
Accepted

## Context
The help desk needs a Teams bot for ticket creation, status checks, and KB search. Two approaches: build a custom bot with Bot Framework SDK, or use Copilot Studio (low-code) with Power Automate extensions.

## Decision
Use Copilot Studio for the conversational AI layer, extended with Power Automate cloud flows for custom logic (Dataverse writes, approval workflows).

## Rationale

| Factor | Copilot Studio | Bot Framework SDK |
|---|---|---|
| **Build time** | Hours (visual dialog builder) | 40+ hours (code dialog management, NLU model training, card rendering, auth flows) |
| **KB search** | Generative answers from SharePoint — zero training data, auto-updates as KB grows | Must build custom RAG pipeline (embeddings, vector search, prompt engineering) |
| **Teams deployment** | One-click publish to Teams channel | Requires Bot Channel Registration, Teams app manifest, admin approval workflow |
| **NLU** | Built-in intent recognition + generative AI fallback | Must train LUIS/CLU models with utterance examples |
| **Extensibility** | Power Automate cloud flows for custom logic | Full code control (C#/Node.js) |
| **Maintenance** | Business users can update topics and responses | Every change requires a developer + deployment |
| **Multi-channel** | Teams, web chat, SharePoint embed — configuration only | Each channel requires code-level integration |

### The 80/20 Rule

Copilot Studio handles the 80% case excellently:
- "I need help with my laptop" → Create ticket topic
- "What's the status of TKT-000042?" → Status check topic
- "How do I connect to VPN?" → Generative answers from KB
- "Talk to a person" → Escalation/handoff topic

The 20% that needs custom logic:
- Writing a ticket to Dataverse → Power Automate cloud flow (called from Copilot Studio)
- Sending an adaptive card with ticket details → Power Automate with Teams connector
- AI-powered ticket classification → Azure Function called via Power Automate

None of the 20% scenarios require dropping to Bot Framework SDK. Power Automate cloud flows bridge the gap.

### Generative Answers — The Key Differentiator

Copilot Studio's generative answers feature:
1. Indexes the SharePoint KB site automatically
2. When a user asks a question, searches the KB for relevant content
3. Generates an AI-summarized answer with source citations
4. Requires **zero training data** — no utterance examples, no intent definitions
5. Improves automatically as KB articles are added or updated

Building equivalent functionality in Bot Framework SDK would require:
- Embedding generation pipeline for KB articles
- Vector database or Azure AI Search index
- RAG prompt engineering
- Refresh mechanism when KB changes
- Citation extraction and formatting

This alone justifies the Copilot Studio choice — it's 40+ hours of RAG engineering replaced by a configuration toggle.

## Consequences

- Copilot Studio has less flexibility than Bot Framework SDK for highly custom conversational flows
- Copilot Studio requires per-message licensing or a capacity pack (cost varies by volume)
- If requirements exceed Copilot Studio capabilities in the future, migration to Bot Framework SDK requires a full rewrite
- The tradeoff is acceptable: help desk bot conversations are structured and predictable, not open-ended — Copilot Studio's capabilities are sufficient
