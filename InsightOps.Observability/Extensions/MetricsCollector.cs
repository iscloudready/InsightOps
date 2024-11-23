using Microsoft.Extensions.Logging;

namespace FrontendService.Services.Monitoring
{
    public class MetricsCollector
    {
        private readonly ILogger<MetricsCollector> _logger;
        private readonly Dictionary<string, List<MetricDataPoint>> _metricHistory;
        private readonly int _retentionHours;

        public MetricsCollector(ILogger<MetricsCollector> logger, int retentionHours = 24)
        {
            _logger = logger;
            _metricHistory = new Dictionary<string, List<MetricDataPoint>>();
            _retentionHours = retentionHours;
        }

        public void RecordMetric(string name, double value, Dictionary<string, string> tags = null)
        {
            var dataPoint = new MetricDataPoint
            {
                Timestamp = DateTime.UtcNow,
                Value = value,
                Tags = tags ?? new Dictionary<string, string>()
            };

            lock (_metricHistory)
            {
                if (!_metricHistory.ContainsKey(name))
                {
                    _metricHistory[name] = new List<MetricDataPoint>();
                }

                _metricHistory[name].Add(dataPoint);

                // Cleanup old data points
                var cutoff = DateTime.UtcNow.AddHours(-_retentionHours);
                _metricHistory[name].RemoveAll(dp => dp.Timestamp < cutoff);

                _logger.LogDebug("Recorded metric {MetricName}: {Value}", name, value);
            }
        }

        public IEnumerable<MetricSummary> GetMetricSummaries()
        {
            lock (_metricHistory)
            {
                return _metricHistory.Select(kvp => new MetricSummary
                {
                    Name = kvp.Key,
                    LastValue = kvp.Value.LastOrDefault()?.Value ?? 0,
                    Average = kvp.Value.Any() ? kvp.Value.Average(dp => dp.Value) : 0,
                    Min = kvp.Value.Any() ? kvp.Value.Min(dp => dp.Value) : 0,
                    Max = kvp.Value.Any() ? kvp.Value.Max(dp => dp.Value) : 0,
                    DataPoints = kvp.Value.Count
                }).ToList();
            }
        }

        public class MetricDataPoint
        {
            public DateTime Timestamp { get; set; }
            public double Value { get; set; }
            public Dictionary<string, string> Tags { get; set; }
        }

        public class MetricSummary
        {
            public string Name { get; set; }
            public double LastValue { get; set; }
            public double Average { get; set; }
            public double Min { get; set; }
            public double Max { get; set; }
            public int DataPoints { get; set; }
        }
    }
}