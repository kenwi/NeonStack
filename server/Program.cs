using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Primitives;
using Tetris.Highscores.Server;
using Tetris.Highscores.Server.Logging;
using Tetris.Highscores.Shared;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.AddFileLogger(builder.Configuration);

const string dataConfigPath = "/data/appsettings.json";
if (File.Exists(dataConfigPath))
    builder.Configuration.AddJsonFile(dataConfigPath, optional: false, reloadOnChange: true);

builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownIPNetworks.Clear();
    options.KnownProxies.Clear();
});

builder.Services.AddSingleton<JsonFileScoreStore>();
builder.Services.AddSingleton<SubmissionRejectionTracker>();
builder.Services.AddHttpClient<DiscordScoreAnnouncer>();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ??
        [
            "http://localhost:8060",
            "http://127.0.0.1:8060",
            "http://localhost:8080",
            "http://127.0.0.1:8080"
        ];

        policy.WithOrigins(origins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

var app = builder.Build();

app.UseForwardedHeaders();
app.UseMiddleware<RequestLoggingMiddleware>();

var startupLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("Tetris.Highscores.Server");
var scoreFilePath = app.Configuration["Highscores:FilePath"] ?? "highscores.json";
var logFilePath = app.Configuration["Logging:File:Path"];
startupLogger.LogInformation(
    "Highscores server starting. ScoreFile={ScoreFile}, LogFile={LogFile}, CorsOrigins={CorsOrigins}",
    Path.GetFullPath(scoreFilePath),
    string.IsNullOrWhiteSpace(logFilePath) ? "(disabled)" : Path.GetFullPath(logFilePath),
    string.Join(", ", app.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? []));

if (File.Exists(dataConfigPath))
{
    ChangeToken.OnChange(
        () => app.Configuration.GetReloadToken(),
        () => startupLogger.LogInformation("Configuration reloaded from {ConfigPath}", dataConfigPath));
}

if (!app.Environment.IsDevelopment())
    app.UseHttpsRedirection();
app.UseCors();

app.MapPost("/api/scores", async (
    ScoreSubmission submission,
    JsonFileScoreStore store,
    DiscordScoreAnnouncer announcer,
    SubmissionRejectionTracker rejectionTracker,
    HttpContext httpContext,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
{
    var clientIp = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    var origin = httpContext.Request.Headers.Origin.ToString();
    var referer = httpContext.Request.Headers.Referer.ToString();
    var userAgent = httpContext.Request.Headers.UserAgent.ToString();

    logger.LogInformation(
        "POST /api/scores request: ClientIp={ClientIp}, Origin={Origin}, Referer={Referer}, UserAgent={UserAgent}",
        clientIp,
        string.IsNullOrEmpty(origin) ? "(none)" : origin,
        string.IsNullOrEmpty(referer) ? "(none)" : referer,
        string.IsNullOrEmpty(userAgent) ? "(none)" : userAgent);

    if (!ScoreSubmissionHandler.TryPrepare(submission, logger, out var normalized, out var error))
    {
        var isSuspectedFake = error.Contains("Checksum", StringComparison.OrdinalIgnoreCase);
        var rejectionCount = rejectionTracker.RecordRejection(clientIp);
        if (rejectionTracker.IsRepeatOffender(clientIp, rejectionCount))
        {
            logger.LogWarning(
                "Repeat score rejection offender: ClientIp={ClientIp}, RejectionCount={RejectionCount}, " +
                "WindowMinutes={WindowMinutes}, Threshold={Threshold}",
                clientIp,
                rejectionCount,
                rejectionTracker.Window.TotalMinutes,
                rejectionTracker.Threshold);
        }

        logger.LogWarning(
            "POST /api/scores rejected: ClientIp={ClientIp}, Origin={Origin}, UserAgent={UserAgent}, " +
            "ModeId={ModeId}, PlayerName={PlayerName}, FinalScore={FinalScore}, RejectionCount={RejectionCount}, " +
            "SuspectedFake={SuspectedFake}, Error={Error}",
            clientIp,
            string.IsNullOrEmpty(origin) ? "(none)" : origin,
            string.IsNullOrEmpty(userAgent) ? "(none)" : userAgent,
            submission.ModeId,
            submission.PlayerName,
            submission.FinalScore,
            rejectionCount,
            isSuspectedFake,
            error);
        return Results.BadRequest(new { error });
    }

    var addResult = await store.TryAddScoreAsync(normalized, cancellationToken);
    if (!addResult.Accepted)
    {
        logger.LogWarning(
            "POST /api/scores rejected (duplicate): ClientIp={ClientIp}, ModeId={ModeId}, PlayerName={PlayerName}, FinalScore={FinalScore}",
            clientIp,
            normalized.ModeId,
            normalized.PlayerName,
            normalized.FinalScore);
        return Results.Conflict(new { error = "This score has already been submitted." });
    }

    announcer.AnnounceInBackground(normalized, addResult);

    logger.LogInformation(
        "POST /api/scores succeeded: ClientIp={ClientIp}, ModeId={ModeId}, PlayerName={PlayerName}, FinalScore={FinalScore}, Rank={Rank}",
        clientIp,
        normalized.ModeId,
        normalized.PlayerName,
        normalized.FinalScore,
        addResult.Rank);
    return Results.Ok(new { message = "Score accepted.", rank = addResult.Rank });
});

app.MapGet("/api/scores/{modeId}", async (
    string modeId,
    int? top,
    JsonFileScoreStore store,
    HttpContext httpContext,
    ILogger<Program> logger,
    CancellationToken cancellationToken) =>
{
    var clientIp = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    var origin = httpContext.Request.Headers.Origin.ToString();
    var count = Math.Clamp(top ?? 10, 1, 100);

    logger.LogInformation(
        "GET /api/scores/{ModeId} request: ClientIp={ClientIp}, Origin={Origin}, RawModeId={RawModeId}, Top={Top}",
        modeId,
        clientIp,
        string.IsNullOrEmpty(origin) ? "(none)" : origin,
        modeId,
        count);

    var sanitizedModeId = ScoreSanitizer.SanitizeModeId(modeId);
    if (string.IsNullOrEmpty(sanitizedModeId))
    {
        logger.LogWarning(
            "GET /api/scores rejected: ClientIp={ClientIp}, RawModeId={RawModeId}, Error=ModeId is required",
            clientIp,
            modeId);
        return Results.BadRequest(new { error = "ModeId is required." });
    }

    if (sanitizedModeId != modeId)
    {
        logger.LogInformation(
            "GET /api/scores normalized ModeId: raw='{RawModeId}' -> '{SanitizedModeId}'",
            modeId,
            sanitizedModeId);
    }

    var entries = await store.GetTopAsync(sanitizedModeId, count, cancellationToken);
    logger.LogInformation(
        "GET /api/scores/{ModeId} succeeded: ClientIp={ClientIp}, ReturnedCount={ReturnedCount}",
        sanitizedModeId,
        clientIp,
        entries.Count);
    return Results.Ok(entries);
});

app.Run();
