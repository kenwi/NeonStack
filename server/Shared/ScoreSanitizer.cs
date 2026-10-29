using System.Text;
using System.Text.RegularExpressions;

namespace Tetris.Highscores.Shared;

/// <summary>Shared input normalization used by client and server before checksum and storage.</summary>
public static partial class ScoreSanitizer
{
    public const int MaxPlayerNameLength = 16;
    public const int MaxModeIdLength = 64;
    public const int MaxScore = 10_000_000;
    public const int MaxLines = 10_000;
    public const int MinLevel = 1;
    public const int MaxLevel = 15;
    public const float MaxElapsedSeconds = 86_400f;

    [GeneratedRegex(@"[^A-Za-z0-9 _-]")]
    private static partial Regex InvalidNameChars();

    [GeneratedRegex(@"[^A-Za-z0-9_-]")]
    private static partial Regex InvalidModeIdChars();

    public static string SanitizePlayerName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
            return "Anonymous";

        var trimmed = name.Trim();
        if (trimmed.Length > MaxPlayerNameLength)
            trimmed = trimmed[..MaxPlayerNameLength];

        var cleaned = InvalidNameChars().Replace(trimmed, string.Empty);
        return string.IsNullOrEmpty(cleaned) ? "Anonymous" : cleaned;
    }

    public static string SanitizeModeId(string? modeId)
    {
        if (string.IsNullOrWhiteSpace(modeId))
            return string.Empty;

        var trimmed = modeId.Trim();
        if (trimmed.Length > MaxModeIdLength)
            trimmed = trimmed[..MaxModeIdLength];

        return InvalidModeIdChars().Replace(trimmed, string.Empty);
    }

    public static bool TryValidateSubmission(ScoreSubmission submission, out string error)
    {
        var sb = new StringBuilder();

        if (string.IsNullOrEmpty(SanitizeModeId(submission.ModeId)))
            sb.AppendLine("ModeId is required.");

        if (submission.FinalScore < 0 || submission.FinalScore > MaxScore)
            sb.AppendLine("FinalScore is out of range.");

        if (submission.LinesCleared < 0 || submission.LinesCleared > MaxLines)
            sb.AppendLine("LinesCleared is out of range.");

        if (submission.Level < MinLevel || submission.Level > MaxLevel)
            sb.AppendLine("Level is out of range.");

        if (submission.ElapsedSeconds <= 0f || submission.ElapsedSeconds > MaxElapsedSeconds)
            sb.AppendLine("ElapsedSeconds is out of range.");

        error = sb.ToString().Trim();
        return error.Length == 0;
    }

    public static ScoreSubmission NormalizeSubmission(ScoreSubmission submission) => new()
    {
        ModeId = SanitizeModeId(submission.ModeId),
        PlayerName = SanitizePlayerName(submission.PlayerName),
        FinalScore = submission.FinalScore,
        LinesCleared = submission.LinesCleared,
        Level = submission.Level,
        ElapsedSeconds = submission.ElapsedSeconds,
        Checksum = submission.Checksum
    };
}
