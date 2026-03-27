using System.Net;
using System.Text;
using System.Text.Json;
using FluentAssertions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.PowerPlatform.Dataverse.Client;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using Moq;
using HelpDesk.Functions.Functions;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Tests;

public class EmailToTicketTests
{
    private readonly Mock<DataverseService> _mockDataverseService;
    private readonly Mock<ServiceClient> _mockServiceClient;
    private readonly Mock<ILogger<EmailToTicket>> _mockLogger;
    private readonly EmailToTicket _function;

    public EmailToTicketTests()
    {
        _mockLogger = new Mock<ILogger<EmailToTicket>>();
        _mockDataverseService = new Mock<DataverseService>();
        _mockServiceClient = new Mock<ServiceClient>();

        _mockDataverseService
            .Setup(s => s.GetClient())
            .Returns(_mockServiceClient.Object);

        _function = new EmailToTicket(_mockDataverseService.Object, _mockLogger.Object);
    }

    // ---------------------------------------------------------------
    // Priority keyword detection
    // ---------------------------------------------------------------

    [Theory]
    [InlineData("urgent", 2)]          // High
    [InlineData("URGENT request", 2)]  // Case-insensitive
    public async Task DetectPriority_Urgent_ReturnsHigh(string subject, int expectedPriority)
    {
        // Arrange
        var payload = new EmailPayload("user@contoso.com", subject, "Some body text");
        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);

        // Act
        var response = await _function.Run(request);

        // Assert
        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            ((OptionSetValue)e["hd_priority"]).Value == expectedPriority)), Times.Once);
    }

    [Theory]
    [InlineData("critical system failure")]
    [InlineData("CRITICAL: server down")]
    public async Task DetectPriority_Critical_ReturnsCritical(string subject)
    {
        var payload = new EmailPayload("user@contoso.com", subject, "Details here");
        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            ((OptionSetValue)e["hd_priority"]).Value == 1)), Times.Once);
    }

    [Fact]
    public async Task DetectPriority_Emergency_ReturnsCritical()
    {
        var payload = new EmailPayload("user@contoso.com", "Need help", "This is an emergency situation");
        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            ((OptionSetValue)e["hd_priority"]).Value == 1)), Times.Once);
    }

    [Fact]
    public async Task DetectPriority_ProductionDown_ReturnsCritical()
    {
        var payload = new EmailPayload("user@contoso.com", "production down in east region", "Please help immediately");
        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            ((OptionSetValue)e["hd_priority"]).Value == 1)), Times.Once);
    }

    [Fact]
    public async Task DetectPriority_NoKeywords_ReturnsMedium()
    {
        var payload = new EmailPayload("user@contoso.com", "Laptop screen flickering", "My laptop screen flickers intermittently");
        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            ((OptionSetValue)e["hd_priority"]).Value == 3)), Times.Once);
    }

    // ---------------------------------------------------------------
    // HTML sanitization
    // ---------------------------------------------------------------

    [Fact]
    public async Task SanitizeHtml_StripsHtmlTags()
    {
        var htmlBody = "<html><body><p>Hello <b>World</b></p><br/><div>Details here</div></body></html>";
        var payload = new EmailPayload("user@contoso.com", "Test ticket", htmlBody);
        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            !((string)e["hd_description"]).Contains("<") &&
            !((string)e["hd_description"]).Contains(">") &&
            ((string)e["hd_description"]).Contains("Hello") &&
            ((string)e["hd_description"]).Contains("World") &&
            ((string)e["hd_description"]).Contains("Details here")
        )), Times.Once);
    }

    [Fact]
    public async Task SanitizeHtml_CollapseWhitespace()
    {
        var htmlBody = "<p>Line one</p>   <p>Line two</p>";
        var payload = new EmailPayload("user@contoso.com", "Test ticket", htmlBody);
        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            !((string)e["hd_description"]).Contains("  ")
        )), Times.Once);
    }

    // ---------------------------------------------------------------
    // User lookup
    // ---------------------------------------------------------------

    [Fact]
    public async Task UserLookup_Found_SetsRequestedBy()
    {
        var userId = Guid.NewGuid();
        var payload = new EmailPayload("known.user@contoso.com", "Help needed", "Details");

        var userEntity = new Entity("systemuser", userId);
        var entityCollection = new EntityCollection(new List<Entity> { userEntity });

        _mockServiceClient
            .Setup(c => c.RetrieveMultiple(It.IsAny<QueryExpression>()))
            .Returns(entityCollection);

        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            e.Contains("hd_requestedby") &&
            ((EntityReference)e["hd_requestedby"]).Id == userId
        )), Times.Once);
    }

    [Fact]
    public async Task UserLookup_NotFound_DoesNotSetRequestedBy()
    {
        var payload = new EmailPayload("unknown@external.com", "Help needed", "Details");

        var emptyCollection = new EntityCollection(new List<Entity>());
        _mockServiceClient
            .Setup(c => c.RetrieveMultiple(It.IsAny<QueryExpression>()))
            .Returns(emptyCollection);

        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            !e.Contains("hd_requestedby")
        )), Times.Once);
    }

    // ---------------------------------------------------------------
    // Malformed payload
    // ---------------------------------------------------------------

    [Fact]
    public async Task MalformedPayload_Returns400()
    {
        var request = CreateMockHttpRequestFromString("this is not valid json");

        var response = await _function.Run(request);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task EmptyBody_Returns400()
    {
        var request = CreateMockHttpRequestFromString("");

        var response = await _function.Run(request);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    // ---------------------------------------------------------------
    // Subject sanitization
    // ---------------------------------------------------------------

    [Fact]
    public async Task SanitizeSubject_RemovesReFwPrefixes()
    {
        var payload = new EmailPayload("user@contoso.com", "RE: FW: Printer not working", "Details");
        SetupCreateAndRetrieve();

        var request = CreateMockHttpRequest(payload);
        var response = await _function.Run(request);

        _mockServiceClient.Verify(c => c.Create(It.Is<Entity>(e =>
            !((string)e["hd_title"]).StartsWith("RE:") &&
            !((string)e["hd_title"]).StartsWith("FW:")
        )), Times.Once);
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    private void SetupCreateAndRetrieve()
    {
        var ticketId = Guid.NewGuid();

        _mockServiceClient
            .Setup(c => c.Create(It.IsAny<Entity>()))
            .Returns(ticketId);

        var retrievedEntity = new Entity("hd_ticket", ticketId);
        retrievedEntity["hd_ticketnumber"] = "HD-00001";

        _mockServiceClient
            .Setup(c => c.Retrieve("hd_ticket", ticketId, It.IsAny<ColumnSet>()))
            .Returns(retrievedEntity);

        // Default: no user found
        _mockServiceClient
            .Setup(c => c.RetrieveMultiple(It.IsAny<QueryExpression>()))
            .Returns(new EntityCollection(new List<Entity>()));
    }

    private static HttpRequestData CreateMockHttpRequest(EmailPayload payload)
    {
        var json = JsonSerializer.Serialize(payload);
        return CreateMockHttpRequestFromString(json);
    }

    private static HttpRequestData CreateMockHttpRequestFromString(string body)
    {
        var context = new Mock<FunctionContext>();
        var serviceProvider = new Mock<IServiceProvider>();
        context.Setup(c => c.InstanceServices).Returns(serviceProvider.Object);

        var request = new Mock<HttpRequestData>(context.Object);
        var stream = new MemoryStream(Encoding.UTF8.GetBytes(body));
        request.Setup(r => r.Body).Returns(stream);

        var responseStream = new MemoryStream();
        var response = new Mock<HttpResponseData>(context.Object);
        response.SetupProperty(r => r.StatusCode);
        response.SetupProperty(r => r.Headers, new HttpHeadersCollection());
        response.Setup(r => r.Body).Returns(responseStream);

        request.Setup(r => r.CreateResponse()).Returns(response.Object);
        request.Setup(r => r.CreateResponse(It.IsAny<HttpStatusCode>()))
            .Returns((HttpStatusCode code) =>
            {
                var resp = new Mock<HttpResponseData>(context.Object);
                resp.SetupProperty(r => r.StatusCode, code);
                resp.SetupProperty(r => r.Headers, new HttpHeadersCollection());
                resp.Setup(r => r.Body).Returns(new MemoryStream());
                return resp.Object;
            });

        return request.Object;
    }
}
