using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using HelpDesk.Functions.Services;

var host = new HostBuilder()
    .ConfigureFunctionsWebApplication()
    .ConfigureServices(services =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();
        services.AddSingleton<DataverseService>();
        services.AddSingleton<DataverseSyncService>();
        services.AddSingleton<AIClassificationService>();
        services.AddHttpClient();
    })
    .Build();

host.Run();
