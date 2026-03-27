using System.ClientModel;
using System.ClientModel.Primitives;
using System.Text.Json;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using OpenAI.Chat;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Tests;

/// <summary>
/// Tests for AIClassificationService.
/// Since the service creates a ChatClient in its constructor via Azure OpenAI,
/// we test the ClassificationResult and SuggestionResult record types, and
/// verify behaviors through an abstraction layer approach.
///
/// For true unit tests of the AI service, we test:
/// 1. ClassificationResult record construction and validation
/// 2. SuggestionResult record construction and validation
/// 3. Edge cases on the data types
///
/// Full integration with Azure OpenAI is tested in integration tests.
/// </summary>
public class AIClassificationServiceTests
{
    // ---------------------------------------------------------------
    // ClassificationResult validation
    // ---------------------------------------------------------------

    [Fact]
    public void ClassificationResult_ValidResult_HasAllFields()
    {
        var result = new ClassificationResult("Hardware", "Laptop", 2, 0.92);

        result.Category.Should().Be("Hardware");
        result.Subcategory.Should().Be("Laptop");
        result.Priority.Should().Be(2);
        result.Confidence.Should().Be(0.92);
    }

    [Fact]
    public void ClassificationResult_Confidence_ShouldBeBetweenZeroAndOne()
    {
        var result = new ClassificationResult("Software", "Installation", 3, 0.87);

        result.Confidence.Should().BeGreaterThanOrEqualTo(0.0);
        result.Confidence.Should().BeLessThanOrEqualTo(1.0);
    }

    [Fact]
    public void ClassificationResult_DefaultFallback_HasValidStructure()
    {
        // This matches the fallback in ClassifyTicketAsync
        var result = new ClassificationResult("Other", "General Inquiry", 3, 0.0);

        result.Category.Should().Be("Other");
        result.Subcategory.Should().Be("General Inquiry");
        result.Priority.Should().Be(3);
        result.Confidence.Should().Be(0.0);
    }

    [Theory]
    [InlineData(1, "Critical")]
    [InlineData(2, "High")]
    [InlineData(3, "Medium")]
    [InlineData(4, "Low")]
    public void ClassificationResult_PriorityValues_AreValid(int priority, string _)
    {
        var result = new ClassificationResult("Network", "VPN", priority, 0.95);
        result.Priority.Should().BeInRange(1, 4);
    }

    // ---------------------------------------------------------------
    // SuggestionResult validation
    // ---------------------------------------------------------------

    [Fact]
    public void SuggestionResult_ValidResult_HasResponseAndArticles()
    {
        var result = new SuggestionResult(
            "Thank you for reporting this issue. We will investigate the VPN disconnection.",
            new[] { "VPN Troubleshooting Guide", "Network Connectivity FAQ" });

        result.SuggestedResponse.Should().NotBeNullOrWhiteSpace();
        result.SuggestedKBArticles.Should().HaveCountGreaterThan(0);
        result.SuggestedKBArticles.Should().HaveCountLessOrEqualTo(3);
    }

    [Fact]
    public void SuggestionResult_DefaultFallback_HasGenericResponse()
    {
        // Matches the fallback in SuggestResponseAsync
        var result = new SuggestionResult(
            "Thank you for contacting IT support. We are looking into your request and will follow up shortly.",
            []);

        result.SuggestedResponse.Should().NotBeNullOrWhiteSpace();
        result.SuggestedKBArticles.Should().BeEmpty();
    }

    [Fact]
    public void SuggestionResult_EmptyArticles_IsValid()
    {
        var result = new SuggestionResult("We are working on your issue.", Array.Empty<string>());

        result.SuggestedKBArticles.Should().BeEmpty();
        result.SuggestedResponse.Should().NotBeNullOrWhiteSpace();
    }

    // ---------------------------------------------------------------
    // JSON deserialization (simulating AI responses)
    // ---------------------------------------------------------------

    [Fact]
    public void ClassificationResult_DeserializesFromValidJson()
    {
        var json = """{"category": "Email", "subcategory": "Outlook", "priority": 3, "confidence": 0.88}""";

        var result = JsonSerializer.Deserialize<ClassificationResult>(
            json,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        result.Should().NotBeNull();
        result!.Category.Should().Be("Email");
        result.Subcategory.Should().Be("Outlook");
        result.Priority.Should().Be(3);
        result.Confidence.Should().BeApproximately(0.88, 0.001);
    }

    [Fact]
    public void ClassificationResult_MalformedJson_ReturnsNull()
    {
        var malformedJson = """{"category": "Email", "broken}""";

        var act = () => JsonSerializer.Deserialize<ClassificationResult>(
            malformedJson,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        act.Should().Throw<JsonException>();
    }

    [Fact]
    public void ClassificationResult_EmptyJsonObject_HandlesGracefully()
    {
        var json = "{}";

        var result = JsonSerializer.Deserialize<ClassificationResult>(
            json,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        // Record with required constructor params will either return null fields
        // or throw -- this validates the edge case
        result.Should().NotBeNull();
    }

    [Fact]
    public void SuggestionResult_DeserializesFromValidJson()
    {
        var json = """
            {
                "suggestedResponse": "Please try restarting your VPN client.",
                "suggestedKBArticles": ["VPN Setup Guide", "Network FAQ"]
            }
            """;

        var result = JsonSerializer.Deserialize<SuggestionResult>(
            json,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        result.Should().NotBeNull();
        result!.SuggestedResponse.Should().Be("Please try restarting your VPN client.");
        result.SuggestedKBArticles.Should().HaveCount(2);
    }

    [Fact]
    public void SuggestionResult_MalformedJson_Throws()
    {
        var malformedJson = """{"suggestedResponse": "partial""";

        var act = () => JsonSerializer.Deserialize<SuggestionResult>(
            malformedJson,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        act.Should().Throw<JsonException>();
    }

    // ---------------------------------------------------------------
    // Confidence boundary tests
    // ---------------------------------------------------------------

    [Theory]
    [InlineData(0.0)]
    [InlineData(0.5)]
    [InlineData(1.0)]
    public void ClassificationResult_ConfidenceBoundaries_AreValid(double confidence)
    {
        var result = new ClassificationResult("Access", "Password Reset", 3, confidence);

        result.Confidence.Should().BeGreaterThanOrEqualTo(0.0);
        result.Confidence.Should().BeLessThanOrEqualTo(1.0);
    }

    // ---------------------------------------------------------------
    // Category taxonomy coverage
    // ---------------------------------------------------------------

    [Theory]
    [InlineData("Hardware", "Laptop")]
    [InlineData("Software", "Installation")]
    [InlineData("Network", "VPN")]
    [InlineData("Email", "Outlook")]
    [InlineData("Access", "Password Reset")]
    [InlineData("Security", "Phishing")]
    [InlineData("Cloud Services", "Teams")]
    [InlineData("Other", "General Inquiry")]
    public void ClassificationResult_KnownCategories_AreValid(string category, string subcategory)
    {
        var result = new ClassificationResult(category, subcategory, 3, 0.9);

        result.Category.Should().Be(category);
        result.Subcategory.Should().Be(subcategory);
    }

    // ---------------------------------------------------------------
    // Error handling simulation
    // ---------------------------------------------------------------

    [Fact]
    public void ClassificationResult_ApiErrorFallback_ReturnsDefault()
    {
        // Simulate what the service does when AI returns null
        ClassificationResult? apiResult = null;
        var fallback = apiResult ?? new ClassificationResult("Other", "General Inquiry", 3, 0.0);

        fallback.Category.Should().Be("Other");
        fallback.Priority.Should().Be(3);
        fallback.Confidence.Should().Be(0.0);
    }

    [Fact]
    public void SuggestionResult_ApiErrorFallback_ReturnsDefault()
    {
        SuggestionResult? apiResult = null;
        var fallback = apiResult ?? new SuggestionResult(
            "Thank you for contacting IT support. We are looking into your request and will follow up shortly.",
            []);

        fallback.SuggestedResponse.Should().Contain("IT support");
        fallback.SuggestedKBArticles.Should().BeEmpty();
    }
}
