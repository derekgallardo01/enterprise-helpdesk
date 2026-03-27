import {
  BaseAdaptiveCardQuickView,
  ISPFxAdaptiveCard,
} from '@microsoft/sp-adaptive-card-extension-base';
import {
  ITicketSummaryState,
  ITicketSummaryProperties,
} from '../TicketSummaryAdaptiveCardExtension';

export interface IQuickViewData {
  openCount: number;
  breachCount: number;
  unassignedCount: number;
  dashboardUrl: string;
}

export class QuickView extends BaseAdaptiveCardQuickView<
  ITicketSummaryProperties,
  ITicketSummaryState,
  IQuickViewData
> {
  public get data(): IQuickViewData {
    return {
      openCount: this.state.openCount,
      breachCount: this.state.breachCount,
      unassignedCount: this.state.unassignedCount,
      dashboardUrl: this.properties.dashboardPageUrl || '#',
    };
  }

  public get template(): ISPFxAdaptiveCard {
    return {
      $schema: 'http://adaptivecards.io/schemas/adaptive-card.json',
      type: 'AdaptiveCard',
      version: '1.5',
      body: [
        {
          type: 'TextBlock',
          text: 'Help Desk Summary',
          weight: 'Bolder',
          size: 'Large',
        },
        {
          type: 'ColumnSet',
          columns: [
            {
              type: 'Column',
              width: 'stretch',
              items: [
                {
                  type: 'TextBlock',
                  text: '${openCount}',
                  size: 'ExtraLarge',
                  weight: 'Bolder',
                  color: 'Accent',
                  horizontalAlignment: 'Center',
                },
                {
                  type: 'TextBlock',
                  text: 'Open',
                  horizontalAlignment: 'Center',
                  isSubtle: true,
                },
              ],
            },
            {
              type: 'Column',
              width: 'stretch',
              items: [
                {
                  type: 'TextBlock',
                  text: '${breachCount}',
                  size: 'ExtraLarge',
                  weight: 'Bolder',
                  color: 'Attention',
                  horizontalAlignment: 'Center',
                },
                {
                  type: 'TextBlock',
                  text: 'SLA Breach',
                  horizontalAlignment: 'Center',
                  isSubtle: true,
                },
              ],
            },
            {
              type: 'Column',
              width: 'stretch',
              items: [
                {
                  type: 'TextBlock',
                  text: '${unassignedCount}',
                  size: 'ExtraLarge',
                  weight: 'Bolder',
                  color: 'Warning',
                  horizontalAlignment: 'Center',
                },
                {
                  type: 'TextBlock',
                  text: 'Unassigned',
                  horizontalAlignment: 'Center',
                  isSubtle: true,
                },
              ],
            },
          ],
        },
      ],
      actions: [
        {
          type: 'Action.OpenUrl',
          title: 'View All Tickets',
          url: '${dashboardUrl}',
        },
      ],
    } as unknown as ISPFxAdaptiveCard;
  }
}
