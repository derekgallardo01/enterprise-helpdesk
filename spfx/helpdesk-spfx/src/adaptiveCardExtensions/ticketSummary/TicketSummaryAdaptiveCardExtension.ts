import { BaseAdaptiveCardExtension } from '@microsoft/sp-adaptive-card-extension-base';
import { AadHttpClient } from '@microsoft/sp-http';
import { CardView, ICardViewData } from './cardView/CardView';
import { QuickView, IQuickViewData } from './quickView/QuickView';

export interface ITicketSummaryState {
  openCount: number;
  breachCount: number;
  unassignedCount: number;
  loading: boolean;
}

export interface ITicketSummaryProperties {
  dataverseUrl: string;
  dashboardPageUrl: string;
}

const CARD_VIEW_ID = 'TICKET_SUMMARY_CARD';
const QUICK_VIEW_ID = 'TICKET_SUMMARY_QUICK';

export default class TicketSummaryAdaptiveCardExtension extends BaseAdaptiveCardExtension<
  ITicketSummaryProperties,
  ITicketSummaryState
> {
  private _aadClient!: AadHttpClient;

  public async onInit(): Promise<void> {
    this.state = {
      openCount: 0,
      breachCount: 0,
      unassignedCount: 0,
      loading: true,
    };

    this.cardNavigator.register(CARD_VIEW_ID, () => new CardView());
    this.quickViewNavigator.register(QUICK_VIEW_ID, () => new QuickView());

    this._aadClient = await this.context.aadHttpClientFactory.getClient(
      this.properties.dataverseUrl
    );

    await this._fetchTicketCounts();

    return Promise.resolve();
  }

  public get title(): string {
    return 'Help Desk Tickets';
  }

  public get iconProperty(): string {
    return 'Ticket';
  }

  private async _fetchTicketCounts(): Promise<void> {
    try {
      const baseUrl = `${this.properties.dataverseUrl}/api/data/v9.2/hd_tickets`;

      const [openRes, breachRes, unassignedRes] = await Promise.all([
        this._aadClient.get(
          `${baseUrl}?$filter=hd_status le 5&$count=true&$top=0`,
          AadHttpClient.configurations.v1
        ),
        this._aadClient.get(
          `${baseUrl}?$filter=hd_slabreach eq true and hd_status le 5&$count=true&$top=0`,
          AadHttpClient.configurations.v1
        ),
        this._aadClient.get(
          `${baseUrl}?$filter=_hd_assignedto_value eq null and hd_status le 2&$count=true&$top=0`,
          AadHttpClient.configurations.v1
        ),
      ]);

      const [openData, breachData, unassignedData] = await Promise.all([
        openRes.json(),
        breachRes.json(),
        unassignedRes.json(),
      ]);

      this.setState({
        openCount: openData['@odata.count'] ?? 0,
        breachCount: breachData['@odata.count'] ?? 0,
        unassignedCount: unassignedData['@odata.count'] ?? 0,
        loading: false,
      });
    } catch {
      this.setState({ loading: false });
    }
  }
}

export { CARD_VIEW_ID, QUICK_VIEW_ID };
