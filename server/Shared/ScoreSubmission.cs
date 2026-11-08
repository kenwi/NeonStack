namespace Tetris.Highscores.Shared;

/// <summary>Payload sent to the highscore API when a run is submitted.</summary>
public sealed class ScoreSubmission
{
    public string ModeId { get; set; } = string.Empty;
    public string PlayerName { get; set; } = string.Empty;
    public int FinalScore { get; set; }
    public int LinesCleared { get; set; }
    public int Level { get; set; }
    public float ElapsedSeconds { get; set; }
    public string Checksum { get; set; } = string.Empty;
    /// <summary>Optional device-local player id; not part of checksum.</summary>
    public string? PlayerId { get; set; }
    /// <summary>Optional replay object. Required when the score would rank in the top 10.</summary>
    public System.Text.Json.JsonElement Replay { get; set; }
}
