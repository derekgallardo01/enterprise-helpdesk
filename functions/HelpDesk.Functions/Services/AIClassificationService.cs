using System.Text.Json;
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using OpenAI.Chat;

namespace HelpDesk.Functions.Services;

/// <summary>
/// Wraps Azure OpenAI calls for ticket classification and response suggestion.
/// Uses DefaultAzureCredential (managed identity) -- no API keys stored.
/// </summary>
public class AIClassificationService
{
    private readonly ILogger<AIClassificationService> _logger;
    private readonly ChatClient? _chatClient;

    // Category taxonomy used in the classification system prompt
    private const string CategoryTaxonomy = """
        Categories and subcategories:
        - Hardware: Laptop, Desktop, Monitor, Peripheral, Mobile Device
        - Software: Installation, Configuration, License, Bug, Update
        - Network: Connectivity, VPN, WiFi, Firewall, DNS
        - Email: Outlook, Calendar, Distribution List, Shared Mailbox
        - Access: Account Lockout, Password Reset, Permissions, New Account, MFA
        - Telephony: Desk Phone, Softphone, Conference Room, Voicemail
        - Printing: Printer Setup, Paper Jam, Toner, Network Printer, Print Queue
        - Security: Phishing, Malware, Data Loss, Compliance, Vulnerability
        - Cloud Services: SharePoint, Teams, OneDrive, Azure, Power Platform
        - Other: General Inquiry, Feedback, Training Request
        """;

    private static readonly string ClassificationSystemPrompt =
        "You are an IT help desk ticket classifier. Given a ticket title and description, " +
        "classify it into the appropriate category and subcategory from the taxonomy below. " +
        "Also assign a priority (1=Critical, 2=High, 3=Medium, 4=Low) and a confidence " +
        "score between 0.0 and 1.0.\n\n" +
        CategoryTaxonomy + "\n\n" +
        """Respond ONLY with valid JSON in this exact format: {"category": "string", "subcategory": "string", "priority": int, "confidence": float}""";

    private const string SuggestionSystemPrompt = """
        You are an expert IT help desk agent assistant. Given a ticket's title, description,
        category, and comment history, draft a professional, empathetic response for the agent
        to send to the end user. Also suggest up to 3 relevant knowledge base article titles
        that may help resolve the issue.

        Respond ONLY with valid JSON in this exact format:
        {"suggestedResponse": "string", "suggestedKBArticles": ["string", "string"]}
        """;

    public AIClassificationService(IConfiguration configuration, ILogger<AIClassificationService> logger)
    {
        _logger = logger;

        var endpoint = configuration["AzureOpenAI:Endpoint"];
        var deploymentName = configuration["AzureOpenAI:DeploymentName"];

        if (!string.IsNullOrEmpty(endpoint) && !string.IsNullOrEmpty(deploymentName))
        {
            var credential = new DefaultAzureCredential();
            var azureClient = new AzureOpenAIClient(new Uri(endpoint), credential);
            _chatClient = azureClient.GetChatClient(deploymentName);
        }
        else
        {
            _logger.LogWarning("AzureOpenAI not configured — AI classification will return defaults");
        }
    }

    /// <summary>
    /// Classifies a ticket into category, subcategory, priority, and confidence.
    /// </summary>
    public async Task<ClassificationResult> ClassifyTicketAsync(string title, string description)
    {
        if (_chatClient is null)
            return new ClassificationResult("Other", "General Inquiry", 3, 0.0);

        _logger.LogInformation("Classifying ticket: {Title}", title);

        var userMessage = $"Title: {title}\nDescription: {description}";

        var options = new ChatCompletionOptions
        {
            Temperature = 0.1f,
            MaxOutputTokenCount = 256,
            ResponseFormat = ChatResponseFormat.CreateJsonObjectFormat()
        };

        var completion = await _chatClient.CompleteChatAsync(
            [
                new SystemChatMessage(ClassificationSystemPrompt),
                new UserChatMessage(userMessage)
            ],
            options);

        var responseText = completion.Value.Content[0].Text;
        _logger.LogDebug("Classification raw response: {Response}", responseText);

        var result = JsonSerializer.Deserialize<ClassificationResult>(
            responseText,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        return result ?? new ClassificationResult("Other", "General Inquiry", 3, 0.0);
    }

    /// <summary>
    /// Generates a suggested agent response and relevant KB article titles.
    /// </summary>
    public async Task<SuggestionResult> SuggestResponseAsync(
        string title,
        string description,
        string category,
        string[] comments)
    {
        if (_chatClient is null)
            return new SuggestionResult("AI service not configured.", []);

        _logger.LogInformation("Generating response suggestion for ticket: {Title}", title);

        var commentHistory = comments.Length > 0
            ? "Comment history:\n" + string.Join("\n---\n", comments)
            : "No previous comments.";

        var userMessage = $"""
            Title: {title}
            Description: {description}
            Category: {category}

            {commentHistory}
            """;

        var options = new ChatCompletionOptions
        {
            Temperature = 0.7f,
            MaxOutputTokenCount = 1024,
            ResponseFormat = ChatResponseFormat.CreateJsonObjectFormat()
        };

        var completion = await _chatClient.CompleteChatAsync(
            [
                new SystemChatMessage(SuggestionSystemPrompt),
                new UserChatMessage(userMessage)
            ],
            options);

        var responseText = completion.Value.Content[0].Text;
        _logger.LogDebug("Suggestion raw response: {Response}", responseText);

        var result = JsonSerializer.Deserialize<SuggestionResult>(
            responseText,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        return result ?? new SuggestionResult(
            "Thank you for contacting IT support. We are looking into your request and will follow up shortly.",
            []);
    }
}

/// <summary>Classification result from Azure OpenAI.</summary>
public record ClassificationResult(
    string Category,
    string Subcategory,
    int Priority,
    double Confidence);

/// <summary>Response suggestion result from Azure OpenAI.</summary>
public record SuggestionResult(
    string SuggestedResponse,
    string[] SuggestedKBArticles);
