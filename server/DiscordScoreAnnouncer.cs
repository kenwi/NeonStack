using System.Globalization;
using System.Net.Http.Json;
using Tetris.Highscores.Shared;

namespace Tetris.Highscores.Server;

/// <summary>
/// Posts accepted score submissions to a Discord webhook.
/// Disabled when Discord:WebhookUrl is not configured. Announcements run in the
/// background and never affect the submission response.
/// </summary>
public sealed class DiscordScoreAnnouncer
{
    private const int GoldColor = 0xF1C40F;
    private const int SlateColor = 0x5865F2;

    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly ILogger<DiscordScoreAnnouncer> _logger;

    public DiscordScoreAnnouncer(
        HttpClient httpClient,
        IConfiguration configuration,
        ILogger<DiscordScoreAnnouncer> logger)
    {
        _httpClient = httpClient;
        _configuration = configuration;
        _logger = logger;
    }

    /// <summary>Fire-and-forget announcement; errors are logged, never thrown.</summary>
    public void AnnounceInBackground(ScoreSubmission submission, ScoreAddResult result)
    {
        _ = AnnounceAsync(submission, result);
    }

    private async Task AnnounceAsync(ScoreSubmission submission, ScoreAddResult result)
    {
        try
        {
            var webhookUrl = _configuration["Discord:WebhookUrl"];
            if (string.IsNullOrWhiteSpace(webhookUrl))
                return;

            var announceTopRanks = _configuration.GetValue("Discord:AnnounceTopRanks", 10);
            if (announceTopRanks > 0 && result.Rank > announceTopRanks)
            {
                _logger.LogInformation(
                    "Discord announcement skipped (rank {Rank} below top {AnnounceTopRanks}): ModeId={ModeId}, PlayerName={PlayerName}",
                    result.Rank,
                    announceTopRanks,
                    submission.ModeId,
                    submission.PlayerName);
                return;
            }

            var payload = BuildPayload(submission, result);
            using var response = await _httpClient.PostAsJsonAsync(webhookUrl, payload);
            if (!response.IsSuccessStatusCode)
            {
                var responseBody = await response.Content.ReadAsStringAsync();
                if (responseBody.Length > 200)
                    responseBody = responseBody[..200] + "...";

                _logger.LogWarning(
                    "Discord announcement failed: StatusCode={StatusCode}, ModeId={ModeId}, PlayerName={PlayerName}, " +
                    "Rank={Rank}, ResponseBody={ResponseBody}",
                    (int)response.StatusCode,
                    submission.ModeId,
                    submission.PlayerName,
                    result.Rank,
                    responseBody);
                return;
            }

            _logger.LogInformation(
                "Discord announcement sent: ModeId={ModeId}, PlayerName={PlayerName}, Rank={Rank}",
                submission.ModeId,
                submission.PlayerName,
                result.Rank);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(
                ex,
                "Discord announcement failed: ModeId={ModeId}, PlayerName={PlayerName}",
                submission.ModeId,
                submission.PlayerName);
        }
    }

    private object BuildPayload(ScoreSubmission submission, ScoreAddResult result)
    {
        var score = submission.FinalScore.ToString("N0", CultureInfo.InvariantCulture);
        var time = FormatTime(submission.ElapsedSeconds);
        bool isTopSpot = result.Rank == 1;

        var modeLabel = ModeLabel(submission.ModeId);
        var title = isTopSpot
            ? $"New #1 on {modeLabel}!"
            : $"New score on {modeLabel}";

        var description = isTopSpot
            ? $"**{submission.PlayerName}** took the top spot with **{score}** points in {time}."
            : $"**{submission.PlayerName}** scored **{score}** points in {time} " +
              $"(rank #{result.Rank} of {result.TotalEntriesForMode}).";

        var gameUrl = _configuration["Discord:GameUrl"];
        if (!string.IsNullOrWhiteSpace(gameUrl))
            description += $"\nThink you can beat it?\n[Play now]({gameUrl})";

        return new
        {
            embeds = new[]
            {
                new
                {
                    title,
                    description,
                    color = isTopSpot ? GoldColor : SlateColor,
                    fields = new[]
                    {
                        new
                        {
                            name = "Lines",
                            value = submission.LinesCleared.ToString(CultureInfo.InvariantCulture),
                            inline = true
                        },
                        new
                        {
                            name = "Level",
                            value = submission.Level.ToString(CultureInfo.InvariantCulture),
                            inline = true
                        },
                        new
                        {
                            name = "Time",
                            value = time,
                            inline = true
                        }
                    },
                    timestamp = DateTimeOffset.UtcNow.ToString("O")
                }
            }
        };
    }

    private static string ModeLabel(string modeId)
    {
        if (string.IsNullOrEmpty(modeId))
            return modeId;

        var mobile = modeId.EndsWith("-mobile", StringComparison.Ordinal);
        var core = mobile ? modeId[..^"-mobile".Length] : modeId;

        var label = core switch
        {
            "classic" => "Classic",
            _ when core.StartsWith("daily-", StringComparison.Ordinal) => $"Daily {core["daily-".Length..]}",
            _ when core.StartsWith("weekly-", StringComparison.Ordinal) => $"Weekly {core["weekly-".Length..]}",
            _ => core,
        };

        return mobile ? $"{label} (Mobile)" : label;
    }

    private static string FormatTime(float elapsedSeconds)
    {
        var timeSpan = TimeSpan.FromSeconds(elapsedSeconds);
        return timeSpan.TotalHours >= 1
            ? timeSpan.ToString(@"h\:mm\:ss", CultureInfo.InvariantCulture)
            : timeSpan.ToString(@"m\:ss", CultureInfo.InvariantCulture);
    }
}
