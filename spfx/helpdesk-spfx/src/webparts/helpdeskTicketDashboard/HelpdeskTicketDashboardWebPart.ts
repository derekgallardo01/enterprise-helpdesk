import * as React from "react";
import * as ReactDom from "react-dom";
import { Version } from "@microsoft/sp-core-library";
import { AadHttpClient } from "@microsoft/sp-http";
import {
  type IPropertyPaneConfiguration,
  PropertyPaneTextField,
  PropertyPaneSlider,
} from "@microsoft/sp-property-pane";
import { BaseClientSideWebPart } from "@microsoft/sp-webpart-base";
import { TicketService } from "../../services/TicketService";

/**
 * SPFx Web Part: Help Desk Ticket Dashboard
 *
 * Displays the current user's tickets in a Fluent UI v9 DataGrid with:
 * - Status badges with semantic colors
 * - Priority indicators
 * - Click-to-expand ticket detail panel
 * - New Ticket button with slide-in form
 *
 * Architecture decision (ADR-003): SPFx web parts load in < 1 second vs 3-5 seconds
 * for Power Apps iframes. They inherit SharePoint theming automatically and authenticate
 * via AadHttpClient with zero user prompts.
 *
 * Data source: Dataverse Web API via AadHttpClient (registered Entra ID app with
 * Dataverse user_impersonation scope).
 */

export interface IHelpdeskTicketDashboardProps {
  dataverseUrl: string;
  maxTickets: number;
  ticketService: TicketService;
  userId: string;
}

export interface IHelpdeskTicketDashboardWebPartProps {
  dataverseUrl: string;
  maxTickets: number;
}

export default class HelpdeskTicketDashboardWebPart extends BaseClientSideWebPart<IHelpdeskTicketDashboardWebPartProps> {
  private _aadClient!: AadHttpClient;
  private _ticketService!: TicketService;

  protected async onInit(): Promise<void> {
    // AadHttpClient gets tokens from the SharePoint context automatically.
    // The Dataverse app registration must be configured in the SPFx API permissions
    // with the Dataverse user_impersonation scope.
    this._aadClient = await this.context.aadHttpClientFactory.getClient(
      this.properties.dataverseUrl
    );

    this._ticketService = new TicketService(
      this._aadClient,
      this.properties.dataverseUrl
    );

    return super.onInit();
  }

  public render(): void {
    // TODO: Replace with actual React component import once TicketDashboard component is built
    const element = React.createElement("div", {}, [
      React.createElement(
        "h2",
        { key: "title" },
        "Help Desk - My Tickets"
      ),
      React.createElement(
        "p",
        { key: "status" },
        `Connected to Dataverse: ${this.properties.dataverseUrl}`
      ),
      React.createElement(
        "p",
        { key: "config" },
        `Showing up to ${this.properties.maxTickets} tickets`
      ),
    ]);

    ReactDom.render(element, this.domElement);
  }

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
          header: { description: "Help Desk Ticket Dashboard Configuration" },
          groups: [
            {
              groupName: "Data Source",
              groupFields: [
                PropertyPaneTextField("dataverseUrl", {
                  label: "Dataverse Environment URL",
                  description:
                    "e.g., https://your-org.crm.dynamics.com",
                }),
                PropertyPaneSlider("maxTickets", {
                  label: "Maximum Tickets to Display",
                  min: 10,
                  max: 100,
                  step: 10,
                  value: 50,
                }),
              ],
            },
          ],
        },
      ],
    };
  }
}
