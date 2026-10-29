using System.Diagnostics;

namespace Tetris.Highscores.Server.Logging;

/// <summary>
/// Adds request-scoped logging context and logs every HTTP request with duration and status.
/// </summary>
public sealed class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public RequestLoggingMiddleware(RequestDelegate next, ILogger<RequestLoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var clientIp = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        var origin = context.Request.Headers.Origin.ToString();
        var userAgent = context.Request.Headers.UserAgent.ToString();

        using (_logger.BeginScope(new Dictionary<string, object?>
        {
            ["ClientIp"] = clientIp,
            ["Origin"] = string.IsNullOrEmpty(origin) ? "(none)" : origin,
            ["UserAgent"] = string.IsNullOrEmpty(userAgent) ? "(none)" : userAgent,
        }))
        {
            var sw = Stopwatch.StartNew();
            try
            {
                await _next(context);
            }
            finally
            {
                sw.Stop();
                var status = context.Response.StatusCode;
                var level = status >= 500 ? LogLevel.Error
                    : status >= 400 ? LogLevel.Warning
                    : LogLevel.Information;

                _logger.Log(
                    level,
                    "HTTP {Method} {Path} -> {StatusCode} ({ElapsedMs}ms)",
                    context.Request.Method,
                    context.Request.Path + context.Request.QueryString,
                    status,
                    sw.ElapsedMilliseconds);
            }
        }
    }
}
