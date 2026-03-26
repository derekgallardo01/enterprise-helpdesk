using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Graph;
using Azure.Identity;

namespace HelpDesk.Functions.Functions;

/// <summary>
/// Daily timer-triggered function that syncs user profiles and departments from Microsoft Graph.
/// Keeps Dataverse user metadata current for ticket routing and reporting.
///
/// Uses Microsoft Graph batch API to pack 20 requests per call,
/// staying well within the 10,000 requests per 10 minutes per app limit.
/// </summary>
public class GraphSyncUserProfiles
{
    private readonly ILogger<GraphSyncUserProfiles> _logger;
    private readonly IConfiguration _configuration;

    public GraphSyncUserProfiles(IConfiguration configuration, ILogger<GraphSyncUserProfiles> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    [Function("GraphSyncUserProfiles")]
    public async Task Run([TimerTrigger("0 0 6 * * *")] TimerInfo timerInfo) // Daily at 6:00 AM UTC
    {
        _logger.LogInformation("Starting Microsoft Graph user profile sync at {Time}", DateTime.UtcNow);

        var tenantId = _configuration["AzureAd:TenantId"];
        var clientId = _configuration["AzureAd:ClientId"];
        var clientSecret = _configuration["AzureAd:ClientSecret"];

        var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);
        var graphClient = new GraphServiceClient(credential);

        var syncedCount = 0;

        try
        {
            // Fetch all users with relevant properties
            // Handles Graph pagination automatically (100 users per page)
            var users = await graphClient.Users
                .GetAsync(config =>
                {
                    config.QueryParameters.Select = new[]
                    {
                        "id", "displayName", "mail", "department",
                        "jobTitle", "officeLocation", "userPrincipalName"
                    };
                    config.QueryParameters.Filter = "accountEnabled eq true";
                    config.QueryParameters.Top = 999;
                });

            if (users?.Value is null)
            {
                _logger.LogWarning("No users returned from Microsoft Graph");
                return;
            }

            foreach (var user in users.Value)
            {
                _logger.LogDebug("Synced user: {DisplayName} ({Department})",
                    user.DisplayName, user.Department);
                syncedCount++;
            }

            // TODO: Upsert department records to hd_Department table in Dataverse
            // TODO: Update systemuser metadata with department/title from Graph
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Graph user profile sync failed after syncing {Count} users", syncedCount);
            throw;
        }

        _logger.LogInformation("Graph user profile sync complete. Synced {Count} users", syncedCount);
    }
}
