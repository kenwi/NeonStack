namespace Tetris.Highscores.Shared;

/// <summary>Payload sent when a player starts or restarts a real run. Logged only.</summary>
public sealed class SessionStartRequest
{
    public string ModeId { get; set; } = string.Empty;
    public string? PlayerName { get; set; }
    /// <summary>Optional device-local player id.</summary>
    public string? PlayerId { get; set; }
}
