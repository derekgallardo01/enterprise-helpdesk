/**
 * Shared type definitions for the Enterprise Help Desk SPFx solution.
 *
 * Re-exports core interfaces from TicketService and adds UI-specific types
 * for KB articles and enum display maps.
 */

// Re-export Dataverse entity interfaces from TicketService
export type {
  Ticket,
  TicketComment,
  TicketListResponse,
} from "../services/TicketService";

/** Dataverse hd_category entity */
export interface Category {
  hd_categoryid: string;
  hd_name: string;
}

/** Dataverse hd_subcategory entity */
export interface Subcategory {
  hd_subcategoryid: string;
  hd_name: string;
  _hd_parentcategory_value: string;
}

/** Filter criteria for the ticket dashboard */
export interface TicketFilters {
  status?: number;
  priority?: number;
  category?: string;
  searchText?: string;
}

/** SharePoint KB article surfaced via Graph Search */
export interface KBArticle {
  id: string;
  title: string;
  snippet: string;
  url: string;
  category?: string;
  viewCount: number;
  helpfulCount: number;
  notHelpfulCount: number;
  articleRefId?: string; // Dataverse hd_kbarticleref ID for feedback
}

/** Single result from the Graph Search API */
export interface KBSearchResult {
  hitId: string;
  summary: string;
  resource: {
    id: string;
    name: string;
    webUrl: string;
    listItem?: {
      fields?: {
        title?: string;
        category?: string;
        [key: string]: unknown;
      };
    };
  };
}

/** Status code to display label mapping */
export const StatusMap: Record<number, string> = {
  1: "New",
  2: "Assigned",
  3: "In Progress",
  4: "Waiting on Customer",
  5: "Waiting on Third Party",
  6: "Resolved",
  7: "Closed",
  8: "Cancelled",
};

/** Priority code to display label mapping */
export const PriorityMap: Record<number, string> = {
  1: "Critical",
  2: "High",
  3: "Medium",
  4: "Low",
};
