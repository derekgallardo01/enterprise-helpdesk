using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Functions;

/// <summary>
/// Receives webhooks from external ITSM tools (ServiceNow, Jira) for migration/hybrid scenarios.
/// Validates HMAC signature on incoming payloads to prevent unauthorized ticket creation.
/// Supports idempotent upsert via hd_externalid to prevent duplicate tickets.
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

        var client = _dataverseService.GetClient();

        // Map external ticket schema to Dataverse based on source
        Entity? ticket;
        string? externalId;
        try
        {
            (ticket, externalId) = source.ToLowerInvariant() switch
            {
                "servicenow" => MapServiceNowTicket(bodyString, client),
                "jira" => MapJiraTicket(bodyString, client),
                _ => (null, null)
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to map {Source} webhook payload", source);
            var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            await errorResponse.WriteStringAsync($"Failed to map {source} payload: {ex.Message}");
            return errorResponse;
        }

        if (ticket is null)
        {
            var badRequest = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
            await badRequest.WriteStringAsync($"Unsupported webhook source: {source}");
            return badRequest;
        }

        // Idempotency: check if ticket with this external ID already exists
        Guid ticketId;
        var existingTicketId = LookupTicketByExternalId(client, externalId);

        if (existingTicketId.HasValue)
        {
            // Update existing ticket
            ticket.Id = existingTicketId.Value;
            client.Update(ticket);
            ticketId = existingTicketId.Value;
            _logger.LogInformation("Updated existing ticket {TicketId} from {Source} webhook (ExternalId={ExternalId})",
                ticketId, source, externalId);
        }
        else
        {
            // Create new ticket
            ticketId = client.Create(ticket);
            _logger.LogInformation("Created ticket {TicketId} from {Source} webhook (ExternalId={ExternalId})",
                ticketId, source, externalId);
        }

        var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
        await response.WriteAsJsonAsync(new { ticketId, source, externalId });
        return response;
    }

    /// <summary>
    /// Queries hd_ticket by hd_externalid to support idempotent upsert.
    /// </summary>
    private static Guid? LookupTicketByExternalId(
        Microsoft.PowerPlatform.Dataverse.Client.ServiceClient client,
        string? externalId)
    {
        if (string.IsNullOrWhiteSpace(externalId)) return null;

        var query = new QueryExpression("hd_ticket")
        {
            ColumnSet = new ColumnSet("hd_ticketid"),
            Criteria = new FilterExpression()
        };
        query.Criteria.AddCondition("hd_externalid", ConditionOperator.Equal, externalId);
        query.TopCount = 1;

        var results = client.RetrieveMultiple(query);
        return results.Entities.FirstOrDefault()?.Id;
    }

    /// <summary>
    /// Looks up a systemuser by email address. Returns null if not found.
    /// </summary>
    private static Guid? LookupUserByEmail(
        Microsoft.PowerPlatform.Dataverse.Client.ServiceClient client,
        string? email)
    {
        if (string.IsNullOrWhiteSpace(email)) return null;

        var query = new QueryExpression("systemuser")
        {
            ColumnSet = new ColumnSet("systemuserid"),
            Criteria = new FilterExpression()
        };
        query.Criteria.AddCondition("internalemailaddress", ConditionOperator.Equal, email);
        query.TopCount = 1;

        var results = client.RetrieveMultiple(query);
        return results.Entities.FirstOrDefault()?.Id;
    }

    /// <summary>
    /// Looks up an hd_category by name. Returns null if not found.
    /// </summary>
    private static Guid? LookupCategoryByName(
        Microsoft.PowerPlatform.Dataverse.Client.ServiceClient client,
        string? categoryName)
    {
        if (string.IsNullOrWhiteSpace(categoryName)) return null;

        var query = new QueryExpression("hd_category")
        {
            ColumnSet = new ColumnSet("hd_categoryid"),
            Criteria = new FilterExpression()
        };
        query.Criteria.AddCondition("hd_name", ConditionOperator.Equal, categoryName);
        query.TopCount = 1;

        var results = client.RetrieveMultiple(query);
        return results.Entities.FirstOrDefault()?.Id;
    }

    /// <summary>
    /// Looks up an hd_subcategory by name. Returns null if not found.
    /// </summary>
    private static Guid? LookupSubcategoryByName(
        Microsoft.PowerPlatform.Dataverse.Client.ServiceClient client,
        string? subcategoryName)
    {
        if (string.IsNullOrWhiteSpace(subcategoryName)) return null;

        var query = new QueryExpression("hd_subcategory")
        {
            ColumnSet = new ColumnSet("hd_subcategoryid"),
            Criteria = new FilterExpression()
        };
        query.Criteria.AddCondition("hd_name", ConditionOperator.Equal, subcategoryName);
        query.TopCount = 1;

        var results = client.RetrieveMultiple(query);
        return results.Entities.FirstOrDefault()?.Id;
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

    private (Entity? Ticket, string? ExternalId) MapServiceNowTicket(
        string json,
        Microsoft.PowerPlatform.Dataverse.Client.ServiceClient client)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (!root.TryGetProperty("number", out var numberElement)) return (null, null);

        var externalId = numberElement.GetString();

        var ticket = new Entity("hd_ticket")
        {
            ["hd_title"] = root.GetProperty("short_description").GetString(),
            ["hd_description"] = root.GetProperty("description").GetString(),
            ["hd_source"] = new OptionSetValue(1), // Portal (external sync)
            ["hd_priority"] = new OptionSetValue(MapServiceNowPriority(
                root.GetProperty("priority").GetString())),
            ["hd_externalid"] = externalId
        };

        // Map ServiceNow state to Dataverse status: New=1, Active=3, Resolved=6, Closed=7
        if (root.TryGetProperty("state", out var stateElement))
        {
            var status = MapServiceNowState(stateElement.GetString());
            ticket["hd_status"] = new OptionSetValue(status);
        }
        else
        {
            ticket["hd_status"] = new OptionSetValue(1); // Default: New
        }

        // Assigned to: lookup by email with per-field error handling
        if (root.TryGetProperty("assigned_to", out var assignedToElement))
        {
            try
            {
                var assignedEmail = assignedToElement.GetString();
                var assignedId = LookupUserByEmail(client, assignedEmail);
                if (assignedId.HasValue)
                {
                    ticket["hd_assignedto"] = new EntityReference("systemuser", assignedId.Value);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to lookup assigned_to user from ServiceNow payload");
            }
        }

        // Category lookup with per-field error handling
        if (root.TryGetProperty("category", out var categoryElement))
        {
            try
            {
                var categoryName = categoryElement.GetString();
                var categoryId = LookupCategoryByName(client, categoryName);
                if (categoryId.HasValue)
                {
                    ticket["hd_category"] = new EntityReference("hd_category", categoryId.Value);
                }
                else
                {
                    _logger.LogWarning("ServiceNow category not found in Dataverse: {Category}", categoryName);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to lookup category from ServiceNow payload");
            }
        }

        // Subcategory lookup with per-field error handling
        if (root.TryGetProperty("subcategory", out var subcategoryElement))
        {
            try
            {
                var subcategoryName = subcategoryElement.GetString();
                var subcategoryId = LookupSubcategoryByName(client, subcategoryName);
                if (subcategoryId.HasValue)
                {
                    ticket["hd_subcategory"] = new EntityReference("hd_subcategory", subcategoryId.Value);
                }
                else
                {
                    _logger.LogWarning("ServiceNow subcategory not found in Dataverse: {Subcategory}", subcategoryName);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to lookup subcategory from ServiceNow payload");
            }
        }

        return (ticket, externalId);
    }

    private (Entity? Ticket, string? ExternalId) MapJiraTicket(
        string json,
        Microsoft.PowerPlatform.Dataverse.Client.ServiceClient client)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (!root.TryGetProperty("issue", out var issue)) return (null, null);

        var externalId = issue.GetProperty("key").GetString();
        var fields = issue.GetProperty("fields");

        var ticket = new Entity("hd_ticket")
        {
            ["hd_title"] = fields.GetProperty("summary").GetString(),
            ["hd_description"] = fields.GetProperty("description").GetString(),
            ["hd_source"] = new OptionSetValue(1),
            ["hd_priority"] = new OptionSetValue(MapJiraPriority(
                fields.GetProperty("priority").GetProperty("name").GetString())),
            ["hd_externalid"] = externalId
        };

        // Map Jira status name to Dataverse status
        if (fields.TryGetProperty("status", out var statusElement) &&
            statusElement.TryGetProperty("name", out var statusNameElement))
        {
            var status = MapJiraStatus(statusNameElement.GetString());
            ticket["hd_status"] = new OptionSetValue(status);
        }
        else
        {
            ticket["hd_status"] = new OptionSetValue(1); // Default: New
        }

        // Assignee lookup with per-field error handling
        if (fields.TryGetProperty("assignee", out var assigneeElement) &&
            assigneeElement.ValueKind != JsonValueKind.Null)
        {
            try
            {
                var assigneeEmail = assigneeElement.TryGetProperty("emailAddress", out var emailProp)
                    ? emailProp.GetString()
                    : null;
                var assigneeId = LookupUserByEmail(client, assigneeEmail);
                if (assigneeId.HasValue)
                {
                    ticket["hd_assignedto"] = new EntityReference("systemuser", assigneeId.Value);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to lookup assignee from Jira payload");
            }
        }

        // Labels -> category (use first label as category name) with per-field error handling
        if (fields.TryGetProperty("labels", out var labelsElement) &&
            labelsElement.GetArrayLength() > 0)
        {
            try
            {
                var categoryName = labelsElement[0].GetString();
                var categoryId = LookupCategoryByName(client, categoryName);
                if (categoryId.HasValue)
                {
                    ticket["hd_category"] = new EntityReference("hd_category", categoryId.Value);
                }
                else
                {
                    _logger.LogWarning("Jira label not found as category in Dataverse: {Category}", categoryName);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to lookup category from Jira labels");
            }
        }

        // Components -> subcategory (use first component name) with per-field error handling
        if (fields.TryGetProperty("components", out var componentsElement) &&
            componentsElement.GetArrayLength() > 0)
        {
            try
            {
                var componentName = componentsElement[0].TryGetProperty("name", out var nameProp)
                    ? nameProp.GetString()
                    : null;
                var subcategoryId = LookupSubcategoryByName(client, componentName);
                if (subcategoryId.HasValue)
                {
                    ticket["hd_subcategory"] = new EntityReference("hd_subcategory", subcategoryId.Value);
                }
                else
                {
                    _logger.LogWarning("Jira component not found as subcategory in Dataverse: {Subcategory}", componentName);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to lookup subcategory from Jira components");
            }
        }

        return (ticket, externalId);
    }

    private static int MapServiceNowPriority(string? priority) => priority switch
    {
        "1" => 1, // Critical
        "2" => 2, // High
        "3" => 3, // Medium
        _ => 4    // Low
    };

    private static int MapServiceNowState(string? state) => state switch
    {
        "1" => 1, // New
        "2" => 3, // Active (In Progress)
        "3" => 3, // Active (On Hold mapped to Active)
        "6" => 6, // Resolved
        "7" => 7, // Closed
        _ => 1    // Default: New
    };

    private static int MapJiraPriority(string? priority) => priority switch
    {
        "Highest" or "Blocker" => 1,
        "High" => 2,
        "Medium" => 3,
        _ => 4
    };

    private static int MapJiraStatus(string? status) => status switch
    {
        "To Do" or "Open" or "Backlog" => 1,           // New
        "In Progress" or "In Review" => 3,              // Active
        "Done" or "Resolved" => 6,                      // Resolved
        "Closed" => 7,                                  // Closed
        _ => 1                                          // Default: New
    };

    private static async Task<byte[]> ReadBodyAsync(Stream stream)
    {
        using var ms = new MemoryStream();
        await stream.CopyToAsync(ms);
        return ms.ToArray();
    }
}
