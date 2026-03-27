import * as React from "react";
import { TicketContext } from "../context/TicketContext";
import type { TicketService } from "../services/TicketService";
import type { Ticket, TicketFilters } from "../models/Types";

const PAGE_SIZE = 50;

/**
 * Custom hook wrapping TicketContext for convenient access to ticket operations.
 * All Dataverse calls are delegated to TicketService.
 */
export function useTickets(ticketService: TicketService, userId: string) {
  const { state, dispatch } = React.useContext(TicketContext);

  const loadTickets = React.useCallback(
    async (page: number = 0): Promise<void> => {
      dispatch({ type: "SET_LOADING", payload: true });
      try {
        const skip = page * PAGE_SIZE;
        const response = await ticketService.getMyTickets(
          userId,
          PAGE_SIZE,
          skip
        );
        const hasMore = !!response["@odata.nextLink"];

        if (page === 0) {
          dispatch({
            type: "LOAD_TICKETS",
            payload: { tickets: response.value, hasMore },
          });
        } else {
          dispatch({
            type: "APPEND_TICKETS",
            payload: { tickets: response.value, hasMore },
          });
        }
      } catch (err) {
        dispatch({
          type: "SET_ERROR",
          payload:
            err instanceof Error ? err.message : "Failed to load tickets.",
        });
      }
    },
    [ticketService, userId, dispatch]
  );

  const selectTicket = React.useCallback(
    async (ticket: Ticket | null): Promise<void> => {
      if (!ticket) {
        dispatch({ type: "SELECT_TICKET", payload: null });
        return;
      }
      // Fetch full details
      try {
        const details = await ticketService.getTicketDetails(
          ticket.hd_ticketid
        );
        dispatch({ type: "SELECT_TICKET", payload: details });
      } catch (err) {
        dispatch({
          type: "SET_ERROR",
          payload:
            err instanceof Error
              ? err.message
              : "Failed to load ticket details.",
        });
      }
    },
    [ticketService, dispatch]
  );

  const createTicket = React.useCallback(
    async (ticketData: Parameters<TicketService["createTicket"]>[0]): Promise<void> => {
      dispatch({ type: "SET_LOADING", payload: true });
      try {
        await ticketService.createTicket(ticketData);
        // Reload tickets to show the new one
        await loadTickets(0);
      } catch (err) {
        dispatch({
          type: "SET_ERROR",
          payload:
            err instanceof Error ? err.message : "Failed to create ticket.",
        });
      }
    },
    [ticketService, dispatch, loadTickets]
  );

  const setFilter = React.useCallback(
    (filters: Partial<TicketFilters>): void => {
      dispatch({ type: "SET_FILTER", payload: filters });
    },
    [dispatch]
  );

  const nextPage = React.useCallback((): void => {
    const next = state.page + 1;
    dispatch({ type: "SET_PAGE", payload: next });
    loadTickets(next).catch(() => {
      /* error handled in loadTickets */
    });
  }, [state.page, dispatch, loadTickets]);

  return {
    tickets: state.tickets,
    selectedTicket: state.selectedTicket,
    loading: state.loading,
    error: state.error,
    filters: state.filters,
    hasMore: state.hasMore,
    categories: state.categories,
    subcategories: state.subcategories,
    loadTickets,
    selectTicket,
    createTicket,
    setFilter,
    nextPage,
  };
}
