import { AadHttpClient, HttpClientResponse } from "@microsoft/sp-http";

/**
 * Abstracted API layer for Dataverse ticket operations.
 *
 * All SPFx web parts use this service instead of calling Dataverse directly.
 * The AadHttpClient is injected via constructor — making the service testable
 * (mock the client in tests) and swappable (switch to a custom API if needed).
 *
 * Architecture note: AadHttpClient handles token acquisition automatically
 * from the SharePoint context. No manual auth code needed.
 */

export interface Ticket {
  hd_ticketid: string;
  hd_ticketnumber: string;
  hd_title: string;
  hd_description?: string;
  hd_priority: number; // 1=Critical, 2=High, 3=Medium, 4=Low
  hd_status: number; // 1=New .. 8=Cancelled
  hd_category?: { hd_name: string };
  hd_assignedto?: { fullname: string };
  hd_requestedby?: { fullname: string };
  hd_duedate?: string;
  hd_resolutiondate?: string;
  hd_slabreach?: boolean;
  hd_satisfactionrating?: number;
  createdon: string;
}

export interface TicketComment {
  hd_ticketcommentid: string;
  hd_commentbody: string;
  hd_commenttype: number; // 1=Public, 2=Internal
  createdon: string;
  createdby: { fullname: string };
}

export interface TicketListResponse {
  value: Ticket[];
  "@odata.nextLink"?: string;
}

const DATAVERSE_API_VERSION = "v9.2";

export class TicketService {
  private readonly client: AadHttpClient;
  private readonly dataverseUrl: string;

  constructor(client: AadHttpClient, dataverseUrl: string) {
    this.client = client;
    this.dataverseUrl = dataverseUrl;
  }

  /**
   * Fetches tickets for the current user with pagination.
   * Uses server-side filtering (OData $filter) — fully delegated, no client-side limits.
   */
  async getMyTickets(
    userId: string,
    top: number = 50,
    skip: number = 0
  ): Promise<TicketListResponse> {
    const url =
      `${this.dataverseUrl}/api/data/${DATAVERSE_API_VERSION}/hd_tickets` +
      `?$filter=_hd_requestedby_value eq '${userId}'` +
      `&$orderby=createdon desc` +
      `&$top=${top}&$skip=${skip}` +
      `&$expand=hd_category($select=hd_name),hd_assignedto($select=fullname)` +
      `&$select=hd_ticketid,hd_ticketnumber,hd_title,hd_priority,hd_status,hd_duedate,hd_slabreach,createdon`;

    const response: HttpClientResponse = await this.client.get(
      url,
      AadHttpClient.configurations.v1
    );

    if (!response.ok) {
      throw new Error(
        `Failed to fetch tickets: ${response.status} ${response.statusText}`
      );
    }

    return response.json();
  }

  /**
   * Fetches tickets assigned to the current user's team (for agents).
   */
  async getTeamTickets(
    teamId: string,
    top: number = 50,
    skip: number = 0
  ): Promise<TicketListResponse> {
    const url =
      `${this.dataverseUrl}/api/data/${DATAVERSE_API_VERSION}/hd_tickets` +
      `?$filter=_hd_assignedteam_value eq '${teamId}'` +
      `&$orderby=hd_priority asc,createdon desc` +
      `&$top=${top}&$skip=${skip}` +
      `&$expand=hd_category($select=hd_name),hd_requestedby($select=fullname),hd_assignedto($select=fullname)` +
      `&$select=hd_ticketid,hd_ticketnumber,hd_title,hd_priority,hd_status,hd_duedate,hd_slabreach,createdon`;

    const response = await this.client.get(
      url,
      AadHttpClient.configurations.v1
    );

    if (!response.ok) {
      throw new Error(
        `Failed to fetch team tickets: ${response.status} ${response.statusText}`
      );
    }

    return response.json();
  }

  /**
   * Fetches a single ticket with all details and comments.
   */
  async getTicketDetails(ticketId: string): Promise<Ticket> {
    const url =
      `${this.dataverseUrl}/api/data/${DATAVERSE_API_VERSION}/hd_tickets(${ticketId})` +
      `?$expand=hd_category($select=hd_name),hd_assignedto($select=fullname),hd_requestedby($select=fullname)`;

    const response = await this.client.get(
      url,
      AadHttpClient.configurations.v1
    );

    if (!response.ok) {
      throw new Error(
        `Failed to fetch ticket: ${response.status} ${response.statusText}`
      );
    }

    return response.json();
  }

  /**
   * Fetches comments for a ticket.
   * Dataverse row-level security automatically filters out internal comments
   * for users without the HD-Agent role.
   */
  async getTicketComments(ticketId: string): Promise<TicketComment[]> {
    const url =
      `${this.dataverseUrl}/api/data/${DATAVERSE_API_VERSION}/hd_ticketcomments` +
      `?$filter=_hd_ticket_value eq '${ticketId}'` +
      `&$orderby=createdon desc` +
      `&$expand=createdby($select=fullname)` +
      `&$select=hd_ticketcommentid,hd_commentbody,hd_commenttype,createdon`;

    const response = await this.client.get(
      url,
      AadHttpClient.configurations.v1
    );

    if (!response.ok) {
      throw new Error(`Failed to fetch comments: ${response.status}`);
    }

    const data = await response.json();
    return data.value;
  }

  /**
   * Creates a new ticket.
   */
  async createTicket(ticket: {
    hd_title: string;
    hd_description: string;
    "hd_category@odata.bind": string;
    "hd_subcategory@odata.bind"?: string;
    hd_urgency: number;
    hd_impact: number;
  }): Promise<string> {
    const url = `${this.dataverseUrl}/api/data/${DATAVERSE_API_VERSION}/hd_tickets`;

    const response = await this.client.post(
      url,
      AadHttpClient.configurations.v1,
      {
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(ticket),
      }
    );

    if (!response.ok) {
      throw new Error(`Failed to create ticket: ${response.status}`);
    }

    // Extract ticket ID from the OData-EntityId header
    const entityId = response.headers.get("OData-EntityId");
    if (!entityId) throw new Error("No entity ID returned");

    const match = entityId.match(/\(([^)]+)\)/);
    return match ? match[1] : entityId;
  }
}
