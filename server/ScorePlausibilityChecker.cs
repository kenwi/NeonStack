using Tetris.Highscores.Shared;

namespace Tetris.Highscores.Server;

/// <summary>
/// Soft heuristics for Tetris Guideline-style scoring. Suspicious scores are logged but still accepted.
/// </summary>
public static class ScorePlausibilityChecker
{
    // Soft drop + hard drop inflate score beyond pure line clears; allow generous headroom.
    private const int SoftDropBudgetPerLine = 400;
    private static readonly int[] LineClearPoints = [0, 100, 300, 500, 800];

    public static IReadOnlyList<string> GetSuspiciousReasons(ScoreSubmission submission)
    {
        var reasons = new List<string>();

        if (submission.Level != ExpectedLevel(submission.LinesCleared))
        {
            reasons.Add(
                $"Level {submission.Level} does not match lines-cleared formula " +
                $"(expected {ExpectedLevel(submission.LinesCleared)} for {submission.LinesCleared} lines).");
        }

        var maxFromLines = MaxPlausibleScore(submission.LinesCleared);
        if (submission.FinalScore > maxFromLines)
        {
            reasons.Add(
                $"FinalScore {submission.FinalScore} exceeds rough max {maxFromLines} " +
                $"for {submission.LinesCleared} lines.");
        }

        if (submission.LinesCleared == 0 && submission.FinalScore > SoftDropBudgetPerLine)
        {
            reasons.Add(
                $"FinalScore {submission.FinalScore} is high for a zero-line run.");
        }

        var minSeconds = Math.Max(1f, submission.LinesCleared * 0.4f);
        if (submission.ElapsedSeconds < minSeconds && submission.LinesCleared >= 10)
        {
            reasons.Add(
                $"ElapsedSeconds {submission.ElapsedSeconds:F3} is very low for {submission.LinesCleared} lines.");
        }

        return reasons;
    }

    private static int ExpectedLevel(int linesCleared) =>
        Math.Min(ScoreSanitizer.MaxLevel, 1 + linesCleared / 10);

    /// <summary>
    /// Upper bound assuming every line clear was a Tetris at the highest reachable level,
    /// plus soft/hard drop budget.
    /// </summary>
    private static int MaxPlausibleScore(int linesCleared)
    {
        if (linesCleared <= 0)
            return SoftDropBudgetPerLine;

        var remaining = linesCleared;
        var score = 0;
        var clearedSoFar = 0;

        while (remaining > 0)
        {
            var chunk = Math.Min(4, remaining);
            var level = ExpectedLevel(clearedSoFar);
            score += LineClearPoints[chunk] * level;
            clearedSoFar += chunk;
            remaining -= chunk;
        }

        score += linesCleared * SoftDropBudgetPerLine;
        return Math.Min(ScoreSanitizer.MaxScore, score);
    }
}
