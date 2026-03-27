import * as React from "react";
import {
  Button,
  Dropdown,
  Input,
  Option,
  Toolbar,
  makeStyles,
} from "@fluentui/react-components";
import {
  SearchRegular,
  DismissCircleRegular,
} from "@fluentui/react-icons";
import { TicketContext } from "../../../context/TicketContext";
import { StatusMap, PriorityMap } from "../../../models/Types";
import type { Category } from "../../../models/Types";

export interface ITicketFiltersProps {
  categories: Category[];
}

const useStyles = makeStyles({
  toolbar: {
    display: "flex",
    flexWrap: "wrap",
    gap: "8px",
    alignItems: "center",
    paddingBottom: "16px",
  },
});

const statusEntries = Object.entries(StatusMap).map(([key, label]) => ({
  value: key,
  label,
}));

const priorityEntries = Object.entries(PriorityMap).map(([key, label]) => ({
  value: key,
  label,
}));

/**
 * Horizontal filter toolbar for the ticket dashboard.
 * Dispatches SET_FILTER actions to TicketContext on changes.
 */
export const TicketFilters: React.FC<ITicketFiltersProps> = ({
  categories,
}) => {
  const styles = useStyles();
  const { state, dispatch } = React.useContext(TicketContext);
  const [searchText, setSearchText] = React.useState(
    state.filters.searchText || ""
  );
  const searchDebounceRef = React.useRef<ReturnType<typeof setTimeout> | null>(
    null
  );

  const handleStatusChange = (
    _e: unknown,
    data: { optionValue?: string }
  ): void => {
    dispatch({
      type: "SET_FILTER",
      payload: {
        status: data.optionValue ? parseInt(data.optionValue, 10) : undefined,
      },
    });
  };

  const handlePriorityChange = (
    _e: unknown,
    data: { optionValue?: string }
  ): void => {
    dispatch({
      type: "SET_FILTER",
      payload: {
        priority: data.optionValue
          ? parseInt(data.optionValue, 10)
          : undefined,
      },
    });
  };

  const handleCategoryChange = (
    _e: unknown,
    data: { optionValue?: string }
  ): void => {
    dispatch({
      type: "SET_FILTER",
      payload: { category: data.optionValue || undefined },
    });
  };

  const handleSearchChange = (
    _e: unknown,
    data: { value: string }
  ): void => {
    setSearchText(data.value);
    if (searchDebounceRef.current) {
      clearTimeout(searchDebounceRef.current);
    }
    searchDebounceRef.current = setTimeout(() => {
      dispatch({
        type: "SET_FILTER",
        payload: { searchText: data.value || undefined },
      });
    }, 300);
  };

  const handleClearFilters = (): void => {
    setSearchText("");
    dispatch({
      type: "SET_FILTER",
      payload: {
        status: undefined,
        priority: undefined,
        category: undefined,
        searchText: undefined,
      },
    });
  };

  const hasFilters =
    state.filters.status !== undefined ||
    state.filters.priority !== undefined ||
    state.filters.category !== undefined ||
    (state.filters.searchText && state.filters.searchText.length > 0);

  return (
    <Toolbar className={styles.toolbar}>
      <Input
        placeholder="Search ticket # or title..."
        value={searchText}
        onChange={handleSearchChange}
        contentBefore={<SearchRegular />}
        style={{ minWidth: "220px" }}
      />

      <Dropdown
        placeholder="Status"
        onOptionSelect={handleStatusChange}
        value={
          state.filters.status !== undefined
            ? StatusMap[state.filters.status]
            : ""
        }
        style={{ minWidth: "160px" }}
      >
        <Option value="" text="All Statuses">
          All Statuses
        </Option>
        {statusEntries.map((entry) => (
          <Option key={entry.value} value={entry.value} text={entry.label}>
            {entry.label}
          </Option>
        ))}
      </Dropdown>

      <Dropdown
        placeholder="Priority"
        onOptionSelect={handlePriorityChange}
        value={
          state.filters.priority !== undefined
            ? PriorityMap[state.filters.priority]
            : ""
        }
        style={{ minWidth: "140px" }}
      >
        <Option value="" text="All Priorities">
          All Priorities
        </Option>
        {priorityEntries.map((entry) => (
          <Option key={entry.value} value={entry.value} text={entry.label}>
            {entry.label}
          </Option>
        ))}
      </Dropdown>

      <Dropdown
        placeholder="Category"
        onOptionSelect={handleCategoryChange}
        value={
          categories.find(
            (c) => c.hd_categoryid === state.filters.category
          )?.hd_name || ""
        }
        style={{ minWidth: "160px" }}
      >
        <Option value="" text="All Categories">
          All Categories
        </Option>
        {categories.map((cat) => (
          <Option
            key={cat.hd_categoryid}
            value={cat.hd_categoryid}
            text={cat.hd_name}
          >
            {cat.hd_name}
          </Option>
        ))}
      </Dropdown>

      {hasFilters && (
        <Button
          appearance="subtle"
          icon={<DismissCircleRegular />}
          onClick={handleClearFilters}
        >
          Clear Filters
        </Button>
      )}
    </Toolbar>
  );
};
