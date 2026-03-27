using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FluentAssertions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.PowerPlatform.Dataverse.Client;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using Moq;
using HelpDesk.Functions.Functions;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Tests;

public class WebhookReceiverTests
{
    private const string TestWebhookSecret = "test-secret-key-for-hmac-validation";

    private readonly Mock<DataverseService> _mockDataverseService;
    private readonly Mock<ServiceClient> _mockServiceClient;
    private readonly Mock<ILogger<WebhookReceiver>> _mockLogger;
    private readonly WebhookReceiver _function;

    public WebhookReceiverTests()
    {
        _mockLogger = new Mock<ILogger<WebhookReceiver>>();
        _mockDataverseService = new Mock<DataverseService>();
        _mockServiceClient = new Mock<ServiceClient>();

        _mockDataverseService
            .Setup(s => s.GetClient())
            .Returns(_mockServiceClient.Object);

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["WebhookSecret"] = TestWebhookSecret
            })
            .Build();

        _function = new WebhookReceiver(_mockDataverseService.Object, config, _mockLogger.Object);
    }

    // ---------------------------------------------------------------
    // HMAC Signature Validation
    // ---------------------------------------------------------------

    [Fact]
    public async Task ValidHmacSignature_PassesValidation()
    {
        var payload = CreateServiceNowPayload();
        var json = JsonSerializer.Serialize(payload);
        var signature = ComputeHmacSignature(json, TestWebhookSecret);
        SetupDataverseForCreate();

        var request = CreateMockHttpRequest(json, signature);
        var response = await _function.Run(request, "servicenow");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task InvalidHmacSignature_Returns401()
    {
        var payload = CreateServiceNowPayload();
        var json = JsonSerializer.Serialize(payload);

        var request = CreateMockHttpRequest(json, "invalid-signature-value");
        var response = await _function.Run(request, "servicenow");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task MissingHmacSignature_Returns401()
    {
        var payload = CreateServiceNowPayload();
        var json = JsonSerializer.Serialize(payload);

        var request = CreateMockHttpRequest(json, signature: null);
        var response = await _function.Run(request, "servicenow");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    // ---------------------------------------------------------------
    // ServiceNow Payload Mapping
    // ---------------------------------------------------------------

    [Fact]
    public async Task ServiceNow_CreatesCorrectEntity()
    {
        var json = JsonSerializer.Serialize(new
        {
            number = "INC0012345",
            short_description = "Laptop not booting",
            description = "User reports laptop shows black screen on power-on",
            priority = "2",
            state = "1"
        });

        var signature = ComputeHmacSignature(json, TestWebhookSecret);
        SetupDataverseForCreate();

        var request = CreateMockHttpRequest(json, signature);
        var response = await _function.Run(request, "servicenow");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            (string)e["hd_title"] == "Laptop not booting" &&
            (string)e["hd_description"] == "User reports laptop shows black screen on power-on" &&
            ((OptionSetValue)e["hd_source"]).Value == 1 &&
            (string)e["hd_externalid"] == "INC0012345"
        )), Times.Once);
    }

    // ---------------------------------------------------------------
    // ServiceNow Priority Mapping
    // ---------------------------------------------------------------

    [Theory]
    [InlineData("1", 1)]  // Critical
    [InlineData("2", 2)]  // High
    [InlineData("3", 3)]  // Medium
    [InlineData("5", 4)]  // default -> Low
    [InlineData("99", 4)] // unknown -> Low
    public async Task ServiceNow_PriorityMapping(string snowPriority, int expectedPriority)
    {
        var json = JsonSerializer.Serialize(new
        {
            number = "INC0099999",
            short_description = "Test",
            description = "Test description",
            priority = snowPriority,
            state = "1"
        });

        var signature = ComputeHmacSignature(json, TestWebhookSecret);
        SetupDataverseForCreate();

        var request = CreateMockHttpRequest(json, signature);
        var response = await _function.Run(request, "servicenow");

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            ((OptionSetValue)e["hd_priority"]).Value == expectedPriority
        )), Times.Once);
    }

    // ---------------------------------------------------------------
    // Jira Payload Mapping
    // ---------------------------------------------------------------

    [Fact]
    public async Task Jira_CreatesCorrectEntity()
    {
        var json = JsonSerializer.Serialize(new
        {
            issue = new
            {
                key = "HELP-42",
                fields = new
                {
                    summary = "VPN connection drops",
                    description = "VPN disconnects every 15 minutes since Monday",
                    priority = new { name = "High" },
                    status = new { name = "Open" }
                }
            }
        });

        var signature = ComputeHmacSignature(json, TestWebhookSecret);
        SetupDataverseForCreate();

        var request = CreateMockHttpRequest(json, signature);
        var response = await _function.Run(request, "jira");

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            (string)e["hd_title"] == "VPN connection drops" &&
            (string)e["hd_description"] == "VPN disconnects every 15 minutes since Monday" &&
            ((OptionSetValue)e["hd_source"]).Value == 1 &&
            (string)e["hd_externalid"] == "HELP-42" &&
            ((OptionSetValue)e["hd_priority"]).Value == 2 // High
        )), Times.Once);
    }

    // ---------------------------------------------------------------
    // Jira Priority Mapping
    // ---------------------------------------------------------------

    [Theory]
    [InlineData("Highest", 1)]
    [InlineData("Blocker", 1)]
    [InlineData("High", 2)]
    [InlineData("Medium", 3)]
    [InlineData("Low", 4)]
    [InlineData("Trivial", 4)]
    public async Task Jira_PriorityMapping(string jiraPriority, int expectedPriority)
    {
        var json = JsonSerializer.Serialize(new
        {
            issue = new
            {
                key = "HELP-99",
                fields = new
                {
                    summary = "Test ticket",
                    description = "Test description",
                    priority = new { name = jiraPriority },
                    status = new { name = "Open" }
                }
            }
        });

        var signature = ComputeHmacSignature(json, TestWebhookSecret);
        SetupDataverseForCreate();

        var request = CreateMockHttpRequest(json, signature);
        var response = await _function.Run(request, "jira");

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            ((OptionSetValue)e["hd_priority"]).Value == expectedPriority
        )), Times.Once);
    }

    // ---------------------------------------------------------------
    // Unsupported source
    // ---------------------------------------------------------------

    [Fact]
    public async Task UnsupportedSource_Returns400()
    {
        var json = "{}";
        var signature = ComputeHmacSignature(json, TestWebhookSecret);

        var request = CreateMockHttpRequest(json, signature);
        var response = await _function.Run(request, "zendesk");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    // ---------------------------------------------------------------
    // Malformed JSON
    // ---------------------------------------------------------------

    [Fact]
    public async Task MalformedJson_ReturnsError()
    {
        var json = "{ this is not valid json }}}";
        var signature = ComputeHmacSignature(json, TestWebhookSecret);

        var request = CreateMockHttpRequest(json, signature);
        var response = await _function.Run(request, "servicenow");

        // Should return 500 (InternalServerError) since JSON parsing throws in MapServiceNowTicket
        response.StatusCode.Should().BeOneOf(
            HttpStatusCode.InternalServerError,
            HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task ServiceNow_MissingRequiredField_ReturnsError()
    {
        // Missing "number" field which is required
        var json = JsonSerializer.Serialize(new
        {
            short_description = "Test",
            description = "Test",
            priority = "3"
        });

        var signature = ComputeHmacSignature(json, TestWebhookSecret);
        SetupDataverseForCreate();

        var request = CreateMockHttpRequest(json, signature);
        var response = await _function.Run(request, "servicenow");

        // MapServiceNowTicket returns (null, null) when "number" is missing -> 400
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    private void SetupDataverseForCreate()
    {
        var ticketId = Guid.NewGuid();

        _mockServiceClient
            .Setup(c => c.Create(It.IsAny<Entity>()))
            .Returns(ticketId);

        // No existing ticket (no idempotency match)
        _mockServiceClient
            .Setup(c => c.RetrieveMultiple(It.IsAny<QueryExpression>()))
            .Returns(new EntityCollection(new List<Entity>()));
    }

    private static object CreateServiceNowPayload() => new
    {
        number = "INC0012345",
        short_description = "Test incident",
        description = "Test incident description",
        priority = "3",
        state = "1"
    };

    private static string ComputeHmacSignature(string body, string secret)
    {
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(body));
        return Convert.ToHexStringLower(hash);
    }

    private static HttpRequestData CreateMockHttpRequest(string body, string? signature)
    {
        var context = new Mock<FunctionContext>();
        var serviceProvider = new Mock<IServiceProvider>();
        context.Setup(c => c.InstanceServices).Returns(serviceProvider.Object);

        var request = new Mock<HttpRequestData>(context.Object);
        var stream = new MemoryStream(Encoding.UTF8.GetBytes(body));
        request.Setup(r => r.Body).Returns(stream);

        // Set up headers
        var headers = new HttpHeadersCollection();
        if (signature is not null)
        {
            headers.Add("X-Webhook-Signature", signature);
        }
        request.Setup(r => r.Headers).Returns(headers);

        // Response factory
        request.Setup(r => r.CreateResponse()).Returns(() => CreateMockResponse(context.Object));
        request.Setup(r => r.CreateResponse(It.IsAny<HttpStatusCode>()))
            .Returns((HttpStatusCode code) =>
            {
                var resp = CreateMockResponse(context.Object);
                resp.StatusCode = code;
                return resp;
            });

        return request.Object;
    }

    private static HttpResponseData CreateMockResponse(FunctionContext context)
    {
        var response = new Mock<HttpResponseData>(context);
        response.SetupProperty(r => r.StatusCode);
        response.SetupProperty(r => r.Headers, new HttpHeadersCollection());
        response.Setup(r => r.Body).Returns(new MemoryStream());
        return response.Object;
    }
}
