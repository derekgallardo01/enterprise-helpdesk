using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Functions;

/// <summary>
/// HTTP POST endpoint that classifies a ticket using Azure OpenAI.
/// Called by the Power Apps form or SPFx web part to auto-populate category fields.
/// </summary>
public class ClassifyTicket
{
    private readonly ILogger<ClassifyTicket> _logger;
    private readonly AIClassificationService _aiService;

    public ClassifyTicket(AIClassificationService aiService, ILogger<ClassifyTicket> logger)
    {
        _aiService = aiService;
        _logger = logger;
    }

    [Function("ClassifyTicket")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        _logger.LogInformation("ClassifyTicket request received");

        ClassifyTicketRequest? payload;
        try
        {
            payload = await JsonSerializer.DeserializeAsync<ClassifyTicketRequest>(
                req.Body,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Invalid JSON in ClassifyTicket request");
            var badRequest = req.CreateResponse(HttpStatusCode.BadRequest);
            await badRequest.WriteAsJsonAsync(new { error = "Invalid JSON payload" });
            return badRequest;
        }

        if (payload is null || string.IsNullOrWhiteSpace(payload.Title))
        {
            var badRequest = req.CreateResponse(HttpStatusCode.BadRequest);
            await badRequest.WriteAsJsonAsync(new { error = "Title is required" });
            return badRequest;
        }

        try
        {
            var result = await _aiService.ClassifyTicketAsync(payload.Title, payload.Description ?? "");

            _logger.LogInformation(
                "Ticket classified: Category={Category}, Subcategory={Subcategory}, Priority={Priority}, Confidence={Confidence}",
                result.Category, result.Subcategory, result.Priority, result.Confidence);

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                category = result.Category,
                subcategory = result.Subcategory,
                priority = result.Priority,
                confidence = result.Confidence
            });
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Ticket classification failed for title: {Title}", payload.Title);
            var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new { error = "Classification service unavailable" });
            return errorResponse;
        }
    }
}

public record ClassifyTicketRequest(string Title, string? Description);
