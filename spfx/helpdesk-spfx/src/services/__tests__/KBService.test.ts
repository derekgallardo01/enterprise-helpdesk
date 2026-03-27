import { KBService } from '../KBService';

const createMockGraphClient = (responseData: unknown) => ({
  api: jest.fn().mockReturnValue({
    post: jest.fn().mockResolvedValue(responseData),
  }),
});

const createMockAadClient = (ok = true) => ({
  fetch: jest.fn().mockResolvedValue({
    ok,
    status: ok ? 204 : 500,
  }),
});

describe('KBService', () => {
  const kbSiteUrl = 'https://contoso.sharepoint.com/sites/ITHelpDesk';
  const dataverseUrl = 'https://org.crm.dynamics.com';

  describe('search', () => {
    it('should execute Graph Search with correct query structure', async () => {
      const mockResponse = {
        value: [
          {
            hitsContainers: [
              {
                hits: [
                  {
                    resource: {
                      id: 'article-1',
                      name: 'VPN Setup Guide',
                      webUrl: 'https://contoso.sharepoint.com/sites/ITHelpDesk/VPN',
                    },
                    summary: 'How to configure VPN access...',
                  },
                ],
                total: 1,
              },
            ],
          },
        ],
      };

      const graphClient = createMockGraphClient(mockResponse);
      const aadClient = createMockAadClient();
      const service = new KBService(graphClient as any, aadClient as any, dataverseUrl);

      const results = await service.search('VPN setup', kbSiteUrl);

      expect(graphClient.api).toHaveBeenCalledWith('/search/query');
      expect(results).toHaveLength(1);
      expect(results[0].title).toBe('VPN Setup Guide');
      expect(results[0].url).toContain('VPN');
    });

    it('should return empty array when no results found', async () => {
      const mockResponse = {
        value: [{ hitsContainers: [{ hits: [], total: 0 }] }],
      };

      const graphClient = createMockGraphClient(mockResponse);
      const aadClient = createMockAadClient();
      const service = new KBService(graphClient as any, aadClient as any, dataverseUrl);

      const results = await service.search('nonexistent topic', kbSiteUrl);

      expect(results).toHaveLength(0);
    });

    it('should handle Graph API errors gracefully', async () => {
      const graphClient = {
        api: jest.fn().mockReturnValue({
          post: jest.fn().mockRejectedValue(new Error('Graph API error')),
        }),
      };
      const aadClient = createMockAadClient();
      const service = new KBService(graphClient as any, aadClient as any, dataverseUrl);

      await expect(service.search('test', kbSiteUrl)).rejects.toThrow('Graph API error');
    });
  });

  describe('submitFeedback', () => {
    it('should call Dataverse API to record feedback', async () => {
      const graphClient = createMockGraphClient({});
      const aadClient = createMockAadClient();
      const service = new KBService(graphClient as any, aadClient as any, dataverseUrl);

      await service.submitFeedback('ref-123', true);

      expect(aadClient.fetch).toHaveBeenCalledTimes(1);
      const url = aadClient.fetch.mock.calls[0][0] as string;
      expect(url).toContain('hd_kbarticlerefs(ref-123)');
    });
  });
});
