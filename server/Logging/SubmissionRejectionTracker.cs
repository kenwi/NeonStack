namespace Tetris.Highscores.Server.Logging;

/// <summary>
/// Tracks score submission rejections per client IP to surface repeat offenders.
/// </summary>
public sealed class SubmissionRejectionTracker
{
    private readonly object _lock = new();
    private readonly Dictionary<string, List<DateTimeOffset>> _rejectionsByIp = new(StringComparer.Ordinal);
    private readonly TimeSpan _window;
    private readonly int _threshold;

    public SubmissionRejectionTracker(IConfiguration configuration)
    {
        _window = TimeSpan.FromMinutes(configuration.GetValue("Logging:RejectionTracker:WindowMinutes", 10));
        _threshold = configuration.GetValue("Logging:RejectionTracker:Threshold", 5);
    }

    public int RecordRejection(string clientIp)
    {
        var now = DateTimeOffset.UtcNow;
        lock (_lock)
        {
            if (!_rejectionsByIp.TryGetValue(clientIp, out var timestamps))
            {
                timestamps = [];
                _rejectionsByIp[clientIp] = timestamps;
            }

            timestamps.Add(now);
            PruneOld(timestamps, now);
            return timestamps.Count;
        }
    }

    public bool IsRepeatOffender(string clientIp, int currentCount) => currentCount >= _threshold;

    public int Threshold => _threshold;

    public TimeSpan Window => _window;

    private void PruneOld(List<DateTimeOffset> timestamps, DateTimeOffset now)
    {
        var cutoff = now - _window;
        timestamps.RemoveAll(timestamp => timestamp < cutoff);
    }
}
