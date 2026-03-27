# Copilot Studio -- Enterprise Help Desk Bot

## Bot Overview

| Property | Value |
|---|---|
| **Bot Name** | HD - Help Desk Assistant |
| **Primary Channel** | Microsoft Teams |
| **Secondary Channels** | SharePoint intranet (embedded web chat) |
| **Language** | English (en-US) |
| **Authentication** | Entra ID SSO (Teams channel inherits user identity) |
| **Solution** | HelpDesk 1.0.0.0 |

## Knowledge Sources

| Source | Type | Description |
|---|---|---|
| SharePoint KB Library | Generative answers | The bot uses generative answers grounded on the SharePoint knowledge base site (`https://contoso.sharepoint.com/sites/IT-KnowledgeBase`). This is the primary self-service deflection mechanism. |
| Dataverse hd_kbarticleref | Search | Structured KB article index used when generative answers return low confidence, providing direct links to SharePoint pages. |
| Dataverse hd_ticket | Plugin action | Used by the check-status topic to look up ticket details by ticket number. |
| Dataverse hd_category / hd_subcategory | Plugin action | Used to populate category/subcategory options during ticket creation. |

## Fallback Behavior

When no topic trigger matches and generative answers cannot provide a confident response:

1. The bot responds: "I was not able to find an answer to that. Would you like me to create a support ticket for you?"
2. If the user says yes, the bot transitions to the `create-ticket` topic.
3. If the user says no, the bot responds: "No problem. You can also reach our IT support team at helpdesk@contoso.com or call ext. 4357."

## Topics

| Topic | File | Description |
|---|---|---|
| Create Ticket | `topics/create-ticket.yaml` | Guides the user through creating a new help desk ticket |
| Check Status | `topics/check-status.yaml` | Looks up a ticket by number and displays current status |
| KB Search | `topics/kb-search.yaml` | Searches the knowledge base with generative answers fallback |
| Auto-Categorize | `topics/auto-categorize.yaml` | Power Automate flow for AI-driven category assignment |

## Environment Variables

| Variable | Type | Description |
|---|---|---|
| `hd_DataverseEnvironmentUrl` | String | Dataverse environment URL for plugin actions |
| `hd_SharePointKBSiteUrl` | String | SharePoint knowledge base site URL for generative answers |
| `hd_ModelDrivenAppUrl` | String | Base URL for ticket deep links |
| `hd_ClassifyTicketFlowUrl` | String | HTTP trigger URL for the ClassifyTicket Azure Function |

## Security

- The bot runs with delegated permissions. It can only access Dataverse rows the calling user has permission to see.
- Ticket creation sets `hd_requestedby` to the calling user's Entra ID, preventing impersonation.
- Internal comments (hd_commenttype = 2) are never returned to the bot -- the Dataverse query filters on hd_commenttype = 1.

## Deployment

1. Import the HelpDesk solution into the target Power Platform environment.
2. The Copilot Studio bot is included as a solution component.
3. Configure the environment variables above for each environment (dev/staging/prod).
4. Publish the bot to the Teams app catalog via the Teams admin center.
5. Pin the bot in the Teams left rail via a Teams app setup policy.
