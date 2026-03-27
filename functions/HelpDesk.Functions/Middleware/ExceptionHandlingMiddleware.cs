using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Middleware;
using Microsoft.Extensions.Logging;

namespace HelpDesk.Functions.Middleware;

/// <summary>
/// Global exception handling middleware for Azure Functions Isolated Worker.
/// Ensures all unhandled exceptions are logged with consistent structured properties
/// for Application Insights correlation and alerting.
/// </summary>
public class ExceptionHandlingMiddleware : IFunctionsWorkerMiddleware
{
    private readonly ILogger<ExceptionHandlingMiddleware> _logger;

    public ExceptionHandlingMiddleware(ILogger<ExceptionHandlingMiddleware> logger)
    {
        _logger = logger;
    }

    public async Task Invoke(FunctionContext context, FunctionExecutionDelegate next)
    {
        try
        {
            await next(context);
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Unhandled exception in function {FunctionName} (InvocationId={InvocationId}). " +
                "ExceptionType={ExceptionType}, Message={ExceptionMessage}",
                context.FunctionDefinition.Name,
                context.InvocationId,
                ex.GetType().Name,
                ex.Message);

            throw;
        }
    }
}
