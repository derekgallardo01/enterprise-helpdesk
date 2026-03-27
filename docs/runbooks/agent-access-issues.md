# Runbook: Agent Access Issues

## Severity: P3

## Detection

- **User Report**: An agent contacts the platform team saying "I can't see tickets," "I can't update this ticket," or "I get a permission error when I try to reassign."
- **Monitoring**: No automated detection — access issues are inherently user-reported. However, Application Insights may show 403 responses from the Dataverse Web API correlated to a specific user.

## Impact

- A single agent (or a small group of newly onboarded agents) cannot perform their job. Their assigned tickets are not being worked.
- If the agent was the sole assignee on urgent tickets, those tickets stall until reassigned or access is restored.
- No system-wide impact. Other agents, self-service portal, Power BI, and the Teams bot are unaffected.

## Diagnosis Steps

1. **Verify the user's Entra ID account is active.** Open Entra ID → Users → search for the user. Confirm:
   - Account enabled = Yes.
   - Sign-in activity shows recent successful sign-ins.
   - The user has not been flagged by Identity Protection (risky sign-in, compromised credentials).

2. **Verify the user's Dataverse security role assignment.** Open Power Platform admin center → Environments → Production → Users → search for the user. The user must have the **HD - Agent** security role (or **HD - Manager** for managers). If no security role is assigned, this is the root cause.

3. **Verify the user's business unit membership.** In the same user record, check the Business Unit field. Agents see tickets scoped to their business unit. If the user was recently transferred and their BU was not updated, they will see tickets from their old BU (or no tickets if moved to a BU with no tickets).

4. **Check column-level security profile membership.** If the agent reports they can see tickets but certain fields are blank or read-only, the issue is column-level security. Open Power Platform admin center → Environments → Production → Column security profiles → **HD - Internal Notes Access**. Verify the user is a member.

5. **Check if the ticket is locked.** Dataverse business rules prevent edits to tickets with status = Closed or Cancelled. If the agent is trying to update a specific ticket, check its status. A locked ticket is not an access issue — it is working as designed.

6. **Check for conditional access policy blocks.** If the agent can sign in to other M365 apps but not Power Apps, a conditional access policy may be blocking access based on device compliance, location, or app filter. Check Entra ID → Sign-in logs → filter by user → look for "Failure" with a conditional access reason.

7. **Check the Power Apps license.** The user must have a Power Apps per-user plan or a per-app plan that includes the help desk app. Open M365 admin center → Users → select user → Licenses and apps.

## Resolution Steps

1. **If no security role is assigned**:
   - Open Power Platform admin center → Environments → Production → Users → select user.
   - Click "Manage security roles."
   - Assign **HD - Agent** (or the appropriate role).
   - The fix takes effect immediately — the agent should refresh the app.

2. **If the user is in the wrong business unit**:
   - Open Power Platform admin center → Environments → Production → Users → select user.
   - Click "Change business unit."
   - Select the correct BU (e.g., "IT Support - North America").
   - Note: Changing a BU removes all security role assignments. Re-assign the **HD - Agent** role after the move.

3. **If the user is missing from a column security profile**:
   - Open Power Platform admin center → Environments → Production → Column security profiles.
   - Select **HD - Internal Notes Access** (or the relevant profile).
   - Add the user as a member.

4. **If the ticket is locked (Closed/Cancelled)**:
   - If the agent needs to reopen the ticket, an **HD - Manager** or **HD - Admin** must change the status back to Active.
   - If the agent just needs to add a comment, verify that the business rule allows comments on closed tickets (current design does not — this is intentional).

5. **If a conditional access policy is blocking access**:
   - Escalate to the Identity team. Do not modify conditional access policies without approval.

6. **If the Power Apps license is missing**:
   - Assign the license in M365 admin center → Users → select user → Licenses and apps.
   - Allow 15 minutes for license propagation.

7. **Verify the fix**: Ask the agent to close and reopen the app (not just refresh). Confirm they can see tickets in their queue and can update a test ticket.

## Escalation Path

| Condition | Escalate To |
|---|---|
| Entra ID account is disabled or flagged | Identity & Access Management team |
| Conditional access policy is blocking Power Apps | Identity & Access Management team |
| Multiple agents in the same BU are affected simultaneously | Power Platform Admin (possible BU or role misconfiguration at the environment level) |
| Agent needs access to tickets outside their BU (cross-BU collaboration) | IT Service Manager (requires a business justification and role modification) |
| License assignment requires procurement | IT Procurement / License Manager |

## Prevention

1. **Automated role assignment via Entra ID group sync**: Map Entra ID security groups to Dataverse security roles. When a user is added to the "IT Support Agents" Entra group, they automatically receive the **HD - Agent** role. This eliminates manual role assignment as an onboarding step.
2. **Onboarding checklist**: Maintain a checklist for new agent onboarding that includes: Entra group membership, Dataverse security role, business unit, column security profile, Power Apps license, and a test sign-in.
3. **Quarterly access review**: Every quarter, export the list of users with the **HD - Agent** and **HD - Manager** roles. Compare against HR's active IT support staff list. Remove roles from departed or transferred employees.
4. **Self-service access request**: Provide a Power Apps canvas app or ServiceNow integration where managers can request agent access for new hires, triggering an automated provisioning flow.

## Related Alerts

| Alert Name | Condition | Severity |
|---|---|---|
| `dataverse-403-spike` | 403 response count from Dataverse Web API > 10 in 5 minutes for a single user | Warning |
| `license-assignment-failed` | Automated license assignment flow failed | Warning |
| `entra-group-sync-failed` | Entra ID group to Dataverse role sync failed | Warning |
