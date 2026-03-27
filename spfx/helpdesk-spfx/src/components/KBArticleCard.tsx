import * as React from "react";
import {
  Badge,
  Body1,
  Button,
  Caption1,
  Card,
  CardHeader,
  CardPreview,
  Text,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import {
  EyeFilled,
  ThumbLikeFilled,
  ThumbDislikeFilled,
} from "@fluentui/react-icons";
import type { KBArticle } from "../models/Types";

export interface IKBArticleCardProps {
  article: KBArticle;
  onFeedback: (articleRefId: string, helpful: boolean) => void;
}

const useStyles = makeStyles({
  card: {
    width: "100%",
    maxWidth: "400px",
    cursor: "pointer",
  },
  snippet: {
    padding: "0 12px 12px 12px",
  },
  footer: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    padding: "0 12px 12px 12px",
    gap: "8px",
  },
  stats: {
    display: "flex",
    alignItems: "center",
    gap: "12px",
  },
  statItem: {
    display: "inline-flex",
    alignItems: "center",
    gap: "4px",
    color: tokens.colorNeutralForeground3,
  },
  feedbackButtons: {
    display: "flex",
    gap: "4px",
  },
});

/**
 * Card component displaying a knowledge base article summary.
 * Clicking the card navigates to the SharePoint page.
 * Thumbs up/down buttons record feedback to Dataverse.
 */
export const KBArticleCard: React.FC<IKBArticleCardProps> = ({
  article,
  onFeedback,
}) => {
  const styles = useStyles();
  const [feedbackGiven, setFeedbackGiven] = React.useState<boolean | null>(
    null
  );

  const handleCardClick = (): void => {
    window.open(article.url, "_self");
  };

  const handleFeedback = (
    e: React.MouseEvent,
    helpful: boolean
  ): void => {
    e.stopPropagation();
    if (feedbackGiven !== null) return; // Already voted
    if (article.articleRefId) {
      onFeedback(article.articleRefId, helpful);
      setFeedbackGiven(helpful);
    }
  };

  return (
    <Card className={styles.card} onClick={handleCardClick}>
      <CardHeader
        header={
          <Text weight="semibold" size={400}>
            {article.title}
          </Text>
        }
        description={
          article.category ? (
            <Badge appearance="outline" color="brand" size="small">
              {article.category}
            </Badge>
          ) : undefined
        }
      />

      <CardPreview>
        <div className={styles.snippet}>
          <Body1>{article.snippet}</Body1>
        </div>
      </CardPreview>

      <div className={styles.footer}>
        <div className={styles.stats}>
          <span className={styles.statItem}>
            <EyeFilled fontSize={14} />
            <Caption1>{article.viewCount}</Caption1>
          </span>
          <span className={styles.statItem}>
            <ThumbLikeFilled fontSize={14} />
            <Caption1>{article.helpfulCount}</Caption1>
          </span>
        </div>

        <div className={styles.feedbackButtons}>
          <Caption1 style={{ alignSelf: "center" }}>Helpful?</Caption1>
          <Button
            appearance={feedbackGiven === true ? "primary" : "subtle"}
            size="small"
            icon={<ThumbLikeFilled />}
            onClick={(e) => handleFeedback(e, true)}
            disabled={feedbackGiven !== null}
            aria-label="Yes, helpful"
          />
          <Button
            appearance={feedbackGiven === false ? "primary" : "subtle"}
            size="small"
            icon={<ThumbDislikeFilled />}
            onClick={(e) => handleFeedback(e, false)}
            disabled={feedbackGiven !== null}
            aria-label="Not helpful"
          />
        </div>
      </div>
    </Card>
  );
};
