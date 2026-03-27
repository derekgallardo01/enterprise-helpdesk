import * as React from "react";
import {
  FluentProvider,
  Input,
  MessageBar,
  MessageBarBody,
  Title2,
  makeStyles,
  tokens,
  webLightTheme,
} from "@fluentui/react-components";
import { SearchRegular } from "@fluentui/react-icons";
import type { MSGraphClientV3 } from "@microsoft/sp-http";
import type { AadHttpClient } from "@microsoft/sp-http";
import { useKBSearch } from "../../../hooks/useKBSearch";
import { KBSearchResults } from "./KBSearchResults";
import { KBService } from "../../../services/KBService";

export interface IKBSearchProps {
  graphClient: MSGraphClientV3;
  kbSiteUrl: string;
  dataverseUrl: string;
  aadClient: AadHttpClient;
}

const useStyles = makeStyles({
  root: {
    display: "flex",
    flexDirection: "column",
    gap: "16px",
    padding: "16px",
  },
  title: {
    color: tokens.colorNeutralForeground1,
  },
  searchBox: {
    maxWidth: "600px",
    width: "100%",
  },
});

/**
 * Main KB Search component.
 * Provides a search input wired to the Graph Search API via useKBSearch hook.
 * Feedback buttons delegate to KBService for Dataverse updates.
 */
export const KBSearch: React.FC<IKBSearchProps> = ({
  graphClient,
  kbSiteUrl,
  dataverseUrl,
  aadClient,
}) => {
  const styles = useStyles();
  const { results, loading, error, query, setQuery } = useKBSearch(
    graphClient,
    kbSiteUrl
  );

  const kbService = React.useMemo(
    () => new KBService(graphClient, aadClient, dataverseUrl),
    [graphClient, aadClient, dataverseUrl]
  );

  const handleFeedback = (articleRefId: string, helpful: boolean): void => {
    kbService.submitFeedback(articleRefId, helpful).catch((err) => {
      console.error("Failed to submit feedback:", err);
    });
  };

  return (
    <FluentProvider theme={webLightTheme}>
      <div className={styles.root}>
        <Title2 className={styles.title}>Knowledge Base</Title2>

        <Input
          className={styles.searchBox}
          placeholder="Search the knowledge base..."
          value={query}
          onChange={(_e, data) => setQuery(data.value)}
          contentBefore={<SearchRegular />}
          size="large"
        />

        {error && (
          <MessageBar intent="error">
            <MessageBarBody>{error}</MessageBarBody>
          </MessageBar>
        )}

        <KBSearchResults
          results={results}
          loading={loading}
          hasSearched={query.trim().length > 0}
          onFeedback={handleFeedback}
        />
      </div>
    </FluentProvider>
  );
};
