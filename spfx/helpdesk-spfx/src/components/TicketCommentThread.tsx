import * as React from "react";
import {
  Badge,
  Body1,
  Button,
  Caption1,
  Divider,
  Spinner,
  Text,
  Textarea,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { SendFilled } from "@fluentui/react-icons";
import type { TicketComment } from "../models/Types";

export interface ITicketCommentThreadProps {
  comments: TicketComment[];
  loading: boolean;
  onAddComment: (body: string) => Promise<void>;
}

const useStyles = makeStyles({
  container: {
    display: "flex",
    flexDirection: "column",
    gap: "12px",
    paddingTop: "16px",
  },
  commentItem: {
    display: "flex",
    flexDirection: "column",
    gap: "4px",
    paddingLeft: "16px",
    borderLeft: `2px solid ${tokens.colorNeutralStroke2}`,
  },
  commentHeader: {
    display: "flex",
    alignItems: "center",
    gap: "8px",
  },
  addCommentRow: {
    display: "flex",
    gap: "8px",
    alignItems: "flex-end",
    marginTop: "8px",
  },
});

/**
 * Vertical timeline of ticket comments with an input to add new comments.
 * Internal comments (type=2) are marked with an "Internal" badge.
 */
export const TicketCommentThread: React.FC<ITicketCommentThreadProps> = ({
  comments,
  loading,
  onAddComment,
}) => {
  const styles = useStyles();
  const [newComment, setNewComment] = React.useState("");
  const [submitting, setSubmitting] = React.useState(false);

  const handleSubmit = async (): Promise<void> => {
    if (!newComment.trim()) return;
    setSubmitting(true);
    try {
      await onAddComment(newComment.trim());
      setNewComment("");
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) {
    return <Spinner size="small" label="Loading comments..." />;
  }

  return (
    <div className={styles.container}>
      <Text weight="semibold" size={400}>
        Comments ({comments.length})
      </Text>
      <Divider />

      {comments.length === 0 && (
        <Body1>No comments yet.</Body1>
      )}

      {comments.map((comment) => (
        <div key={comment.hd_ticketcommentid} className={styles.commentItem}>
          <div className={styles.commentHeader}>
            <Text weight="semibold" size={200}>
              {comment.createdby?.fullname || "Unknown"}
            </Text>
            <Caption1>
              {new Date(comment.createdon).toLocaleString()}
            </Caption1>
            {comment.hd_commenttype === 2 && (
              <Badge appearance="outline" color="warning" size="small">
                Internal
              </Badge>
            )}
          </div>
          <Body1>{comment.hd_commentbody}</Body1>
        </div>
      ))}

      <Divider />

      <div className={styles.addCommentRow}>
        <Textarea
          placeholder="Add a comment..."
          value={newComment}
          onChange={(_e, data) => setNewComment(data.value)}
          style={{ flex: 1 }}
          resize="vertical"
          disabled={submitting}
        />
        <Button
          appearance="primary"
          icon={<SendFilled />}
          onClick={handleSubmit}
          disabled={!newComment.trim() || submitting}
        >
          {submitting ? "Sending..." : "Send"}
        </Button>
      </div>
    </div>
  );
};
