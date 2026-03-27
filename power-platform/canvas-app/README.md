# Canvas App -- Enterprise Help Desk Self-Service Portal

## App Overview

| Property | Value |
|---|---|
| **App Name** | HD - Self Service Portal |
| **Layout** | Tablet (responsive, 1366x768 base) |
| **Data Source** | Microsoft Dataverse (HelpDesk solution tables) |
| **Theme** | Contoso brand: Primary #0078D4, Secondary #106EBE, Background #FAF9F8 |
| **Authentication** | Entra ID SSO (inherited from Power Apps) |
| **Target Users** | All employees (HD - Requester role) |

## Data Sources

| Name | Type | Tables Used |
|---|---|---|
| Dataverse | Native | hd_ticket, hd_ticketcomment, hd_category, hd_subcategory, hd_kbarticleref |
| Office 365 Users | Connector | User() for current user context |

## Global Variables

| Variable | Type | Set On | Description |
|---|---|---|---|
| `gblCurrentUser` | Record | App.OnStart | Current user profile from Office365Users.MyProfile() |
| `gblCategories` | Table | App.OnStart | Cached active categories: `Filter(hd_category, hd_isactive = true)` |
| `gblAppTheme` | Record | App.OnStart | Color and font tokens for consistent styling |

## App.OnStart

```
Concurrent(
    Set(gblCurrentUser, Office365Users.MyProfile()),
    ClearCollect(gblCategories, Filter(hd_category, hd_isactive = true)),
    Set(gblAppTheme, {
        Primary: ColorValue("#0078D4"),
        PrimaryDark: ColorValue("#106EBE"),
        Background: ColorValue("#FAF9F8"),
        Surface: Color.White,
        TextPrimary: ColorValue("#323130"),
        TextSecondary: ColorValue("#605E5C"),
        Success: ColorValue("#107C10"),
        Warning: ColorValue("#FFB900"),
        Error: ColorValue("#D13438")
    })
)
```

---

## Screens

### 1. Home Screen (`scrHome`)

**Purpose:** Landing page showing quick-action cards and a summary of the user's recent tickets.

#### Controls

| Control | Type | Properties |
|---|---|---|
| `lblWelcome` | Label | Text: `"Welcome, " & gblCurrentUser.DisplayName` |
| `galQuickActions` | Gallery (Horizontal) | Items: `["Submit Ticket", "My Tickets", "Knowledge Base"]` |
| `imgQuickActionIcon` | Image (inside gallery) | Image: Conditional icon per action type |
| `lblQuickActionLabel` | Label (inside gallery) | Text: `ThisItem.Value` |
| `galRecentTickets` | Gallery (Vertical) | Items: `SortByColumns(Filter(hd_ticket, hd_requestedby = gblCurrentUser.Id, hd_status <> 7, hd_status <> 8), "createdon", SortOrder.Descending)` Top: 5 |
| `lblRecentTicketNumber` | Label (inside gallery) | Text: `ThisItem.hd_ticketnumber` |
| `lblRecentTicketTitle` | Label (inside gallery) | Text: `ThisItem.hd_title` |
| `icoRecentTicketPriority` | Icon (inside gallery) | Color: Switch on `ThisItem.hd_priority` |
| `btnViewAll` | Button | Text: "View All Tickets", OnSelect: `Navigate(scrMyTickets)` |

#### Navigation

- Quick action "Submit Ticket" -> `Navigate(scrSubmitTicket, ScreenTransition.Fade)`
- Quick action "My Tickets" -> `Navigate(scrMyTickets, ScreenTransition.Fade)`
- Quick action "Knowledge Base" -> `Navigate(scrKBSearch, ScreenTransition.Fade)`
- Gallery item select -> `Navigate(scrTicketDetail, ScreenTransition.Fade, {navTicket: ThisItem})`

---

### 2. Submit Ticket Screen (`scrSubmitTicket`)

**Purpose:** Form for creating a new help desk ticket.

#### Controls

| Control | Type | Properties |
|---|---|---|
| `lblPageTitle` | Label | Text: "Submit a New Ticket" |
| `txtTitle` | Text Input | HintText: "Brief summary of your issue", MaxLength: 200 |
| `txtDescription` | Rich Text Editor | HintText: "Describe the issue in detail..." |
| `ddCategory` | Dropdown | Items: `gblCategories`, DisplayFields: `hd_name` |
| `ddSubcategory` | Dropdown | Items: `Filter(hd_subcategory, hd_category.hd_categoryid = ddCategory.Selected.hd_categoryid, hd_isactive = true)`, DisplayFields: `hd_name` |
| `ddImpact` | Dropdown | Items: `["Individual", "Department", "Enterprise"]` |
| `ddUrgency` | Dropdown | Items: `["Low", "Medium", "High", "Critical"]` |
| `lblCalculatedPriority` | Label | Text: Computed from impact/urgency matrix |
| `ddEnvironment` | Dropdown | Items: `["Production", "Staging", "Development"]`, Visible: `ddCategory.Selected.hd_name = "Software"` |
| `btnSubmit` | Button | Text: "Submit Ticket" |
| `btnCancel` | Button | Text: "Cancel", OnSelect: `Back()` |
| `lblValidation` | Label | Visible on validation errors, red text |

#### Submit Logic (btnSubmit.OnSelect)

```
If(
    IsBlank(txtTitle.Text) Or IsBlank(txtDescription.HtmlText) Or IsBlank(ddCategory.Selected),
    Set(varValidationError, "Please fill in all required fields."),

    // Create the ticket
    Set(varNewTicket,
        Patch(hd_ticket,
            Defaults(hd_ticket),
            {
                hd_title: txtTitle.Text,
                hd_description: txtDescription.HtmlText,
                hd_category: ddCategory.Selected,
                hd_subcategory: ddSubcategory.Selected,
                hd_impact: {Value: Switch(ddImpact.Selected.Value, "Enterprise",1, "Department",2, "Individual",3)},
                hd_urgency: {Value: Switch(ddUrgency.Selected.Value, "Critical",1, "High",2, "Medium",3, "Low",4)},
                hd_source: {Value: 1},
                hd_status: {Value: 1}
            }
        )
    );
    If(
        !IsError(varNewTicket),
        Navigate(scrTicketDetail, ScreenTransition.Fade, {navTicket: varNewTicket});
        Notify("Ticket " & varNewTicket.hd_ticketnumber & " created successfully.", NotificationType.Success),
        Notify("Failed to create ticket. Please try again.", NotificationType.Error)
    )
)
```

---

### 3. My Tickets Screen (`scrMyTickets`)

**Purpose:** List of all tickets submitted by the current user with filtering and sorting.

#### Controls

| Control | Type | Properties |
|---|---|---|
| `lblPageTitle` | Label | Text: "My Tickets" |
| `ddStatusFilter` | Dropdown | Items: `["All", "Open", "Resolved", "Closed"]`, Default: "Open" |
| `txtSearch` | Text Input | HintText: "Search by ticket number or title..." |
| `galTickets` | Gallery (Vertical, flexible height) | Items: (see data binding below) |
| `lblTicketNumber` | Label (inside gallery) | Text: `ThisItem.hd_ticketnumber` |
| `lblTicketTitle` | Label (inside gallery) | Text: `ThisItem.hd_title` |
| `lblTicketStatus` | Label (inside gallery) | Text: status label, Fill: status color |
| `icoTicketPriority` | Icon (inside gallery) | Icon: Circle, Color: priority color |
| `lblTicketDate` | Label (inside gallery) | Text: `Text(ThisItem.createdon, "mmm dd, yyyy")` |
| `lblNoTickets` | Label | Visible: `CountRows(galTickets.AllItems) = 0`, Text: "No tickets found." |

#### Data Binding

```
SortByColumns(
    Filter(
        hd_ticket,
        hd_requestedby = gblCurrentUser.Id,
        // Status filter
        Switch(ddStatusFilter.Selected.Value,
            "Open", hd_status.Value < 6,
            "Resolved", hd_status.Value = 6,
            "Closed", hd_status.Value >= 7,
            true
        ),
        // Search filter
        Or(
            IsBlank(txtSearch.Text),
            txtSearch.Text in hd_ticketnumber,
            txtSearch.Text in hd_title
        )
    ),
    "createdon", SortOrder.Descending
)
```

#### Navigation

- Gallery item select -> `Navigate(scrTicketDetail, ScreenTransition.Fade, {navTicket: ThisItem})`

---

### 4. Ticket Detail Screen (`scrTicketDetail`)

**Purpose:** Full ticket view with comment thread, status timeline, and ability to add comments or rate satisfaction.

#### Context Variable

- `navTicket` (Record): The selected `hd_ticket` row passed via `Navigate()`.

#### Controls

| Control | Type | Properties |
|---|---|---|
| `lblTicketNumber` | Label | Text: `navTicket.hd_ticketnumber` |
| `lblTicketTitle` | Label | Text: `navTicket.hd_title` |
| `htmlDescription` | HTML Text | HtmlText: `navTicket.hd_description` |
| `lblStatus` | Label | Text: Status label, Fill: Status color |
| `lblPriority` | Label | Text: Priority label |
| `lblCategory` | Label | Text: `navTicket.hd_category.hd_name` |
| `lblSubcategory` | Label | Text: `navTicket.hd_subcategory.hd_name` |
| `lblCreatedDate` | Label | Text: `"Created: " & Text(navTicket.createdon, "mmm dd, yyyy hh:mm")` |
| `lblDueDate` | Label | Text: `"Due: " & Text(navTicket.hd_duedate, "mmm dd, yyyy hh:mm")`, Color: If overdue, red |
| `lblAssignedTo` | Label | Text: `navTicket.hd_assignedto.'Full Name'` |
| `galComments` | Gallery (Vertical) | Items: `SortByColumns(Filter(hd_ticketcomment, hd_ticket.hd_ticketid = navTicket.hd_ticketid, hd_commenttype.Value = 1), "createdon", SortOrder.Ascending)` |
| `htmlCommentBody` | HTML Text (inside gallery) | HtmlText: `ThisItem.hd_commentbody` |
| `lblCommentAuthor` | Label (inside gallery) | Text: `ThisItem.createdby.'Full Name'` |
| `lblCommentDate` | Label (inside gallery) | Text: `Text(ThisItem.createdon, "mmm dd hh:mm")` |
| `txtNewComment` | Rich Text Editor | HintText: "Add a comment..." |
| `btnAddComment` | Button | Text: "Add Comment" |
| `grpSatisfaction` | Group | Visible: `navTicket.hd_status.Value = 6 And IsBlank(navTicket.hd_satisfactionrating)` |
| `ratingStars` | Rating | Max: 5 |
| `btnSubmitRating` | Button | Text: "Submit Rating" |
| `btnBack` | Button | Text: "Back", OnSelect: `Back()` |

#### Add Comment Logic (btnAddComment.OnSelect)

```
If(
    !IsBlank(txtNewComment.HtmlText),
    Patch(hd_ticketcomment,
        Defaults(hd_ticketcomment),
        {
            hd_ticket: navTicket,
            hd_commentbody: txtNewComment.HtmlText,
            hd_commenttype: {Value: 1}
        }
    );
    Reset(txtNewComment);
    Notify("Comment added.", NotificationType.Success)
)
```

#### Submit Rating Logic (btnSubmitRating.OnSelect)

```
Patch(hd_ticket, navTicket, { hd_satisfactionrating: ratingStars.Value });
Notify("Thank you for your feedback!", NotificationType.Success);
Set(navTicket, LookUp(hd_ticket, hd_ticketid = navTicket.hd_ticketid))
```

---

### 5. KB Search Screen (`scrKBSearch`)

**Purpose:** Search the knowledge base (SharePoint-backed articles indexed in Dataverse).

#### Controls

| Control | Type | Properties |
|---|---|---|
| `lblPageTitle` | Label | Text: "Knowledge Base" |
| `txtKBSearch` | Text Input | HintText: "Search for articles..." |
| `ddKBCategory` | Dropdown | Items: `Table({Value:"All"}, gblCategories)`, Default: "All" |
| `galKBArticles` | Gallery (Vertical) | Items: (see data binding below) |
| `lblArticleTitle` | Label (inside gallery) | Text: `ThisItem.hd_title` |
| `lblArticleCategory` | Label (inside gallery) | Text: `ThisItem.hd_category.hd_name` |
| `lblArticleViews` | Label (inside gallery) | Text: `ThisItem.hd_viewcount & " views"` |
| `icoHelpful` | Icon (inside gallery) | Icon: Like, Text: `ThisItem.hd_helpfulcount` |
| `lblNoResults` | Label | Visible: `CountRows(galKBArticles.AllItems) = 0 And !IsBlank(txtKBSearch.Text)`, Text: "No articles found. Would you like to submit a ticket?" |
| `btnCreateFromKB` | Button | Visible: same as `lblNoResults`, Text: "Submit a Ticket", OnSelect: `Navigate(scrSubmitTicket)` |

#### Data Binding

```
SortByColumns(
    Filter(
        hd_kbarticleref,
        Or(IsBlank(txtKBSearch.Text), txtKBSearch.Text in hd_title),
        Or(
            ddKBCategory.Selected.Value = "All",
            hd_category.hd_categoryid = ddKBCategory.Selected.hd_categoryid
        )
    ),
    "hd_viewcount", SortOrder.Descending
)
```

#### Navigation

- Article tap -> `Launch(ThisItem.hd_sharepointurl)` (opens SharePoint KB article in browser)

---

### 6. Satisfaction Survey Screen (`scrSurvey`)

**Purpose:** Dedicated screen for rating a resolved ticket (also accessible from the ticket detail screen inline). Used when the user arrives via a deep link from the Teams notification.

#### Context Variable

- `navTicketId` (GUID): Ticket ID passed from deep link query parameter.

#### Controls

| Control | Type | Properties |
|---|---|---|
| `lblSurveyTitle` | Label | Text: "How was your experience?" |
| `lblSurveyTicket` | Label | Text: `varSurveyTicket.hd_ticketnumber & " - " & varSurveyTicket.hd_title` |
| `ratingControl` | Rating | Max: 5, Default: 0 |
| `lblRatingText` | Label | Text: Switch on rating value ("Poor", "Fair", "Good", "Very Good", "Excellent") |
| `txtFeedback` | Text Input (multiline) | HintText: "Optional: Tell us more about your experience..." |
| `btnSubmitSurvey` | Button | Text: "Submit Feedback" |
| `lblThankYou` | Label | Visible: after submission, Text: "Thank you for your feedback!" |

#### Screen.OnVisible

```
Set(varSurveyTicket,
    LookUp(hd_ticket, hd_ticketid = navTicketId)
);
If(
    IsBlank(varSurveyTicket),
    Notify("Ticket not found.", NotificationType.Error);
    Back()
)
```

#### Submit Logic (btnSubmitSurvey.OnSelect)

```
Patch(hd_ticket, varSurveyTicket, {
    hd_satisfactionrating: ratingControl.Value
});
Set(varSubmitted, true);
Notify("Rating submitted. Thank you!", NotificationType.Success)
```

---

## Navigation Component (`cmpNavBar`)

A reusable component rendered at the top of every screen.

| Control | Type | Properties |
|---|---|---|
| `rectNavBg` | Rectangle | Fill: `gblAppTheme.Primary`, Height: 48 |
| `lblAppName` | Label | Text: "IT Help Desk", Color: White, Font: Segoe UI Semibold 16 |
| `btnNavHome` | Button | Icon: Home, OnSelect: `Navigate(scrHome)` |
| `btnNavSubmit` | Button | Icon: Add, OnSelect: `Navigate(scrSubmitTicket)` |
| `btnNavTickets` | Button | Icon: DocumentSet, OnSelect: `Navigate(scrMyTickets)` |
| `btnNavKB` | Button | Icon: Search, OnSelect: `Navigate(scrKBSearch)` |
| `lblUserName` | Label | Text: `gblCurrentUser.DisplayName`, Align: Right |
