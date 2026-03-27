import { TicketService } from '../TicketService';

// Mock AadHttpClient
const createMockClient = (responseData: unknown, ok = true) => ({
  get: jest.fn().mockResolvedValue({
    ok,
    status: ok ? 200 : 500,
    statusText: ok ? 'OK' : 'Internal Server Error',
    json: jest.fn().mockResolvedValue(responseData),
    headers: { get: jest.fn().mockReturnValue(null) },
  }),
  post: jest.fn().mockResolvedValue({
    ok,
    status: ok ? 201 : 500,
    statusText: ok ? 'Created' : 'Internal Server Error',
    json: jest.fn().mockResolvedValue(responseData),
    headers: {
      get: jest.fn().mockReturnValue(
        'https://org.crm.dynamics.com/api/data/v9.2/hd_tickets(abc-123)'
      ),
    },
  }),
});

describe('TicketService', () => {
  const dataverseUrl = 'https://org.crm.dynamics.com';

  describe('getMyTickets', () => {
    it('should fetch tickets for a user with correct OData query', async () => {
      const mockData = {
        value: [
          { hd_ticketid: '1', hd_title: 'Test ticket', hd_status: 1, hd_priority: 3 },
        ],
      };
      const client = createMockClient(mockData);
      const service = new TicketService(client as any, dataverseUrl);

      const result = await service.getMyTickets('user-123', 50, 0);

      expect(result.value).toHaveLength(1);
      expect(result.value[0].hd_title).toBe('Test ticket');
      expect(client.get).toHaveBeenCalledTimes(1);

      const url = client.get.mock.calls[0][0] as string;
      expect(url).toContain("_hd_requestedby_value eq 'user-123'");
      expect(url).toContain('$top=50');
      expect(url).toContain('$skip=0');
      expect(url).toContain('$orderby=createdon desc');
      expect(url).toContain('$expand=hd_category');
    });

    it('should pass custom pagination parameters', async () => {
      const client = createMockClient({ value: [] });
      const service = new TicketService(client as any, dataverseUrl);

      await service.getMyTickets('user-123', 25, 50);

      const url = client.get.mock.calls[0][0] as string;
      expect(url).toContain('$top=25');
      expect(url).toContain('$skip=50');
    });

    it('should throw on failed response', async () => {
      const client = createMockClient({}, false);
      const service = new TicketService(client as any, dataverseUrl);

      await expect(service.getMyTickets('user-123')).rejects.toThrow(
        'Failed to fetch tickets'
      );
    });
  });

  describe('getTeamTickets', () => {
    it('should fetch tickets filtered by team', async () => {
      const client = createMockClient({ value: [] });
      const service = new TicketService(client as any, dataverseUrl);

      await service.getTeamTickets('team-456');

      const url = client.get.mock.calls[0][0] as string;
      expect(url).toContain("_hd_assignedteam_value eq 'team-456'");
      expect(url).toContain('$orderby=hd_priority asc,createdon desc');
    });
  });

  describe('getTicketDetails', () => {
    it('should fetch a single ticket by ID with expansions', async () => {
      const mockTicket = { hd_ticketid: 'abc-123', hd_title: 'Detail test' };
      const client = createMockClient(mockTicket);
      const service = new TicketService(client as any, dataverseUrl);

      const result = await service.getTicketDetails('abc-123');

      expect(result.hd_title).toBe('Detail test');
      const url = client.get.mock.calls[0][0] as string;
      expect(url).toContain('hd_tickets(abc-123)');
      expect(url).toContain('$expand=');
    });
  });

  describe('getTicketComments', () => {
    it('should fetch comments for a ticket', async () => {
      const mockComments = {
        value: [
          { hd_ticketcommentid: 'c1', hd_commentbody: 'Test comment', hd_commenttype: 1 },
        ],
      };
      const client = createMockClient(mockComments);
      const service = new TicketService(client as any, dataverseUrl);

      const result = await service.getTicketComments('ticket-789');

      expect(result).toHaveLength(1);
      expect(result[0].hd_commentbody).toBe('Test comment');
      const url = client.get.mock.calls[0][0] as string;
      expect(url).toContain("_hd_ticket_value eq 'ticket-789'");
    });
  });

  describe('createTicket', () => {
    it('should POST to Dataverse and return entity ID', async () => {
      const client = createMockClient({});
      const service = new TicketService(client as any, dataverseUrl);

      const ticketId = await service.createTicket({
        hd_title: 'New ticket',
        hd_description: 'Description',
        'hd_category@odata.bind': '/hd_categories(cat-1)',
        hd_urgency: 2,
        hd_impact: 2,
      });

      expect(ticketId).toBe('abc-123');
      expect(client.post).toHaveBeenCalledTimes(1);

      const url = client.post.mock.calls[0][0] as string;
      expect(url).toContain('/hd_tickets');
    });

    it('should throw on failed create', async () => {
      const client = createMockClient({}, false);
      const service = new TicketService(client as any, dataverseUrl);

      await expect(
        service.createTicket({
          hd_title: 'Test',
          hd_description: 'Test',
          'hd_category@odata.bind': '/hd_categories(cat-1)',
          hd_urgency: 3,
          hd_impact: 2,
        })
      ).rejects.toThrow('Failed to create ticket');
    });
  });
});
