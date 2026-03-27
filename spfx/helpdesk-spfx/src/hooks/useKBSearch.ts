import * as React from "react";
import type { KBArticle, KBSearchResult } from "../models/Types";
import type { MSGraphClientV3 } from "@microsoft/sp-http";

/**
 * Custom hook for debounced knowledge base search via Microsoft Graph Search API.
 * Implements a 300ms debounce to prevent excessive API calls while typing.
 */
export function useKBSearch(graphClient: MSGraphClientV3, kbSiteUrl: string) {
  const [query, setQuery] = React.useState("");
  const [results, setResults] = React.useState<KBArticle[]>([]);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const debounceRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  React.useEffect(() => {
    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
    }

    if (!query.trim()) {
      setResults([]);
      setLoading(false);
      setError(null);
      return;
    }

    setLoading(true);

    debounceRef.current = setTimeout(async () => {
      try {
        const searchRequest = {
          requests: [
            {
              entityTypes: ["listItem"],
              query: { queryString: query },
              sharePointOneDriveOptions: {
                includeContent: "privateContent",
              },
              from: 0,
              size: 10,
            },
          ],
        };

        const response = await graphClient
          .api("/search/query")
          .post(searchRequest);

        const hits =
          response?.value?.[0]?.hitsContainers?.[0]?.hits || [];

        const articles: KBArticle[] = hits.map(
          (hit: KBSearchResult) => ({
            id: hit.hitId,
            title:
              hit.resource?.listItem?.fields?.title ||
              hit.resource?.name ||
              "Untitled",
            snippet: hit.summary || "",
            url: hit.resource?.webUrl || "",
            category:
              hit.resource?.listItem?.fields?.category || undefined,
            viewCount: 0,
            helpfulCount: 0,
            notHelpfulCount: 0,
            articleRefId: undefined,
          })
        );

        setResults(articles);
        setError(null);
      } catch (err) {
        setError(
          err instanceof Error ? err.message : "Search failed."
        );
        setResults([]);
      } finally {
        setLoading(false);
      }
    }, 300);

    return () => {
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
      }
    };
  }, [query, graphClient, kbSiteUrl]);

  return {
    results,
    loading,
    error,
    query,
    setQuery,
  };
}
