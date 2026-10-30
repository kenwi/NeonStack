namespace Tetris.Highscores.Shared;

/// <summary>One ranked row returned by the highscore API.</summary>
public sealed class HighscoreEntry
{
    public int Rank { get; set; }
    public string PlayerName { get; set; } = string.Empty;
    public int FinalScore { get; set; }
    public int LinesCleared { get; set; }
    public int Level { get; set; }
    public float ElapsedSeconds { get; set; }
    public DateTimeOffset SubmittedAt { get; set; }
    public string Checksum { get; set; } = string.Empty;
    public bool HasReplay { get; set; }
}
