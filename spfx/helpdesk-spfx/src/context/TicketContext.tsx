import * as React from "react";
import type { Ticket, TicketFilters, Category, Subcategory } from "../models/Types";

/**
 * Ticket dashboard state shape.
 */
export interface TicketState {
  tickets: Ticket[];
  selectedTicket: Ticket | null;
  categories: Category[];
  subcategories: Subcategory[];
  filters: TicketFilters;
  loading: boolean;
  error: string | null;
  page: number;
  hasMore: boolean;
}

/**
 * Actions dispatched to the ticket reducer.
 */
export type TicketAction =
  | { type: "LOAD_TICKETS"; payload: { tickets: Ticket[]; hasMore: boolean } }
  | { type: "APPEND_TICKETS"; payload: { tickets: Ticket[]; hasMore: boolean } }
  | { type: "SELECT_TICKET"; payload: Ticket | null }
  | { type: "CREATE_TICKET"; payload: Ticket }
  | { type: "SET_FILTER"; payload: Partial<TicketFilters> }
  | { type: "SET_PAGE"; payload: number }
  | { type: "SET_ERROR"; payload: string | null }
  | { type: "SET_LOADING"; payload: boolean }
  | { type: "SET_CATEGORIES"; payload: { categories: Category[]; subcategories: Subcategory[] } };

const initialState: TicketState = {
  tickets: [],
  selectedTicket: null,
  categories: [],
  subcategories: [],
  filters: {},
  loading: false,
  error: null,
  page: 0,
  hasMore: true,
};

function ticketReducer(state: TicketState, action: TicketAction): TicketState {
  switch (action.type) {
    case "LOAD_TICKETS":
      return {
        ...state,
        tickets: action.payload.tickets,
        hasMore: action.payload.hasMore,
        loading: false,
        error: null,
      };
    case "APPEND_TICKETS":
      return {
        ...state,
        tickets: [...state.tickets, ...action.payload.tickets],
        hasMore: action.payload.hasMore,
        loading: false,
      };
    case "SELECT_TICKET":
      return { ...state, selectedTicket: action.payload };
    case "CREATE_TICKET":
      return {
        ...state,
        tickets: [action.payload, ...state.tickets],
      };
    case "SET_FILTER":
      return {
        ...state,
        filters: { ...state.filters, ...action.payload },
        page: 0,
        tickets: [],
        hasMore: true,
      };
    case "SET_PAGE":
      return { ...state, page: action.payload };
    case "SET_ERROR":
      return { ...state, error: action.payload, loading: false };
    case "SET_LOADING":
      return { ...state, loading: action.payload };
    case "SET_CATEGORIES":
      return {
        ...state,
        categories: action.payload.categories,
        subcategories: action.payload.subcategories,
      };
    default:
      return state;
  }
}

export interface ITicketContext {
  state: TicketState;
  dispatch: React.Dispatch<TicketAction>;
}

export const TicketContext = React.createContext<ITicketContext>({
  state: initialState,
  dispatch: () => undefined,
});

/**
 * Provider component wrapping the ticket dashboard.
 * Manages all ticket state via useReducer.
 */
export const TicketProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const [state, dispatch] = React.useReducer(ticketReducer, initialState);

  const value = React.useMemo(() => ({ state, dispatch }), [state, dispatch]);

  return (
    <TicketContext.Provider value={value}>{children}</TicketContext.Provider>
  );
};
