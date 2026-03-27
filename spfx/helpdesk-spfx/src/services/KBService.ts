import type { MSGraphClientV3 } from "@microsoft/sp-http";
import { AadHttpClient } from "@microsoft/sp-http";
import type { KBArticle, KBSearchResult } from "../models/Types";

const DATAVERSE_API_VERSION = "v9.2";

/**
 * Service for knowledge base operations.
 *
 * Uses MSGraphClientV3 for SharePoint search and AadHttpClient for
 * Dataverse feedback tracking (hd_kbarticlerefs).
 */
export class KBService {
  private readonly graphClient: MSGraphClientV3;
  private readonly aadClient: AadHttpClient;
  private readonly dataverseUrl: string;

  constructor(
    graphClient: MSGraphClientV3,
    aadClient: AadHttpClient,
    dataverseUrl: string
  ) {
    this.graphClient = graphClient;
    this.aadClient = aadClient;
    this.dataverseUrl = dataverseUrl;
  }

  /**
   * Searches the KB SharePoint site using Microsoft Graph Search API.
   * Returns articles with titles, snippets, and URLs.
   */
  async search(query: string, kbSiteUrl: string): Promise<KBArticle[]> {
    if (!query.trim()) return [];

    const searchRequest = {
      requests: [
        {
          entityTypes: ["listItem"],
          query: {
            queryString: `${query} site:${kbSiteUrl}`,
          },
          sharePointOneDriveOptions: {
            includeContent: "privateContent",
          },
          from: 0,
          size: 10,
        },
      ],
    };

    const response = await this.graphClient
      .api("/search/query")
      .post(searchRequest);

    const hits =
      response?.value?.[0]?.hitsContainers?.[0]?.hits || [];

    return hits.map((hit: KBSearchResult) => ({
      id: hit.hitId,
      title:
        hit.resource?.listItem?.fields?.title ||
        hit.resource?.name ||
        "Untitled",
      snippet: hit.summary || "",
      url: hit.resource?.webUrl || "",
      category: hit.resource?.listItem?.fields?.category || undefined,
      viewCount: 0,
      helpfulCount: 0,
      notHelpfulCount: 0,
      articleRefId: undefined,
    }));
  }

  /**
   * Records a view for a KB article reference in Dataverse.
   * Increments the hd_viewcount field on the hd_kbarticlerefs entity.
   */
  async recordView(articleRefId: string): Promise<void> {
    const url =
      `${this.dataverseUrl}/api/data/${DATAVERSE_API_VERSION}` +
      `/hd_kbarticlerefs(${articleRefId})`;

    // Fetch current view count
    const getResponse = await this.aadClient.get(
      url + "?$select=hd_viewcount",
      AadHttpClient.configurations.v1
    );

    if (!getResponse.ok) {
      throw new Error(`Failed to fetch article ref: ${getResponse.status}`);
    }

    const data = await getResponse.json();
    const currentCount = data.hd_viewcount || 0;

    // Increment
    const patchResponse = await this.aadClient.fetch(
      url,
      AadHttpClient.configurations.v1,
      {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ hd_viewcount: currentCount + 1 }),
      }
    );

    if (!patchResponse.ok) {
      throw new Error(`Failed to record view: ${patchResponse.status}`);
    }
  }

  /**
   * Submits helpful/not-helpful feedback for a KB article reference.
   * Increments the appropriate counter field in Dataverse.
   */
  async submitFeedback(
    articleRefId: string,
    helpful: boolean
  ): Promise<void> {
    const url =
      `${this.dataverseUrl}/api/data/${DATAVERSE_API_VERSION}` +
      `/hd_kbarticlerefs(${articleRefId})`;

    const field = helpful ? "hd_helpfulcount" : "hd_nothelpfulcount";

    // Fetch current count
    const getResponse = await this.aadClient.get(
      `${url}?$select=${field}`,
      AadHttpClient.configurations.v1
    );

    if (!getResponse.ok) {
      throw new Error(`Failed to fetch article ref: ${getResponse.status}`);
    }

    const data = await getResponse.json();
    const currentCount = data[field] || 0;

    // Increment
    const patchResponse = await this.aadClient.fetch(
      url,
      AadHttpClient.configurations.v1,
      {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ [field]: currentCount + 1 }),
      }
    );

    if (!patchResponse.ok) {
      throw new Error(`Failed to submit feedback: ${patchResponse.status}`);
    }
  }
}
