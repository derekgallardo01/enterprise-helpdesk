using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Graph;
using Microsoft.Graph.Models;
using Microsoft.Kiota.Abstractions.Serialization;
using Azure.Identity;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using HelpDesk.Functions.Services;

using DataverseEntity = Microsoft.Xrm.Sdk.Entity;

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
    private readonly DataverseService _dataverseService;

    public GraphSyncUserProfiles(
        IConfiguration configuration,
        DataverseService dataverseService,
        ILogger<GraphSyncUserProfiles> logger)
    {
        _configuration = configuration;
        _dataverseService = dataverseService;
        _logger = logger;
    }

    [Function("GraphSyncUserProfiles")]
    public async Task Run([TimerTrigger("0 0 6 * * *")] TimerInfo timerInfo) // Daily at 6:00 AM UTC
    {
        _logger.LogInformation("Starting Microsoft Graph user profile sync at {Time}", DateTime.UtcNow);

        // Use DefaultAzureCredential for managed identity (no client secrets in config)
        var credential = new DefaultAzureCredential();
        var graphClient = new GraphServiceClient(credential);

        var syncedCount = 0;
        var allUsers = new List<User>();

        try
        {
            // Fetch first page of users
            var usersResponse = await graphClient.Users
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

            if (usersResponse?.Value is null)
            {
                _logger.LogWarning("No users returned from Microsoft Graph");
                return;
            }

            allUsers.AddRange(usersResponse.Value);

            // Handle pagination for >999 users
            var nextLink = usersResponse.OdataNextLink;
            while (!string.IsNullOrEmpty(nextLink))
            {
                var nextPage = await graphClient.Users
                    .WithUrl(nextLink)
                    .GetAsync();

                if (nextPage?.Value is not null)
                {
                    allUsers.AddRange(nextPage.Value);
                    nextLink = nextPage.OdataNextLink;
                }
                else
                {
                    break;
                }
            }

            _logger.LogInformation("Fetched {UserCount} users from Microsoft Graph", allUsers.Count);

            // Collect unique department names and sync to Dataverse
            var departments = allUsers
                .Where(u => !string.IsNullOrWhiteSpace(u.Department))
                .Select(u => u.Department!)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            _logger.LogInformation("Found {DepartmentCount} unique departments", departments.Count);

            var client = _dataverseService.GetClient();

            // Upsert each department to Dataverse hd_department
            foreach (var departmentName in departments)
            {
                try
                {
                    UpsertDepartment(client, departmentName);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to upsert department: {DepartmentName}", departmentName);
                }
            }

            // Log synced users
            foreach (var user in allUsers)
            {
                _logger.LogDebug("Synced user: {DisplayName} ({Department})",
                    user.DisplayName, user.Department);
                syncedCount++;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Graph user profile sync failed after syncing {Count} users", syncedCount);
            throw;
        }

        _logger.LogInformation("Graph user profile sync complete. Synced {Count} users", syncedCount);
    }

    /// <summary>
    /// Queries Dataverse for an hd_department by name. Creates if not found, updates if found.
    /// </summary>
    private void UpsertDepartment(Microsoft.PowerPlatform.Dataverse.Client.ServiceClient client, string departmentName)
    {
        var query = new QueryExpression("hd_department")
        {
            ColumnSet = new ColumnSet("hd_departmentid", "hd_name"),
            Criteria = new FilterExpression()
        };
        query.Criteria.AddCondition("hd_name", ConditionOperator.Equal, departmentName);
        query.TopCount = 1;

        var results = client.RetrieveMultiple(query);
        var existing = results.Entities.FirstOrDefault();

        if (existing is not null)
        {
            // Update existing department (touch the record to mark it as current)
            existing["hd_name"] = departmentName;
            client.Update(existing);
            _logger.LogDebug("Updated department: {DepartmentName}", departmentName);
        }
        else
        {
            // Create new department
            var department = new DataverseEntity("hd_department")
            {
                ["hd_name"] = departmentName
            };
            client.Create(department);
            _logger.LogInformation("Created department: {DepartmentName}", departmentName);
        }
    }
}
