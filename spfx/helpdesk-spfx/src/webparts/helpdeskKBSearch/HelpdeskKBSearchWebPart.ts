import * as React from "react";
import * as ReactDom from "react-dom";
import { Version } from "@microsoft/sp-core-library";
import { MSGraphClientV3 } from "@microsoft/sp-http";
import {
  type IPropertyPaneConfiguration,
  PropertyPaneTextField,
} from "@microsoft/sp-property-pane";
import { BaseClientSideWebPart } from "@microsoft/sp-webpart-base";

/**
 * SPFx Web Part: Knowledge Base Search
 *
 * Provides full-text search across the SharePoint KB site using Microsoft Graph Search API.
 * Results rendered as Fluent UI v9 Card components with title, snippet, category, and
 * "Was this helpful?" feedback buttons.
 *
 * Uses MSGraphClientV3 for automatic token management from the SharePoint context.
 * Search query: POST /search/query with entityTypes: ["listItem"] scoped to the KB site.
 *
 * Key UX decisions:
 * - 300ms debounce on search input (prevents API spam while typing)
 * - Results open SharePoint page in current context (not new tab — feels native)
 * - Feedback buttons call Dataverse API to increment hd_KBArticleRef.hd_helpfulcount
 */

export interface IHelpdeskKBSearchWebPartProps {
  kbSiteUrl: string;
  dataverseUrl: string;
}

export default class HelpdeskKBSearchWebPart extends BaseClientSideWebPart<IHelpdeskKBSearchWebPartProps> {
  private _graphClient!: MSGraphClientV3;

  protected async onInit(): Promise<void> {
    this._graphClient = await this.context.msGraphClientFactory.getClient("3");
    return super.onInit();
  }

  public render(): void {
    // TODO: Replace with actual React KBSearch component once built
    const element = React.createElement("div", {}, [
      React.createElement("h2", { key: "title" }, "Knowledge Base Search"),
      React.createElement("input", {
        key: "search",
        type: "text",
        placeholder: "Search the knowledge base...",
        style: { width: "100%", padding: "8px", fontSize: "14px" },
      }),
      React.createElement(
        "p",
        { key: "status" },
        `Searching: ${this.properties.kbSiteUrl}`
      ),
    ]);

    ReactDom.render(element, this.domElement);
  }

  /**
   * Example Graph Search query structure:
   *
   * POST https://graph.microsoft.com/v1.0/search/query
   * {
   *   "requests": [{
   *     "entityTypes": ["listItem"],
   *     "query": { "queryString": "VPN setup" },
   *     "sharePointOneDriveOptions": {
   *       "includeContent": "privateContent"
   *     },
   *     "from": 0,
   *     "size": 10
   *   }]
   * }
   */

  protected onDispose(): void {
    ReactDom.unmountComponentAtNode(this.domElement);
  }

  protected get dataVersion(): Version {
    return Version.parse("1.0");
  }

  protected getPropertyPaneConfiguration(): IPropertyPaneConfiguration {
    return {
      pages: [
        {
          header: { description: "Knowledge Base Search Configuration" },
          groups: [
            {
              groupName: "Data Sources",
              groupFields: [
                PropertyPaneTextField("kbSiteUrl", {
                  label: "KB SharePoint Site URL",
                  description: "e.g., https://contoso.sharepoint.com/sites/ITHelpDesk",
                }),
                PropertyPaneTextField("dataverseUrl", {
                  label: "Dataverse Environment URL",
                  description: "For feedback tracking (hd_KBArticleRef)",
                }),
              ],
            },
          ],
        },
      ],
    };
  }
}
