namespace Tetris.Highscores.Shared;

/// <summary>POST /api/challenges body.</summary>
public sealed class CreateChallengeRequest
{
    public string? Name { get; set; }
    public string? Family { get; set; }
    public string? Difficulty { get; set; }
}

/// <summary>Challenge board metadata returned to clients.</summary>
public sealed class ChallengeDto
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string Family { get; init; }
    public required string Difficulty { get; init; }
    public long? PeriodUnix { get; init; }
    public DateTimeOffset CreatedAt { get; init; }
}
