using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Tetris.Highscores.Shared;

/// <summary>
/// Deterministic score checksum shared by client and server.
/// A secret embedded in the game build deters casual tampering but is not real security.
/// </summary>
public static class ScoreChecksum
{
    private const string SharedSecret = "Tetris.Highscores.v1";

    public static string Compute(ScoreSubmission submission)
    {
        var canonical = string.Join('|',
            submission.ModeId,
            submission.PlayerName,
            submission.FinalScore.ToString(CultureInfo.InvariantCulture),
            submission.LinesCleared.ToString(CultureInfo.InvariantCulture),
            submission.Level.ToString(CultureInfo.InvariantCulture),
            submission.ElapsedSeconds.ToString("F3", CultureInfo.InvariantCulture),
            SharedSecret);

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public static bool Verify(ScoreSubmission submission)
    {
        if (string.IsNullOrWhiteSpace(submission.Checksum))
            return false;

        var expected = Compute(submission);
        return string.Equals(expected, submission.Checksum.Trim(), StringComparison.OrdinalIgnoreCase);
    }
}
