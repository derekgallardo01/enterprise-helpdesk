import * as React from "react";
import {
  Skeleton,
  SkeletonItem,
  Subtitle1,
  Text,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import type { KBArticle } from "../../../models/Types";
import { KBArticleCard } from "../../../components/KBArticleCard";

export interface IKBSearchResultsProps {
  results: KBArticle[];
  loading: boolean;
  hasSearched: boolean;
  onFeedback: (articleRefId: string, helpful: boolean) => void;
}

const useStyles = makeStyles({
  grid: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fill, minmax(340px, 1fr))",
    gap: "16px",
    paddingTop: "16px",
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
  skeletonCard: {
    display: "flex",
    flexDirection: "column",
    gap: "8px",
    padding: "16px",
    borderRadius: "8px",
    border: `1px solid ${tokens.colorNeutralStroke2}`,
  },
});

/**
 * Responsive grid of KBArticleCard components with loading/empty states.
 */
export const KBSearchResults: React.FC<IKBSearchResultsProps> = ({
  results,
  loading,
  hasSearched,
  onFeedback,
}) => {
  const styles = useStyles();

  // Loading skeleton
  if (loading) {
    return (
      <div className={styles.grid}>
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className={styles.skeletonCard}>
            <Skeleton>
              <SkeletonItem style={{ width: "70%", height: "20px" }} />
            </Skeleton>
            <Skeleton>
              <SkeletonItem style={{ width: "40%", height: "16px" }} />
            </Skeleton>
            <Skeleton>
              <SkeletonItem style={{ width: "100%", height: "48px" }} />
            </Skeleton>
            <Skeleton>
              <SkeletonItem style={{ width: "60%", height: "16px" }} />
            </Skeleton>
          </div>
        ))}
      </div>
    );
  }

  // Initial state (no search yet)
  if (!hasSearched) {
    return (
      <div className={styles.emptyState}>
        <Subtitle1>Search the knowledge base to find answers</Subtitle1>
        <Text>
          Type a question or keywords in the search box above.
        </Text>
      </div>
    );
  }

  // No results
  if (results.length === 0) {
    return (
      <div className={styles.emptyState}>
        <Subtitle1>No articles found</Subtitle1>
        <Text>
          Would you like to submit a ticket? Our support team can help you
          directly.
        </Text>
      </div>
    );
  }

  // Results grid
  return (
    <div className={styles.grid}>
      {results.map((article) => (
        <KBArticleCard
          key={article.id}
          article={article}
          onFeedback={onFeedback}
        />
      ))}
    </div>
  );
};
