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
}
