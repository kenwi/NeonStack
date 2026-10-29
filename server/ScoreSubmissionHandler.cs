using Microsoft.Extensions.Logging;
using Tetris.Highscores.Shared;

namespace Tetris.Highscores.Server;

public static class ScoreSubmissionHandler
{
    public static bool TryPrepare(
        ScoreSubmission submission,
        ILogger logger,
        out ScoreSubmission normalized,
        out string error)
    {
        logger.LogInformation(
            "Score submission received: ModeId={ModeId}, PlayerName={PlayerName}, FinalScore={FinalScore}, " +
            "LinesCleared={LinesCleared}, Level={Level}, ElapsedSeconds={ElapsedSeconds:F3}, Checksum={Checksum}",
            submission.ModeId,
            submission.PlayerName,
            submission.FinalScore,
            submission.LinesCleared,
            submission.Level,
            submission.ElapsedSeconds,
            submission.Checksum);

        normalized = ScoreSanitizer.NormalizeSubmission(submission);
        LogNormalizationChanges(logger, submission, normalized);

        if (!ScoreSanitizer.TryValidateSubmission(normalized, out error))
        {
            logger.LogWarning(
                "Score submission rejected (validation): ModeId={ModeId}, PlayerName={PlayerName}, Error={Error}",
                normalized.ModeId,
                normalized.PlayerName,
                error);
            return false;
        }

        if (!ScoreChecksum.Verify(normalized))
        {
            error = "Checksum verification failed.";
            var expected = ScoreChecksum.Compute(normalized);
            logger.LogWarning(
                "Suspected fake score submission (checksum mismatch): ModeId={ModeId}, PlayerName={PlayerName}, " +
                "FinalScore={FinalScore}, LinesCleared={LinesCleared}, Level={Level}, ElapsedSeconds={ElapsedSeconds:F3}, " +
                "ProvidedChecksum={ProvidedChecksum}, ExpectedChecksum={ExpectedChecksum}",
                normalized.ModeId,
                normalized.PlayerName,
                normalized.FinalScore,
                normalized.LinesCleared,
                normalized.Level,
                normalized.ElapsedSeconds,
                submission.Checksum,
                expected);
            return false;
        }

        var suspiciousReasons = ScorePlausibilityChecker.GetSuspiciousReasons(normalized);
        if (suspiciousReasons.Count > 0)
        {
            logger.LogWarning(
                "Suspicious but accepted score submission: ModeId={ModeId}, PlayerName={PlayerName}, " +
                "FinalScore={FinalScore}, LinesCleared={LinesCleared}, Level={Level}, " +
                "ElapsedSeconds={ElapsedSeconds:F3}, Reasons={Reasons}",
                normalized.ModeId,
                normalized.PlayerName,
                normalized.FinalScore,
                normalized.LinesCleared,
                normalized.Level,
                normalized.ElapsedSeconds,
                string.Join("; ", suspiciousReasons));
        }

        logger.LogInformation(
            "Score submission accepted for storage: ModeId={ModeId}, PlayerName={PlayerName}, " +
            "FinalScore={FinalScore}, LinesCleared={LinesCleared}, Level={Level}, ElapsedSeconds={ElapsedSeconds:F3}",
            normalized.ModeId,
            normalized.PlayerName,
            normalized.FinalScore,
            normalized.LinesCleared,
            normalized.Level,
            normalized.ElapsedSeconds);

        return true;
    }

    private static void LogNormalizationChanges(
        ILogger logger,
        ScoreSubmission raw,
        ScoreSubmission normalized)
    {
        if (raw.ModeId != normalized.ModeId)
        {
            logger.LogInformation(
                "Normalized ModeId: raw='{RawModeId}' -> '{NormalizedModeId}'",
                raw.ModeId,
                normalized.ModeId);
        }

        if (raw.PlayerName != normalized.PlayerName)
        {
            logger.LogInformation(
                "Normalized PlayerName: raw='{RawPlayerName}' -> '{NormalizedPlayerName}'",
                raw.PlayerName,
                normalized.PlayerName);
        }
    }
}
