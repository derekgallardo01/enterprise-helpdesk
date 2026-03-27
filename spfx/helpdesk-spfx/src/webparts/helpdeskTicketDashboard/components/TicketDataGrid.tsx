import * as React from "react";
import {
  Button,
  DataGrid,
  DataGridBody,
  DataGridCell,
  DataGridHeader,
  DataGridHeaderCell,
  DataGridRow,
  Skeleton,
  SkeletonItem,
  Subtitle1,
  Text,
  makeStyles,
  tokens,
  type DataGridProps,
  type TableColumnDefinition,
  createTableColumn,
} from "@fluentui/react-components";
import { ArrowDownFilled } from "@fluentui/react-icons";
import type { Ticket } from "../../../models/Types";
import { StatusBadge } from "../../../components/StatusBadge";
import { PriorityIcon } from "../../../components/PriorityIcon";

export interface ITicketDataGridProps {
  tickets: Ticket[];
  loading: boolean;
  hasMore: boolean;
  onRowClick: (ticket: Ticket) => void;
  onLoadMore: () => void;
}

const useStyles = makeStyles({
  container: {
    width: "100%",
  },
  emptyState: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    padding: "48px",
    gap: "12px",
    color: tokens.colorNeutralForeground3,
  },
  loadMore: {
    display: "flex",
    justifyContent: "center",
    paddingTop: "16px",
  },
  skeletonRow: {
    display: "flex",
    gap: "16px",
    padding: "8px 0",
  },
  clickableRow: {
    cursor: "pointer",
  },
});

const columns: TableColumnDefinition<Ticket>[] = [
  createTableColumn<Ticket>({
    columnId: "ticketNumber",
    compare: (a, b) => a.hd_ticketnumber.localeCompare(b.hd_ticketnumber),
    renderHeaderCell: () => "Ticket #",
    renderCell: (item) => (
      <Text weight="semibold">{item.hd_ticketnumber}</Text>
    ),
  }),
  createTableColumn<Ticket>({
    columnId: "title",
    compare: (a, b) => a.hd_title.localeCompare(b.hd_title),
    renderHeaderCell: () => "Title",
    renderCell: (item) => (
      <Text
        truncate
        wrap={false}
        style={{ maxWidth: "250px", display: "block" }}
      >
        {item.hd_title}
      </Text>
    ),
  }),
  createTableColumn<Ticket>({
    columnId: "status",
    compare: (a, b) => a.hd_status - b.hd_status,
    renderHeaderCell: () => "Status",
    renderCell: (item) => <StatusBadge status={item.hd_status} />,
  }),
  createTableColumn<Ticket>({
    columnId: "priority",
    compare: (a, b) => a.hd_priority - b.hd_priority,
    renderHeaderCell: () => "Priority",
    renderCell: (item) => <PriorityIcon priority={item.hd_priority} />,
  }),
  createTableColumn<Ticket>({
    columnId: "category",
    compare: (a, b) =>
      (a.hd_category?.hd_name || "").localeCompare(
        b.hd_category?.hd_name || ""
      ),
    renderHeaderCell: () => "Category",
    renderCell: (item) => (
      <Text>{item.hd_category?.hd_name || "—"}</Text>
    ),
  }),
  createTableColumn<Ticket>({
    columnId: "assignedTo",
    compare: (a, b) =>
      (a.hd_assignedto?.fullname || "").localeCompare(
        b.hd_assignedto?.fullname || ""
      ),
    renderHeaderCell: () => "Assigned To",
    renderCell: (item) => (
      <Text>{item.hd_assignedto?.fullname || "Unassigned"}</Text>
    ),
  }),
  createTableColumn<Ticket>({
    columnId: "created",
    compare: (a, b) =>
      new Date(a.createdon).getTime() - new Date(b.createdon).getTime(),
    renderHeaderCell: () => "Created",
    renderCell: (item) => (
      <Text>{new Date(item.createdon).toLocaleDateString()}</Text>
    ),
  }),
  createTableColumn<Ticket>({
    columnId: "dueDate",
    compare: (a, b) =>
      new Date(a.hd_duedate || 0).getTime() -
      new Date(b.hd_duedate || 0).getTime(),
    renderHeaderCell: () => "Due Date",
    renderCell: (item) => (
      <Text
        style={{
          color: item.hd_slabreach
            ? tokens.colorPaletteRedForeground1
            : undefined,
          fontWeight: item.hd_slabreach ? "bold" : undefined,
        }}
      >
        {item.hd_duedate
          ? new Date(item.hd_duedate).toLocaleDateString()
          : "—"}
      </Text>
    ),
  }),
];

/**
 * DataGrid component for displaying tickets with sortable columns.
 * Supports skeleton loading state, empty state, and "Load More" pagination.
 */
export const TicketDataGrid: React.FC<ITicketDataGridProps> = ({
  tickets,
  loading,
  hasMore,
  onRowClick,
  onLoadMore,
}) => {
  const styles = useStyles();
  const [sortState, setSortState] = React.useState<
    Parameters<NonNullable<DataGridProps["onSortChange"]>>[1]
  >({
    sortColumn: "created",
    sortDirection: "descending",
  });

  const onSortChange: DataGridProps["onSortChange"] = (_e, nextSortState) => {
    setSortState(nextSortState);
  };

  // Skeleton loading rows
  if (loading && tickets.length === 0) {
    return (
      <div className={styles.container}>
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className={styles.skeletonRow}>
            <Skeleton>
              <SkeletonItem style={{ width: "80px" }} />
            </Skeleton>
            <Skeleton>
              <SkeletonItem style={{ width: "200px" }} />
            </Skeleton>
            <Skeleton>
              <SkeletonItem style={{ width: "100px" }} />
            </Skeleton>
            <Skeleton>
              <SkeletonItem style={{ width: "80px" }} />
            </Skeleton>
            <Skeleton>
              <SkeletonItem style={{ width: "120px" }} />
            </Skeleton>
          </div>
        ))}
      </div>
    );
  }

  // Empty state
  if (!loading && tickets.length === 0) {
    return (
      <div className={styles.emptyState}>
        <Subtitle1>No tickets found</Subtitle1>
        <Text>
          Try adjusting your filters or create a new ticket to get started.
        </Text>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <DataGrid
        items={tickets}
        columns={columns}
        sortable
        sortState={sortState}
        onSortChange={onSortChange}
        getRowId={(item: Ticket) => item.hd_ticketid}
      >
        <DataGridHeader>
          <DataGridRow>
            {({ renderHeaderCell }) => (
              <DataGridHeaderCell>{renderHeaderCell()}</DataGridHeaderCell>
            )}
          </DataGridRow>
        </DataGridHeader>
        <DataGridBody<Ticket>>
          {({ item, rowId }) => (
            <DataGridRow<Ticket>
              key={rowId}
              className={styles.clickableRow}
              onClick={() => onRowClick(item)}
            >
              {({ renderCell }) => (
                <DataGridCell>{renderCell(item)}</DataGridCell>
              )}
            </DataGridRow>
          )}
        </DataGridBody>
      </DataGrid>

      {hasMore && (
        <div className={styles.loadMore}>
          <Button
            appearance="secondary"
            icon={<ArrowDownFilled />}
            onClick={onLoadMore}
            disabled={loading}
          >
            {loading ? "Loading..." : "Load More"}
          </Button>
        </div>
      )}
    </div>
  );
};
