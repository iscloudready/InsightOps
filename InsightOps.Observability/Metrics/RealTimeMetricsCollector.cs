// InsightOps.Observability/Metrics/RealTimeMetricsCollector.cs
using System.Collections.Concurrent;
using System.Diagnostics.Metrics;

namespace InsightOps.Observability.Metrics;

public class RealTimeMetricsCollector
{
    private readonly Meter _meter;
    private readonly Counter<long> _requestCounter;
    private readonly Histogram<double> _requestDuration;
    private readonly Counter<long> _errorCounter;
    private readonly ConcurrentDictionary<string, RequestMetrics> _endpointMetrics;

    public RealTimeMetricsCollector()
    {
        _meter = new Meter("InsightOps.Metrics");
        _requestCounter = _meter.CreateCounter<long>("http_requests_total");
        _requestDuration = _meter.CreateHistogram<double>("http_request_duration_seconds");
        _errorCounter = _meter.CreateCounter<long>("http_request_errors_total");
        _endpointMetrics = new ConcurrentDictionary<string, RequestMetrics>();
    }

    public void RecordRequestStarted(string path)
    {
        var metrics = _endpointMetrics.GetOrAdd(path, _ => new RequestMetrics());
        _requestCounter.Add(1, new KeyValuePair<string, object?>("path", path));
        metrics.ActiveRequests++;
    }

    public void RecordMetric(string metricName, double value)
    {
        _meter.CreateObservableGauge(metricName, () => value, "units", "Dynamic metric value");
    }

    public void RecordRequestCompleted(string path, int statusCode, double duration)
    {
        if (_endpointMetrics.TryGetValue(path, out var metrics))
        {
            metrics.ActiveRequests--;
            metrics.TotalRequests++;
            metrics.TotalDuration += duration;

            if (statusCode >= 400)
            {
                metrics.ErrorCount++;
                _errorCounter.Add(1, new KeyValuePair<string, object?>("path", path));
            }

            _requestDuration.Record(
                duration,
                new KeyValuePair<string, object?>("path", path),
                new KeyValuePair<string, object?>("status_code", statusCode.ToString()));
        }

    }

    public IReadOnlyDictionary<string, RequestMetrics> GetEndpointMetrics()
    {
        return _endpointMetrics;
    }

    public class RequestMetrics
    {
        public long ActiveRequests { get; set; }
        public long TotalRequests { get; set; }
        public long ErrorCount { get; set; }
        public double TotalDuration { get; set; }

        public double AverageResponseTime =>
            TotalRequests > 0 ? TotalDuration / TotalRequests : 0;

        public double ErrorRate =>
            TotalRequests > 0 ? (double)ErrorCount / TotalRequests : 0;
    }
}