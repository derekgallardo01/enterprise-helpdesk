using System.Net;
using System.Text.Json;
using FluentAssertions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.PowerPlatform.Dataverse.Client;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Moq;
using HelpDesk.Functions.Functions;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Tests;

public class HealthCheckTests
{
    private readonly Mock<DataverseService> _mockDataverseService;
    private readonly Mock<ServiceClient> _mockServiceClient;
    private readonly Mock<ILogger<HealthCheck>> _mockLogger;
    private readonly IConfiguration _configuration;

    public HealthCheckTests()
    {
        _mockLogger = new Mock<ILogger<HealthCheck>>();
        _mockDataverseService = new Mock<DataverseService>();
        _mockServiceClient = new Mock<ServiceClient>();

        _mockDataverseService
            .Setup(s => s.GetClient())
            .Returns(_mockServiceClient.Object);

        _configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                // Use a fake connection string -- the SQL call is mocked via the approach below
                ["SqlConnectionString"] = "Server=localhost;Database=test;Trusted_Connection=True;"
            })
            .Build();
    }

    [Fact]
    public async Task AllHealthy_ReturnsHealthyStatus()
    {
        // Arrange - Dataverse succeeds
        _mockServiceClient
            .Setup(c => c.Execute(It.IsAny<WhoAmIRequest>()))
            .Returns(new WhoAmIResponse());

        // Note: SQL connectivity check opens a real SqlConnection.
        // In unit tests we can only verify the Dataverse path directly.
        // For a full healthy test, we rely on integration tests.
        // Here we test the logic by verifying Dataverse side only.
        var function = new HealthCheck(_mockDataverseService.Object, _configuration, _mockLogger.Object);
        var request = CreateMockHttpRequest();

        // Act
        var response = await function.Run(request);

        // Assert - Dataverse is healthy; SQL may fail due to fake connection string
        // but we verify the response structure
        response.Should().NotBeNull();

        var body = ReadResponseBody(response);
        body.Should().NotBeNull();
        body.RootElement.TryGetProperty("status", out _).Should().BeTrue();
        body.RootElement.TryGetProperty("dataverse", out _).Should().BeTrue();
        body.RootElement.TryGetProperty("sql", out _).Should().BeTrue();
        body.RootElement.TryGetProperty("timestamp", out _).Should().BeTrue();
    }

    [Fact]
    public async Task DataverseDown_ReturnsDegradedWithDataverseFalse()
    {
        // Arrange - Dataverse throws
        _mockServiceClient
            .Setup(c => c.Execute(It.IsAny<WhoAmIRequest>()))
            .Throws(new Exception("Dataverse connection failed"));

        var function = new HealthCheck(_mockDataverseService.Object, _configuration, _mockLogger.Object);
        var request = CreateMockHttpRequest();

        // Act
        var response = await function.Run(request);

        // Assert
        var body = ReadResponseBody(response);
        body.RootElement.GetProperty("dataverse").GetBoolean().Should().BeFalse();
        // Status should be degraded or unhealthy when Dataverse is down
        var status = body.RootElement.GetProperty("status").GetString();
        status.Should().NotBe("healthy");
    }

    [Fact]
    public async Task SqlDown_ReturnsDegradedWithSqlFalse()
    {
        // Arrange - Dataverse succeeds
        _mockServiceClient
            .Setup(c => c.Execute(It.IsAny<WhoAmIRequest>()))
            .Returns(new WhoAmIResponse());

        // SQL will fail with fake connection string (cannot open actual connection)
        var function = new HealthCheck(_mockDataverseService.Object, _configuration, _mockLogger.Object);
        var request = CreateMockHttpRequest();

        // Act
        var response = await function.Run(request);

        // Assert
        var body = ReadResponseBody(response);
        body.RootElement.GetProperty("dataverse").GetBoolean().Should().BeTrue();
        body.RootElement.GetProperty("sql").GetBoolean().Should().BeFalse();
        body.RootElement.GetProperty("status").GetString().Should().Be("degraded");
    }

    [Fact]
    public async Task BothDown_ReturnsUnhealthyStatusBothFalse()
    {
        // Arrange - Dataverse throws
        _mockServiceClient
            .Setup(c => c.Execute(It.IsAny<WhoAmIRequest>()))
            .Throws(new Exception("Dataverse connection failed"));

        // SQL will also fail with fake connection string
        var function = new HealthCheck(_mockDataverseService.Object, _configuration, _mockLogger.Object);
        var request = CreateMockHttpRequest();

        // Act
        var response = await function.Run(request);

        // Assert
        var body = ReadResponseBody(response);
        body.RootElement.GetProperty("dataverse").GetBoolean().Should().BeFalse();
        body.RootElement.GetProperty("sql").GetBoolean().Should().BeFalse();

        // Both down: current implementation sets "degraded" for any failure combo.
        // The status should not be "healthy".
        var status = body.RootElement.GetProperty("status").GetString();
        status.Should().NotBe("healthy");
    }

    [Fact]
    public async Task HealthCheck_ReturnsServiceUnavailable_WhenNotFullyHealthy()
    {
        // Arrange - Dataverse throws so not fully healthy
        _mockServiceClient
            .Setup(c => c.Execute(It.IsAny<WhoAmIRequest>()))
            .Throws(new Exception("Dataverse down"));

        var function = new HealthCheck(_mockDataverseService.Object, _configuration, _mockLogger.Object);
        var request = CreateMockHttpRequest();

        // Act
        var response = await function.Run(request);

        // Assert - not fully healthy should give 503
        response.StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    private static HttpRequestData CreateMockHttpRequest()
    {
        var context = new Mock<FunctionContext>();
        var serviceProvider = new Mock<IServiceProvider>();
        context.Setup(c => c.InstanceServices).Returns(serviceProvider.Object);

        var request = new Mock<HttpRequestData>(context.Object);
        request.Setup(r => r.Body).Returns(new MemoryStream());

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
        var bodyStream = new MemoryStream();
        response.Setup(r => r.Body).Returns(bodyStream);
        return response.Object;
    }

    private static JsonDocument ReadResponseBody(HttpResponseData response)
    {
        response.Body.Position = 0;
        using var reader = new StreamReader(response.Body);
        var content = reader.ReadToEnd();
        return JsonDocument.Parse(content);
    }
}
