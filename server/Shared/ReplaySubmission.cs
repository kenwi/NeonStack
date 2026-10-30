namespace Tetris.Highscores.Shared;

/// <summary>Optional replay upload linked to an existing score by checksum.</summary>
public sealed class ReplaySubmission
{
    public string Checksum { get; set; } = string.Empty;
    public string ModeId { get; set; } = string.Empty;
    public System.Text.Json.JsonElement Replay { get; set; }
}
