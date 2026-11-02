using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Tetris.Highscores.Shared;

namespace Tetris.Highscores.Server;

public sealed class ChallengeStore
{
    public const string ModeIdPrefix = "c_";
    public const int TokenLength = 12;
    public const int MaxNameLength = 32;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    private static readonly Regex InvalidNameChars = new(
        @"[^A-Za-z0-9À-ÖØ-öø-ÿ _.!?'\-]",
        RegexOptions.Compiled);

    private static readonly HashSet<string> ValidFamilies = new(StringComparer.OrdinalIgnoreCase)
    {
        "classic", "daily", "weekly"
    };

    private static readonly HashSet<string> ValidDifficulties = new(StringComparer.OrdinalIgnoreCase)
    {
        "classic", "hardcore"
    };

    private static readonly char[] TokenAlphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".ToCharArray();

    private readonly string _filePath;
    private readonly ILogger<ChallengeStore> _logger;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public ChallengeStore(IConfiguration configuration, ILogger<ChallengeStore> logger)
    {
        var configured = configuration["Highscores:ChallengesFilePath"];
        if (!string.IsNullOrWhiteSpace(configured))
        {
            _filePath = configured;
        }
        else
        {
            var scorePath = configuration["Highscores:FilePath"] ?? "highscores.json";
            var dir = Path.GetDirectoryName(Path.GetFullPath(scorePath)) ?? ".";
            _filePath = Path.Combine(dir, "challenges.json");
        }

        _logger = logger;
        _logger.LogInformation(
            "ChallengeStore initialized. FilePath={FilePath}",
            Path.GetFullPath(_filePath));
    }

    public static bool IsChallengeModeId(string? modeId)
    {
        if (string.IsNullOrEmpty(modeId))
            return false;
        var core = modeId.EndsWith("-mobile", StringComparison.OrdinalIgnoreCase)
            ? modeId[..^"-mobile".Length]
            : modeId;
        return core.StartsWith(ModeIdPrefix, StringComparison.OrdinalIgnoreCase);
    }

    public static string ScoreModeId(string token, bool mobile) =>
        mobile ? $"{ModeIdPrefix}{token}-mobile" : $"{ModeIdPrefix}{token}";

    public async Task<(ChallengeDto? Challenge, string? Error)> TryCreateAsync(
        CreateChallengeRequest request,
        CancellationToken cancellationToken = default)
    {
        var name = SanitizeName(request.Name);
        if (string.IsNullOrEmpty(name))
            return (null, "Name is required.");

        var family = (request.Family ?? "classic").Trim().ToLowerInvariant();
        if (!ValidFamilies.Contains(family))
            return (null, "Family must be classic, daily, or weekly.");

        var difficulty = (request.Difficulty ?? "classic").Trim().ToLowerInvariant();
        if (!ValidDifficulties.Contains(difficulty))
            return (null, "Difficulty must be classic or hardcore.");

        long? periodUnix = null;
        if (family is "daily" or "weekly")
            periodUnix = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        await _lock.WaitAsync(cancellationToken);
        try
        {
            var data = await ReadAsync(cancellationToken);
            string token;
            var attempts = 0;
            do
            {
                token = GenerateToken();
                attempts++;
                if (attempts > 8)
                    return (null, "Could not allocate a unique challenge id.");
            } while (data.Boards.ContainsKey(token));

            var createdAt = DateTimeOffset.Now;
            var entry = new StoredChallenge
            {
                Name = name,
                Family = family,
                Difficulty = difficulty,
                PeriodUnix = periodUnix,
                CreatedAt = createdAt
            };
            data.Boards[token] = entry;
            await WriteAsync(data, cancellationToken);

            _logger.LogInformation(
                "Challenge created: Id={Id}, Name={Name}, Family={Family}, Difficulty={Difficulty}, PeriodUnix={PeriodUnix}",
                token,
                name,
                family,
                difficulty,
                periodUnix);

            return (ToDto(token, entry), null);
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<ChallengeDto?> TryGetAsync(string rawId, CancellationToken cancellationToken = default)
    {
        var token = SanitizeToken(rawId);
        if (string.IsNullOrEmpty(token))
            return null;

        await _lock.WaitAsync(cancellationToken);
        try
        {
            var data = await ReadAsync(cancellationToken);
            if (!data.Boards.TryGetValue(token, out var entry))
                return null;
            return ToDto(token, entry);
        }
        finally
        {
            _lock.Release();
        }
    }

    public static string SanitizeToken(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return string.Empty;

        var trimmed = raw.Trim();
        if (trimmed.StartsWith(ModeIdPrefix, StringComparison.OrdinalIgnoreCase))
            trimmed = trimmed[ModeIdPrefix.Length..];
        if (trimmed.EndsWith("-mobile", StringComparison.OrdinalIgnoreCase))
            trimmed = trimmed[..^"-mobile".Length];

        if (trimmed.Length > TokenLength)
            trimmed = trimmed[..TokenLength];

        var sb = new StringBuilder(trimmed.Length);
        foreach (var ch in trimmed)
        {
            if (char.IsAsciiLetterOrDigit(ch) || ch is '_' or '-')
                sb.Append(ch);
        }

        return sb.ToString();
    }

    public static string SanitizeName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
            return string.Empty;

        var trimmed = name.Trim();
        if (trimmed.Length > MaxNameLength)
            trimmed = trimmed[..MaxNameLength];

        var cleaned = InvalidNameChars.Replace(trimmed, string.Empty).Trim();
        return cleaned;
    }

    private static ChallengeDto ToDto(string id, StoredChallenge entry) => new()
    {
        Id = id,
        Name = entry.Name,
        Family = entry.Family,
        Difficulty = entry.Difficulty,
        PeriodUnix = entry.PeriodUnix,
        CreatedAt = entry.CreatedAt
    };

    private static string GenerateToken()
    {
        Span<byte> bytes = stackalloc byte[TokenLength];
        RandomNumberGenerator.Fill(bytes);
        var chars = new char[TokenLength];
        for (var i = 0; i < TokenLength; i++)
            chars[i] = TokenAlphabet[bytes[i] % TokenAlphabet.Length];
        return new string(chars);
    }

    private async Task<ChallengeFile> ReadAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_filePath))
            return new ChallengeFile();

        await using var stream = File.OpenRead(_filePath);
        var data = await JsonSerializer.DeserializeAsync<ChallengeFile>(stream, JsonOptions, cancellationToken);
        return data ?? new ChallengeFile();
    }

    private async Task WriteAsync(ChallengeFile data, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(_filePath));
        if (!string.IsNullOrEmpty(directory))
            Directory.CreateDirectory(directory);

        var tempPath = _filePath + ".tmp";
        await using (var stream = File.Create(tempPath))
        {
            await JsonSerializer.SerializeAsync(stream, data, JsonOptions, cancellationToken);
        }

        File.Move(tempPath, _filePath, overwrite: true);
    }

    private sealed class ChallengeFile
    {
        public Dictionary<string, StoredChallenge> Boards { get; set; } =
            new(StringComparer.OrdinalIgnoreCase);
    }

    private sealed class StoredChallenge
    {
        public string Name { get; set; } = "";
        public string Family { get; set; } = "classic";
        public string Difficulty { get; set; } = "classic";
        public long? PeriodUnix { get; set; }
        public DateTimeOffset CreatedAt { get; set; }
    }
}
