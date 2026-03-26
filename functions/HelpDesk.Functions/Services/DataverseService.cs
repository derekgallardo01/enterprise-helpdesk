using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.PowerPlatform.Dataverse.Client;

namespace HelpDesk.Functions.Services;

/// <summary>
/// Manages Dataverse connectivity using S2S (server-to-server) authentication.
/// S2S auth provides 40,000 requests per 5 minutes — separate from per-user quotas.
/// </summary>
public class DataverseService
{
    private readonly ILogger<DataverseService> _logger;
    private readonly string _connectionString;
    private ServiceClient? _client;

    public DataverseService(IConfiguration configuration, ILogger<DataverseService> logger)
    {
        _logger = logger;
        _connectionString = configuration["DataverseConnectionString"]
            ?? throw new InvalidOperationException("DataverseConnectionString not configured");
    }

    public ServiceClient GetClient()
    {
        if (_client is null || !_client.IsReady)
        {
            _logger.LogInformation("Initializing Dataverse ServiceClient (S2S authentication)");
            _client = new ServiceClient(_connectionString);

            if (!_client.IsReady)
            {
                throw new InvalidOperationException(
                    $"Failed to connect to Dataverse: {_client.LastError}");
            }
        }

        return _client;
    }
}
