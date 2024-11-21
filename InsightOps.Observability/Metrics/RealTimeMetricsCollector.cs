namespace InsightOps.Observability.Metrics
{
    using Microsoft.Extensions.Logging;
    using System.Collections.Concurrent;
    using System.Diagnostics;
    using System.Diagnostics.Metrics;

    public class RealTimeMetricsCollector
    {
        private readonly ILogger<RealTimeMetricsCollector> _logger;
        private readonly Meter _meter;
        private readonly ConcurrentDictionary<string, Counter<long>> _counters;
        private readonly ConcurrentDictionary<string, Histogram<double>> _histograms;

        public RealTimeMetricsCollector(ILogger<RealTimeMetricsCollector> logger)
        {
            _logger = logger;
            _meter = new Meter("InsightOpsMetrics");
            _counters = new ConcurrentDictionary<string, Counter<long>>();
            _histograms = new ConcurrentDictionary<string, Histogram<double>>();

            InitializeMetrics();
        }

        private void InitializeMetrics()
        {
            _counters["api_requests"] = _meter.CreateCounter<long>("api_requests_total", "Total API requests");
            _histograms["api_response_time"] = _meter.CreateHistogram<double>("api_response_time_seconds", "API response time");
        }

        public void RecordApiRequest(string endpoint, string method)
        {
            if (_counters.TryGetValue("api_requests", out var counter))
            {
                counter.Add(1, new KeyValuePair<string, object?>("endpoint", endpoint));
            }
        }

        public void RecordApiResponse(string endpoint, double duration)
        {
            if (_histograms.TryGetValue("api_response_time", out var histogram))
            {
                histogram.Record(duration, new KeyValuePair<string, object?>("endpoint", endpoint));
            }
        }
    }
}
