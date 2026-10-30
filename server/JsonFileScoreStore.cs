using System.Text.Json;
using Microsoft.Extensions.Logging;
using Tetris.Highscores.Shared;

namespace Tetris.Highscores.Server;

/// <summary>Outcome of a score submission. Rank is 1-based within the mode's leaderboard.</summary>
public sealed record ScoreAddResult(bool Accepted, int Rank, int TotalEntriesForMode, string? Error = null)
{
    public static readonly ScoreAddResult Duplicate = new(false, 0, 0, "duplicate");

    public static ScoreAddResult Failed(string error) => new(false, 0, 0, error);
}

public sealed class JsonFileScoreStore
{
    public const int MaxReplayBytes = 1_048_576;
    public const int TopReplayRequiredRank = 10;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    private readonly string _filePath;
    private readonly string _replayDir;
    private readonly ILogger<JsonFileScoreStore> _logger;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public JsonFileScoreStore(IConfiguration configuration, ILogger<JsonFileScoreStore> logger)
    {
        _filePath = configuration["Highscores:FilePath"] ?? "highscores.json";
        var configuredReplayDir = configuration["Highscores:ReplayDirectory"];
        _replayDir = string.IsNullOrWhiteSpace(configuredReplayDir)
            ? Path.Combine(Path.GetDirectoryName(Path.GetFullPath(_filePath)) ?? ".", "replays")
            : configuredReplayDir;
        _logger = logger;
        _logger.LogInformation(
            "JsonFileScoreStore initialized. FilePath={FilePath}, ReplayDir={ReplayDir}",
            Path.GetFullPath(_filePath),
            Path.GetFullPath(_replayDir));
    }

    public async Task<ScoreAddResult> TryAddScoreAsync(ScoreSubmission submission, CancellationToken cancellationToken = default)
    {
        await _lock.WaitAsync(cancellationToken);
        try
        {
            var checksum = ScoreChecksum.Compute(submission);
            var data = await ReadAsync(cancellationToken);

            if (ContainsChecksum(data, checksum))
            {
                _logger.LogWarning(
                    "Score rejected (duplicate checksum): ModeId={ModeId}, PlayerName={PlayerName}, " +
                    "FinalScore={FinalScore}, Checksum={Checksum}, FilePath={FilePath}",
                    submission.ModeId,
                    submission.PlayerName,
                    submission.FinalScore,
                    checksum,
                    _filePath);
                return ScoreAddResult.Duplicate;
            }

            if (!data.Modes.TryGetValue(submission.ModeId, out var entries))
            {
                entries = [];
                data.Modes[submission.ModeId] = entries;
            }

            var submittedAt = DateTimeOffset.Now;
            var newEntry = new StoredScoreEntry
            {
                PlayerName = submission.PlayerName,
                FinalScore = submission.FinalScore,
                LinesCleared = submission.LinesCleared,
                Level = submission.Level,
                ElapsedSeconds = submission.ElapsedSeconds,
                SubmittedAt = submittedAt,
                Checksum = checksum,
                HasReplay = false
            };

            var rank = entries
                .Append(newEntry)
                .OrderByDescending(e => e.FinalScore)
                .ThenBy(e => e.ElapsedSeconds)
                .ThenBy(e => e.SubmittedAt)
                .ToList()
                .FindIndex(e => ReferenceEquals(e, newEntry)) + 1;

            var hasReplayPayload = submission.Replay.ValueKind == JsonValueKind.Object;
            if (rank <= TopReplayRequiredRank)
            {
                if (!hasReplayPayload)
                {
                    _logger.LogWarning(
                        "Score rejected (top {Top} requires replay): ModeId={ModeId}, PlayerName={PlayerName}, " +
                        "FinalScore={FinalScore}, ProjectedRank={ProjectedRank}",
                        TopReplayRequiredRank,
                        submission.ModeId,
                        submission.PlayerName,
                        submission.FinalScore,
                        rank);
                    return ScoreAddResult.Failed("Replay is required for top 10 scores.");
                }

                var replayJson = submission.Replay.GetRawText();
                var byteCount = System.Text.Encoding.UTF8.GetByteCount(replayJson);
                if (byteCount > MaxReplayBytes)
                    return ScoreAddResult.Failed("Replay exceeds size limit.");

                if (!TryValidateReplaySchema(replayJson, out var schemaError))
                    return ScoreAddResult.Failed(schemaError);

                if (!TryMatchReplayOutcome(replayJson, newEntry, out var outcomeError))
                    return ScoreAddResult.Failed(outcomeError);

                Directory.CreateDirectory(_replayDir);
                await File.WriteAllTextAsync(ReplayPath(checksum), replayJson, cancellationToken);
                newEntry.HasReplay = true;
                _logger.LogInformation(
                    "Top-rank replay attached on submit: Checksum={Checksum}, ModeId={ModeId}, Rank={Rank}, Bytes={Bytes}",
                    checksum,
                    submission.ModeId,
                    rank,
                    byteCount);
            }

            entries.Add(newEntry);

            _logger.LogInformation(
                "Score persisted: ModeId={ModeId}, PlayerName={PlayerName}, FinalScore={FinalScore}, " +
                "Rank={Rank}, HasReplay={HasReplay}, ModeEntryCount={ModeEntryCount}, FilePath={FilePath}",
                submission.ModeId,
                submission.PlayerName,
                submission.FinalScore,
                rank,
                newEntry.HasReplay,
                entries.Count,
                _filePath);

            await WriteAsync(data, cancellationToken);
            return new ScoreAddResult(true, rank, entries.Count);
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<IReadOnlyList<HighscoreEntry>> GetTopAsync(
        string modeId,
        int top,
        CancellationToken cancellationToken = default)
    {
        await _lock.WaitAsync(cancellationToken);
        try
        {
            var data = await ReadAsync(cancellationToken);
            if (!data.Modes.TryGetValue(modeId, out var entries))
                return Array.Empty<HighscoreEntry>();

            var results = entries
                .OrderByDescending(e => e.FinalScore)
                .ThenBy(e => e.ElapsedSeconds)
                .ThenBy(e => e.SubmittedAt)
                .Take(top)
                .Select((entry, index) => new HighscoreEntry
                {
                    Rank = index + 1,
                    PlayerName = entry.PlayerName,
                    FinalScore = entry.FinalScore,
                    LinesCleared = entry.LinesCleared,
                    Level = entry.Level,
                    ElapsedSeconds = entry.ElapsedSeconds,
                    SubmittedAt = entry.SubmittedAt,
                    Checksum = entry.Checksum,
                    HasReplay = entry.HasReplay
                })
                .ToArray();

            _logger.LogInformation(
                "Leaderboard queried: ModeId={ModeId}, RequestedTop={RequestedTop}, ReturnedCount={ReturnedCount}, " +
                "TotalStoredForMode={TotalStoredForMode}",
                modeId,
                top,
                results.Length,
                entries.Count);

            return results;
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<(bool Ok, string Error)> TryAttachReplayAsync(
        string checksum,
        string modeId,
        string replayJson,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(checksum))
            return (false, "Checksum is required.");
        if (string.IsNullOrWhiteSpace(modeId))
            return (false, "ModeId is required.");
        if (string.IsNullOrWhiteSpace(replayJson))
            return (false, "Replay body is required.");

        var byteCount = System.Text.Encoding.UTF8.GetByteCount(replayJson);
        if (byteCount > MaxReplayBytes)
            return (false, "Replay exceeds size limit.");

        if (!TryValidateReplaySchema(replayJson, out var schemaError))
            return (false, schemaError);

        await _lock.WaitAsync(cancellationToken);
        try
        {
            var data = await ReadAsync(cancellationToken);
            if (!data.Modes.TryGetValue(modeId, out var modeEntries))
                return (false, "No score found for checksum.");

            var match = modeEntries.FirstOrDefault(e =>
                !string.IsNullOrEmpty(e.Checksum) &&
                string.Equals(e.Checksum, checksum, StringComparison.OrdinalIgnoreCase));
            if (match == null)
                return (false, "No score found for checksum.");

            if (!TryMatchReplayOutcome(replayJson, match, out var outcomeError))
                return (false, outcomeError);

            Directory.CreateDirectory(_replayDir);
            var path = ReplayPath(checksum);
            await File.WriteAllTextAsync(path, replayJson, cancellationToken);
            match.HasReplay = true;
            await WriteAsync(data, cancellationToken);

            _logger.LogInformation(
                "Replay attached: Checksum={Checksum}, ModeId={ModeId}, Bytes={Bytes}, Path={Path}",
                checksum,
                modeId,
                byteCount,
                path);
            return (true, string.Empty);
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<string?> GetReplayJsonAsync(string checksum, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(checksum))
            return null;

        await _lock.WaitAsync(cancellationToken);
        try
        {
            var path = ReplayPath(checksum);
            if (!File.Exists(path))
                return null;
            return await File.ReadAllTextAsync(path, cancellationToken);
        }
        finally
        {
            _lock.Release();
        }
    }

    private string ReplayPath(string checksum)
    {
        var safe = new string(checksum.Where(ch => char.IsAsciiLetterOrDigit(ch) || ch is '-' or '_').ToArray());
        if (string.IsNullOrEmpty(safe))
            safe = "invalid";
        return Path.Combine(_replayDir, $"{safe}.json");
    }

    private static bool TryValidateReplaySchema(string replayJson, out string error)
    {
        error = string.Empty;
        try
        {
            using var doc = JsonDocument.Parse(replayJson);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                error = "Replay must be a JSON object.";
                return false;
            }

            if (!root.TryGetProperty("v", out var version) || !TryReadInt(version, out var versionValue) ||
                versionValue != 1)
            {
                error = "Unsupported replay version.";
                return false;
            }

            // Godot hash() often exceeds Int32; accept full Int64 JSON integers (and float ints).
            if (!root.TryGetProperty("seed", out var seed) || !TryReadInt64(seed, out _))
            {
                error = "Replay seed is required.";
                return false;
            }

            if (!root.TryGetProperty("tickHz", out var tickHz) || !TryReadInt(tickHz, out var tickHzValue) ||
                tickHzValue != 60)
            {
                error = "Replay tickHz must be 60.";
                return false;
            }

            if (!root.TryGetProperty("events", out var events) || events.ValueKind != JsonValueKind.Array)
            {
                error = "Replay events array is required.";
                return false;
            }

            return true;
        }
        catch (JsonException)
        {
            error = "Replay JSON is invalid.";
            return false;
        }
    }

    private static bool TryMatchReplayOutcome(string replayJson, StoredScoreEntry entry, out string error)
    {
        error = string.Empty;
        try
        {
            using var doc = JsonDocument.Parse(replayJson);
            var root = doc.RootElement;
            if (root.TryGetProperty("finalScore", out var score) && TryReadInt(score, out var finalScore) &&
                finalScore != entry.FinalScore)
            {
                error = "Replay finalScore does not match stored score.";
                return false;
            }

            if (root.TryGetProperty("linesCleared", out var lines) && TryReadInt(lines, out var linesCleared) &&
                linesCleared != entry.LinesCleared)
            {
                error = "Replay linesCleared does not match stored score.";
                return false;
            }

            return true;
        }
        catch (JsonException)
        {
            error = "Replay JSON is invalid.";
            return false;
        }
    }

    /// <summary>Godot JSON often emits ints as floats (1.0). Accept both.</summary>
    private static bool TryReadInt(JsonElement element, out int value)
    {
        if (element.TryGetInt32(out value))
            return true;

        if (element.ValueKind == JsonValueKind.Number &&
            element.TryGetDouble(out var number) &&
            double.IsFinite(number) &&
            Math.Abs(number - Math.Truncate(number)) < 0.0000001 &&
            number >= int.MinValue &&
            number <= int.MaxValue)
        {
            value = (int)number;
            return true;
        }

        value = 0;
        return false;
    }

    /// <summary>Same as TryReadInt but for Int64 (Godot hash seeds often exceed Int32.MaxValue).</summary>
    private static bool TryReadInt64(JsonElement element, out long value)
    {
        if (element.TryGetInt64(out value))
            return true;

        if (element.ValueKind == JsonValueKind.Number &&
            element.TryGetDouble(out var number) &&
            double.IsFinite(number) &&
            Math.Abs(number - Math.Truncate(number)) < 0.0000001 &&
            number >= long.MinValue &&
            number <= long.MaxValue)
        {
            value = (long)number;
            return true;
        }

        value = 0;
        return false;
    }

    private static bool ContainsChecksum(HighscoreStoreData data, string checksum) =>
        data.Modes.Values
            .SelectMany(entries => entries)
            .Any(entry => !string.IsNullOrEmpty(entry.Checksum) &&
                          string.Equals(entry.Checksum, checksum, StringComparison.OrdinalIgnoreCase));

    private async Task<HighscoreStoreData> ReadAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_filePath))
            return new HighscoreStoreData();

        await using var stream = File.OpenRead(_filePath);
        var data = await JsonSerializer.DeserializeAsync<HighscoreStoreData>(stream, JsonOptions, cancellationToken);
        return data ?? new HighscoreStoreData();
    }

    private async Task WriteAsync(HighscoreStoreData data, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(_filePath);
        if (!string.IsNullOrEmpty(directory))
            Directory.CreateDirectory(directory);

        await using var stream = File.Create(_filePath);
        await JsonSerializer.SerializeAsync(stream, data, JsonOptions, cancellationToken);
    }

    private sealed class HighscoreStoreData
    {
        public Dictionary<string, List<StoredScoreEntry>> Modes { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }

    private sealed class StoredScoreEntry
    {
        public string PlayerName { get; set; } = string.Empty;
        public int FinalScore { get; set; }
        public int LinesCleared { get; set; }
        public int Level { get; set; }
        public float ElapsedSeconds { get; set; }
        public DateTimeOffset SubmittedAt { get; set; }
        public string Checksum { get; set; } = string.Empty;
        public bool HasReplay { get; set; }
    }
}
