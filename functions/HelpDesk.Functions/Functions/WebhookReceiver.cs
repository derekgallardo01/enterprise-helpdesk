using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Xrm.Sdk;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Functions;

/// <summary>
/// Receives webhooks from external ITSM tools (ServiceNow, Jira) for migration/hybrid scenarios.
/// Validates HMAC signature on incoming payloads to prevent unauthorized ticket creation.
///
/// Demonstrates: "Guide integration strategies with external systems" (job post requirement 5).
/// </summary>
public class WebhookReceiver
{
    private readonly ILogger<WebhookReceiver> _logger;
    private readonly DataverseService _dataverseService;
    private readonly string _webhookSecret;

    public WebhookReceiver(
        DataverseService dataverseService,
        IConfiguration configuration,
        ILogger<WebhookReceiver> logger)
    {
        _dataverseService = dataverseService;
        _logger = logger;
        _webhookSecret = configuration["WebhookSecret"]
            ?? throw new InvalidOperationException("WebhookSecret not configured");
    }

    [Function("WebhookReceiver")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "webhook/{source}")] HttpRequestData req,
        string source)
    {
        _logger.LogInformation("Webhook received from source: {Source}", source);

        // Read request body
        var bodyBytes = await ReadBodyAsync(req.Body);
        var bodyString = Encoding.UTF8.GetString(bodyBytes);

        // Validate HMAC signature
        var signature = req.Headers.GetValues("X-Webhook-Signature")?.FirstOrDefault();
        if (!ValidateSignature(bodyBytes, signature))
        {
            _logger.LogWarning("Invalid webhook signature from {Source}", source);
            return req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
        }

        // Map external ticket schema to Dataverse based on source
        var ticket = source.ToLowerInvariant() switch
        {
            "servicenow" => MapServiceNowTicket(bodyString),
            "jira" => MapJiraTicket(bodyString),
            _ => null
        };

        if (ticket is null)
        {
            var badRequest = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
            await badRequest.WriteStringAsync($"Unsupported webhook source: {source}");
            return badRequest;
        }

        var client = _dataverseService.GetClient();
        var ticketId = client.Create(ticket);

        _logger.LogInformation("Created ticket {TicketId} from {Source} webhook", ticketId, source);

        var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
        await response.WriteAsJsonAsync(new { ticketId, source });
        return response;
    }

    private bool ValidateSignature(byte[] body, string? signature)
    {
        if (string.IsNullOrEmpty(signature)) return false;

        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(_webhookSecret));
        var hash = hmac.ComputeHash(body);
        var expected = Convert.ToHexStringLower(hash);

        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(expected),
            Encoding.UTF8.GetBytes(signature));
    }

    private static Entity? MapServiceNowTicket(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (!root.TryGetProperty("number", out _)) return null;

        return new Entity("hd_ticket")
        {
            ["hd_title"] = root.GetProperty("short_description").GetString(),
            ["hd_description"] = root.GetProperty("description").GetString(),
            ["hd_source"] = new OptionSetValue(1), // Portal (external sync)
            ["hd_priority"] = new OptionSetValue(MapServiceNowPriority(
                root.GetProperty("priority").GetString())),
            ["hd_status"] = new OptionSetValue(1) // New
        };
    }

    private static Entity? MapJiraTicket(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (!root.TryGetProperty("issue", out var issue)) return null;
        var fields = issue.GetProperty("fields");

        return new Entity("hd_ticket")
        {
            ["hd_title"] = fields.GetProperty("summary").GetString(),
            ["hd_description"] = fields.GetProperty("description").GetString(),
            ["hd_source"] = new OptionSetValue(1),
            ["hd_priority"] = new OptionSetValue(MapJiraPriority(
                fields.GetProperty("priority").GetProperty("name").GetString())),
            ["hd_status"] = new OptionSetValue(1)
        };
    }

    private static int MapServiceNowPriority(string? priority) => priority switch
    {
        "1" => 1, // Critical
        "2" => 2, // High
        "3" => 3, // Medium
        _ => 4    // Low
    };

    private static int MapJiraPriority(string? priority) => priority switch
    {
        "Highest" or "Blocker" => 1,
        "High" => 2,
        "Medium" => 3,
        _ => 4
    };

    private static async Task<byte[]> ReadBodyAsync(Stream stream)
    {
        using var ms = new MemoryStream();
        await stream.CopyToAsync(ms);
        return ms.ToArray();
    }
}
