using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Functions;

/// <summary>
/// HTTP POST endpoint that generates a suggested response for a ticket using Azure OpenAI.
/// Called by agents in the Power App to get AI-drafted replies and relevant KB articles.
/// </summary>
public class SuggestResponse
{
    private readonly ILogger<SuggestResponse> _logger;
    private readonly AIClassificationService _aiService;

    public SuggestResponse(AIClassificationService aiService, ILogger<SuggestResponse> logger)
    {
        _aiService = aiService;
        _logger = logger;
    }

    [Function("SuggestResponse")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        _logger.LogInformation("SuggestResponse request received");

        SuggestResponseRequest? payload;
        try
        {
            payload = await JsonSerializer.DeserializeAsync<SuggestResponseRequest>(
                req.Body,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Invalid JSON in SuggestResponse request");
            var badRequest = req.CreateResponse(HttpStatusCode.BadRequest);
            await badRequest.WriteAsJsonAsync(new { error = "Invalid JSON payload" });
            return badRequest;
        }

        if (payload is null || string.IsNullOrWhiteSpace(payload.TicketTitle))
        {
            var badRequest = req.CreateResponse(HttpStatusCode.BadRequest);
            await badRequest.WriteAsJsonAsync(new { error = "TicketTitle is required" });
            return badRequest;
        }

        try
        {
            var result = await _aiService.SuggestResponseAsync(
                payload.TicketTitle,
                payload.TicketDescription ?? "",
                payload.Category ?? "",
                payload.CommentHistory ?? []);

            _logger.LogInformation(
                "Response suggestion generated for ticket: {Title}, KB articles: {ArticleCount}",
                payload.TicketTitle, result.SuggestedKBArticles.Length);

            var response = req.CreateResponse(HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                suggestedResponse = result.SuggestedResponse,
                suggestedKBArticles = result.SuggestedKBArticles
            });
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Response suggestion failed for ticket: {Title}", payload.TicketTitle);
            var errorResponse = req.CreateResponse(HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new { error = "Suggestion service unavailable" });
            return errorResponse;
        }
    }
}

public record SuggestResponseRequest(
    string TicketTitle,
    string? TicketDescription,
    string? Category,
    string[]? CommentHistory);
