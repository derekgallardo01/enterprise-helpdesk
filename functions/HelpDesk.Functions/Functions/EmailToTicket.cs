using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Xrm.Sdk;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Functions;

/// <summary>
/// Parses inbound emails from the shared helpdesk mailbox into Dataverse tickets.
///
/// Called by Power Automate via HTTP POST when a new email arrives at helpdesk@contoso.com.
/// Power Automate handles the email trigger and sends the parsed payload here.
/// This function handles the complex parsing that Power Automate cannot do well:
/// - Priority keyword detection via regex
/// - HTML sanitization
/// - User lookup in Dataverse
/// - Attachment handling
/// </summary>
public class EmailToTicket
{
    private readonly ILogger<EmailToTicket> _logger;
    private readonly DataverseService _dataverseService;

    // Priority keywords detected in email subject/body
    private static readonly Dictionary<string, int> PriorityKeywords = new(StringComparer.OrdinalIgnoreCase)
    {
        ["urgent"] = 2,         // High
        ["critical"] = 1,       // Critical
        ["asap"] = 2,           // High
        ["emergency"] = 1,      // Critical
        ["production down"] = 1, // Critical
        ["outage"] = 1          // Critical
    };

    public EmailToTicket(DataverseService dataverseService, ILogger<EmailToTicket> logger)
    {
        _dataverseService = dataverseService;
        _logger = logger;
    }

    [Function("EmailToTicket")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        _logger.LogInformation("Processing inbound email to ticket conversion");

        var body = await JsonSerializer.DeserializeAsync<EmailPayload>(req.Body);
        if (body is null)
        {
            var badRequest = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
            await badRequest.WriteStringAsync("Invalid email payload");
            return badRequest;
        }

        var client = _dataverseService.GetClient();

        // Look up the sender as a Dataverse system user
        var senderId = LookupUserByEmail(client, body.SenderEmail);

        // Detect priority from keywords in subject and body
        var detectedPriority = DetectPriority(body.Subject, body.Body);

        // Create the ticket in Dataverse
        var ticket = new Entity("hd_ticket")
        {
            ["hd_title"] = SanitizeSubject(body.Subject),
            ["hd_description"] = SanitizeHtml(body.Body),
            ["hd_source"] = new OptionSetValue(2), // 2 = Email
            ["hd_priority"] = new OptionSetValue(detectedPriority),
            ["hd_status"] = new OptionSetValue(1), // 1 = New
        };

        if (senderId.HasValue)
        {
            ticket["hd_requestedby"] = new EntityReference("systemuser", senderId.Value);
        }

        var ticketId = client.Create(ticket);

        // Retrieve the auto-generated ticket number
        var created = client.Retrieve("hd_ticket", ticketId, new Microsoft.Xrm.Sdk.Query.ColumnSet("hd_ticketnumber"));
        var ticketNumber = created.GetAttributeValue<string>("hd_ticketnumber") ?? ticketId.ToString();

        _logger.LogInformation("Created ticket {TicketNumber} from email by {Sender}",
            ticketNumber, body.SenderEmail);

        var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
        await response.WriteAsJsonAsync(new { ticketId, ticketNumber });
        return response;
    }

    private static Guid? LookupUserByEmail(Microsoft.PowerPlatform.Dataverse.Client.ServiceClient client, string email)
    {
        var query = new Microsoft.Xrm.Sdk.Query.QueryExpression("systemuser")
        {
            ColumnSet = new Microsoft.Xrm.Sdk.Query.ColumnSet("systemuserid"),
            Criteria = new Microsoft.Xrm.Sdk.Query.FilterExpression()
        };
        query.Criteria.AddCondition("internalemailaddress", Microsoft.Xrm.Sdk.Query.ConditionOperator.Equal, email);
        query.TopCount = 1;

        var results = client.RetrieveMultiple(query);
        return results.Entities.FirstOrDefault()?.Id;
    }

    private static int DetectPriority(string subject, string body)
    {
        var combined = $"{subject} {body}";
        var highestPriority = 3; // Default: Medium

        foreach (var (keyword, priority) in PriorityKeywords)
        {
            if (Regex.IsMatch(combined, $@"\b{Regex.Escape(keyword)}\b", RegexOptions.IgnoreCase))
            {
                highestPriority = Math.Min(highestPriority, priority);
            }
        }

        return highestPriority;
    }

    private static string SanitizeSubject(string subject)
    {
        // Remove RE:/FW: prefixes and trim
        return Regex.Replace(subject, @"^(RE|FW|FWD)\s*:\s*", "", RegexOptions.IgnoreCase).Trim();
    }

    private static string SanitizeHtml(string html)
    {
        // Basic HTML tag removal for plain text storage
        // In production, use a proper HTML sanitizer library (HtmlSanitizer NuGet)
        var text = Regex.Replace(html, @"<[^>]+>", " ");
        text = Regex.Replace(text, @"\s+", " ");
        return text.Trim();
    }
}

public record EmailPayload(
    string SenderEmail,
    string Subject,
    string Body,
    string[]? AttachmentUrls = null);
