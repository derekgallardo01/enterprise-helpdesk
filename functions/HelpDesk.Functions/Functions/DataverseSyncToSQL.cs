using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using HelpDesk.Functions.Services;

namespace HelpDesk.Functions.Functions;

/// <summary>
/// Timer-triggered function that syncs Dataverse ticket data to Azure SQL every 15 minutes.
///
/// Architecture decision (ADR-002): Power BI queries Azure SQL instead of Dataverse directly,
/// protecting the Dataverse API quota (6,000 req/5 min/user) for transactional apps.
///
/// Uses Dataverse change tracking (delta token) — only syncs rows modified since last run.
/// Not a full table scan.
/// </summary>
public class DataverseSyncToSQL
{
    private readonly ILogger<DataverseSyncToSQL> _logger;
    private readonly DataverseSyncService _syncService;

    public DataverseSyncToSQL(DataverseSyncService syncService, ILogger<DataverseSyncToSQL> logger)
    {
        _syncService = syncService;
        _logger = logger;
    }

    [Function("DataverseSyncToSQL")]
    public async Task Run([TimerTrigger("0 */15 * * * *")] TimerInfo timerInfo)
    {
        _logger.LogInformation("Dataverse → SQL sync triggered at {Time}", DateTime.UtcNow);

        try
        {
            await _syncService.SyncAllAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Dataverse → SQL sync failed");
            throw; // Let Azure Functions retry infrastructure handle it
        }

        if (timerInfo.ScheduleStatus?.Next is not null)
        {
            _logger.LogInformation("Next sync scheduled at {NextRun}", timerInfo.ScheduleStatus.Next);
        }
    }
}
