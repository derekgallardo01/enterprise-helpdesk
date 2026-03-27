using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Crm.Sdk.Messages;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Functions;

/// <summary>
/// HTTP health check endpoint for monitoring and load balancer probes.
/// Returns connectivity status for Dataverse and Azure SQL dependencies.
/// </summary>
public class HealthCheck
{
    private readonly ILogger<HealthCheck> _logger;
    private readonly DataverseService _dataverseService;
    private readonly string _sqlConnectionString;

    public HealthCheck(
        DataverseService dataverseService,
        IConfiguration configuration,
        ILogger<HealthCheck> logger)
    {
        _dataverseService = dataverseService;
        _logger = logger;
        _sqlConnectionString = configuration["SqlConnectionString"] ?? "";
    }

    [Function("HealthCheck")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get")] HttpRequestData req)
    {
        _logger.LogInformation("Health check requested at {Time}", DateTime.UtcNow);

        var dataverseHealthy = false;
        var sqlHealthy = false;

        // Check Dataverse connectivity
        try
        {
            var client = _dataverseService.GetClient();
            client.Execute(new WhoAmIRequest());
            dataverseHealthy = true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Dataverse health check failed");
        }

        // Check SQL connectivity
        try
        {
            await using var connection = new SqlConnection(_sqlConnectionString);
            await connection.OpenAsync();
            await using var command = new SqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync();
            sqlHealthy = true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SQL health check failed");
        }

        var overallStatus = dataverseHealthy && sqlHealthy ? "healthy" : "degraded";
        var statusCode = overallStatus == "healthy" ? HttpStatusCode.OK : HttpStatusCode.ServiceUnavailable;

        var result = new
        {
            status = overallStatus,
            dataverse = dataverseHealthy,
            sql = sqlHealthy,
            timestamp = DateTime.UtcNow
        };

        _logger.LogInformation("Health check result: {Status} (Dataverse={Dataverse}, SQL={SQL})",
            overallStatus, dataverseHealthy, sqlHealthy);

        var response = req.CreateResponse(statusCode);
        await response.WriteAsJsonAsync(result);
        return response;
    }
}
