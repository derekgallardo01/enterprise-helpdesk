import * as React from "react";
import {
  FluentProvider,
  webLightTheme,
  Title2,
  MessageBar,
  MessageBarBody,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { TicketProvider, TicketContext } from "../../../context/TicketContext";
import { useTickets } from "../../../hooks/useTickets";
import { TicketFilters } from "./TicketFilters";
import { TicketDataGrid } from "./TicketDataGrid";
import { TicketDetailPanel } from "../../../components/TicketDetailPanel";
import { NewTicketForm } from "../../../components/NewTicketForm";
import type { TicketService } from "../../../services/TicketService";
import type { TicketComment } from "../../../models/Types";

export interface ITicketDashboardProps {
  ticketService: TicketService;
  userId: string;
}

const useStyles = makeStyles({
  root: {
    display: "flex",
    flexDirection: "column",
    gap: "16px",
    padding: "16px",
  },
  header: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    flexWrap: "wrap",
    gap: "12px",
  },
  title: {
    color: tokens.colorNeutralForeground1,
  },
});

/**
 * Inner dashboard component that consumes TicketContext.
 */
const DashboardInner: React.FC<ITicketDashboardProps> = ({
  ticketService,
  userId,
}) => {
  const styles = useStyles();
  const {
    tickets,
    selectedTicket,
    loading,
    error,
    hasMore,
    categories,
    subcategories,
    loadTickets,
    selectTicket,
    nextPage,
  } = useTickets(ticketService, userId);

  const { state } = React.useContext(TicketContext);

  const [comments, setComments] = React.useState<TicketComment[]>([]);
  const [commentsLoading, setCommentsLoading] = React.useState(false);
  const [panelOpen, setPanelOpen] = React.useState(false);

  // Initial load
  React.useEffect(() => {
    loadTickets(0).catch(() => {
      /* error handled in hook */
    });
  }, [loadTickets, state.filters]);

  // Load comments when a ticket is selected
  React.useEffect(() => {
    if (selectedTicket) {
      setCommentsLoading(true);
      ticketService
        .getTicketComments(selectedTicket.hd_ticketid)
        .then((c) => {
          setComments(c);
          setCommentsLoading(false);
        })
        .catch(() => {
          setComments([]);
          setCommentsLoading(false);
        });
    }
  }, [selectedTicket, ticketService]);

  const handleRowClick = async (ticket: typeof tickets[0]): Promise<void> => {
    await selectTicket(ticket);
    setPanelOpen(true);
  };

  const handleClosePanel = (): void => {
    setPanelOpen(false);
    selectTicket(null).catch(() => {
      /* error handled */
    });
  };

  const handleAddComment = async (body: string): Promise<void> => {
    // For now, comments are read-only; this would call a comment creation endpoint
    // Placeholder: reload comments after adding
    if (selectedTicket) {
      const updated = await ticketService.getTicketComments(
        selectedTicket.hd_ticketid
      );
      setComments(updated);
    }
    void body;
  };

  const handleTicketCreated = (): void => {
    loadTickets(0).catch(() => {
      /* error handled */
    });
  };

  return (
    <div className={styles.root}>
      <div className={styles.header}>
        <Title2 className={styles.title}>My Tickets</Title2>
        <NewTicketForm
          ticketService={ticketService}
          categories={categories}
          subcategories={subcategories}
          onTicketCreated={handleTicketCreated}
        />
      </div>

      {error && (
        <MessageBar intent="error">
          <MessageBarBody>{error}</MessageBarBody>
        </MessageBar>
      )}

      <TicketFilters categories={categories} />

      <TicketDataGrid
        tickets={tickets}
        loading={loading}
        hasMore={hasMore}
        onRowClick={handleRowClick}
        onLoadMore={nextPage}
      />

      <TicketDetailPanel
        ticket={selectedTicket}
        comments={comments}
        commentsLoading={commentsLoading}
        open={panelOpen}
        onClose={handleClosePanel}
        onAddComment={handleAddComment}
      />
    </div>
  );
};

/**
 * Main dashboard component. Wraps inner component with FluentProvider
 * and TicketContext.Provider for state management.
 */
export const TicketDashboard: React.FC<ITicketDashboardProps> = (props) => {
  return (
    <FluentProvider theme={webLightTheme}>
      <TicketProvider>
        <DashboardInner {...props} />
      </TicketProvider>
    </FluentProvider>
  );
};
