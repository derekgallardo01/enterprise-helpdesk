import * as React from "react";
import {
  Body1,
  Button,
  Caption1,
  Divider,
  DrawerBody,
  DrawerHeader,
  DrawerHeaderTitle,
  OverlayDrawer,
  Subtitle2,
  Text,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DismissRegular, WarningFilled } from "@fluentui/react-icons";
import type { Ticket, TicketComment } from "../models/Types";
import { StatusBadge } from "./StatusBadge";
import { PriorityIcon } from "./PriorityIcon";
import { TicketCommentThread } from "./TicketCommentThread";

export interface ITicketDetailPanelProps {
  ticket: Ticket | null;
  comments: TicketComment[];
  commentsLoading: boolean;
  open: boolean;
  onClose: () => void;
  onAddComment: (body: string) => Promise<void>;
}

const useStyles = makeStyles({
  detailGrid: {
    display: "grid",
    gridTemplateColumns: "140px 1fr",
    gap: "8px 12px",
    paddingTop: "12px",
    paddingBottom: "12px",
  },
  label: {
    fontWeight: tokens.fontWeightSemibold,
    color: tokens.colorNeutralForeground3,
  },
  slaWarning: {
    display: "inline-flex",
    alignItems: "center",
    gap: "4px",
    color: tokens.colorPaletteRedForeground1,
    fontWeight: tokens.fontWeightSemibold,
  },
  description: {
    whiteSpace: "pre-wrap",
    paddingTop: "8px",
    paddingBottom: "8px",
  },
});

/**
 * Slide-in panel showing full ticket details and comment thread.
 * Uses Fluent UI v9 OverlayDrawer positioned on the right.
 */
export const TicketDetailPanel: React.FC<ITicketDetailPanelProps> = ({
  ticket,
  comments,
  commentsLoading,
  open,
  onClose,
  onAddComment,
}) => {
  const styles = useStyles();

  if (!ticket) return null;

  return (
    <OverlayDrawer
      open={open}
      onOpenChange={(_e, data) => {
        if (!data.open) onClose();
      }}
      position="end"
      size="medium"
    >
      <DrawerHeader>
        <DrawerHeaderTitle
          action={
            <Button
              appearance="subtle"
              aria-label="Close"
              icon={<DismissRegular />}
              onClick={onClose}
            />
          }
        >
          {ticket.hd_ticketnumber} - {ticket.hd_title}
        </DrawerHeaderTitle>
      </DrawerHeader>

      <DrawerBody>
        <div className={styles.detailGrid}>
          <Text className={styles.label}>Status</Text>
          <div>
            <StatusBadge status={ticket.hd_status} />
          </div>

          <Text className={styles.label}>Priority</Text>
          <div>
            <PriorityIcon priority={ticket.hd_priority} />
          </div>

          <Text className={styles.label}>Category</Text>
          <Body1>{ticket.hd_category?.hd_name || "Uncategorized"}</Body1>

          <Text className={styles.label}>Assigned To</Text>
          <Body1>{ticket.hd_assignedto?.fullname || "Unassigned"}</Body1>

          <Text className={styles.label}>Requester</Text>
          <Body1>{ticket.hd_requestedby?.fullname || "Unknown"}</Body1>

          <Text className={styles.label}>Created</Text>
          <Body1>{new Date(ticket.createdon).toLocaleString()}</Body1>

          <Text className={styles.label}>Due Date</Text>
          <Body1>
            {ticket.hd_duedate
              ? new Date(ticket.hd_duedate).toLocaleString()
              : "Not set"}
          </Body1>

          {ticket.hd_resolutiondate && (
            <>
              <Text className={styles.label}>Resolved</Text>
              <Body1>
                {new Date(ticket.hd_resolutiondate).toLocaleString()}
              </Body1>
            </>
          )}

          {ticket.hd_slabreach && (
            <>
              <Text className={styles.label}>SLA</Text>
              <div className={styles.slaWarning}>
                <WarningFilled />
                <Text>SLA Breach</Text>
              </div>
            </>
          )}
        </div>

        <Divider />

        <Subtitle2 style={{ paddingTop: "12px" }}>Description</Subtitle2>
        <div className={styles.description}>
          <Body1>{ticket.hd_description || "No description provided."}</Body1>
        </div>

        <Divider />

        <TicketCommentThread
          comments={comments}
          loading={commentsLoading}
          onAddComment={onAddComment}
        />
      </DrawerBody>
    </OverlayDrawer>
  );
};
