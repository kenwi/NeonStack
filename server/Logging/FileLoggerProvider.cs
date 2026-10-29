using System.Collections;
using System.Globalization;
using System.Text;
using Microsoft.Extensions.Logging;

namespace Tetris.Highscores.Server.Logging;

public static class FileLoggerExtensions
{
    public static ILoggingBuilder AddFileLogger(this ILoggingBuilder builder, IConfiguration configuration)
    {
        var filePath = configuration["Logging:File:Path"];
        if (string.IsNullOrWhiteSpace(filePath))
            return builder;

        var minLevel = LogLevel.Information;
        if (Enum.TryParse<LogLevel>(configuration["Logging:File:MinLevel"], ignoreCase: true, out var configured))
            minLevel = configured;

        builder.AddProvider(new FileLoggerProvider(filePath, minLevel));
        return builder;
    }
}

public sealed class FileLoggerProvider : ILoggerProvider, ISupportExternalScope
{
    private readonly string _baseFilePath;
    private readonly LogLevel _minLevel;
    private readonly object _writeLock = new();
    private IExternalScopeProvider? _scopeProvider;

    private static readonly CultureInfo NorwegianCulture = CultureInfo.GetCultureInfo("nb-NO");

    public FileLoggerProvider(string filePath, LogLevel minLevel)
    {
        _baseFilePath = filePath;
        _minLevel = minLevel;

        var directory = Path.GetDirectoryName(ResolveDailyPath(filePath, DateTime.Now));
        if (!string.IsNullOrEmpty(directory))
            Directory.CreateDirectory(directory);
    }

    public void SetScopeProvider(IExternalScopeProvider scopeProvider) => _scopeProvider = scopeProvider;

    public ILogger CreateLogger(string categoryName) =>
        new FileLogger(categoryName, _baseFilePath, _minLevel, _writeLock, _scopeProvider);

    public void Dispose() { }

    internal static string ResolveDailyPath(string baseFilePath, DateTime date)
    {
        var directory = Path.GetDirectoryName(baseFilePath) ?? string.Empty;
        var fileName = Path.GetFileNameWithoutExtension(baseFilePath);
        var extension = Path.GetExtension(baseFilePath);
        return Path.Combine(directory, $"{fileName}-{date:yyyy-MM-dd}{extension}");
    }

    private sealed class FileLogger : ILogger
    {
        private readonly string _category;
        private readonly string _baseFilePath;
        private readonly LogLevel _minLevel;
        private readonly object _writeLock;
        private readonly IExternalScopeProvider? _scopeProvider;

        public FileLogger(
            string category,
            string baseFilePath,
            LogLevel minLevel,
            object writeLock,
            IExternalScopeProvider? scopeProvider)
        {
            _category = category;
            _baseFilePath = baseFilePath;
            _minLevel = minLevel;
            _writeLock = writeLock;
            _scopeProvider = scopeProvider;
        }

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull =>
            _scopeProvider?.Push(state);

        public bool IsEnabled(LogLevel logLevel) => logLevel >= _minLevel;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel))
                return;

            var now = DateTime.Now;
            var timestamp = now.ToString("dd.MM.yyyy HH:mm:ss", NorwegianCulture);
            var level = logLevel switch
            {
                LogLevel.Trace => "TRC",
                LogLevel.Debug => "DBG",
                LogLevel.Information => "INF",
                LogLevel.Warning => "WRN",
                LogLevel.Error => "ERR",
                LogLevel.Critical => "CRT",
                _ => "???",
            };

            var builder = new StringBuilder();
            builder.Append('[').Append(timestamp).Append("] ");
            builder.Append('[').Append(level).Append("] ");

            var scopeText = FormatScopes();
            if (scopeText.Length > 0)
                builder.Append(scopeText).Append(' ');

            builder.Append(_category).Append(": ");
            builder.Append(formatter(state, exception));

            if (exception is not null)
            {
                builder.AppendLine();
                builder.Append(exception);
            }

            var filePath = ResolveDailyPath(_baseFilePath, now);
            lock (_writeLock)
                File.AppendAllText(filePath, builder.ToString() + Environment.NewLine);
        }

        private string FormatScopes()
        {
            if (_scopeProvider is null)
                return string.Empty;

            var parts = new List<string>();
            _scopeProvider.ForEachScope((scope, list) =>
            {
                if (scope is IEnumerable<KeyValuePair<string, object?>> keyValues)
                {
                    foreach (var (key, value) in keyValues)
                        list.Add($"{key}={value}");
                }
                else if (scope is not null)
                {
                    list.Add(scope.ToString() ?? string.Empty);
                }
            }, parts);

            return parts.Count == 0 ? string.Empty : $"[{string.Join(" ", parts)}]";
        }
    }
}
