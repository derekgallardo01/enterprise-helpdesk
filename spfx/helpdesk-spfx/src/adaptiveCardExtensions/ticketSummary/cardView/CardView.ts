import {
  BasePrimaryTextCardView,
  IPrimaryTextCardParameters,
  IExternalLinkCardAction,
  IQuickViewCardAction,
} from '@microsoft/sp-adaptive-card-extension-base';
import {
  ITicketSummaryState,
  ITicketSummaryProperties,
  QUICK_VIEW_ID,
} from '../TicketSummaryAdaptiveCardExtension';

export interface ICardViewData {
  openCount: number;
  breachCount: number;
}

export class CardView extends BasePrimaryTextCardView<
  ITicketSummaryProperties,
  ITicketSummaryState
> {
  public get data(): IPrimaryTextCardParameters {
    const { openCount, breachCount, loading } = this.state;

    if (loading) {
      return {
        primaryText: 'Loading...',
        description: 'Fetching ticket data',
      };
    }

    return {
      primaryText: `${openCount} Open Tickets`,
      description:
        breachCount > 0
          ? `${breachCount} SLA breach${breachCount !== 1 ? 'es' : ''}`
          : 'All tickets within SLA',
    };
  }

  public get cardButtons(): (IExternalLinkCardAction | IQuickViewCardAction)[] {
    return [
      {
        title: 'View Details',
        action: {
          type: 'QuickView',
          parameters: { view: QUICK_VIEW_ID },
        },
      },
    ];
  }
}
