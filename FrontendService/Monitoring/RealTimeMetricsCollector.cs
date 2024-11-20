using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using Microsoft.Extensions.Options;

namespace FrontendService.Monitoring
{
    public class RealTimeMetricsCollector
    {
        private readonly ILogger<RealTimeMetricsCollector> _logger;
        private readonly Meter _meter;
        private readonly MonitoringOptions _options;
        private readonly DateTime _startTime;

        private readonly ConcurrentDictionary<string, Counter<long>> _counters = new();
        private readonly ConcurrentDictionary<string, ObservableGauge<double>> _gauges = new();
        private readonly ConcurrentDictionary<string, Histogram<double>> _histograms = new();

        public RealTimeMetricsCollector(
            ILogger<RealTimeMetricsCollector> logger,
            IOptions<MonitoringOptions> options)
        {
            _logger = logger;
            _options = options.Value;
            _meter = new Meter("FrontendService");
            _startTime = DateTime.UtcNow;
            InitializeMetrics();
        }

        private double GetProcessUptime()
        {
            return (DateTime.UtcNow - _startTime).TotalMilliseconds;
        }

        private double GetCpuUsage()
        {
            try
            {
                using var process = Process.GetCurrentProcess();
                var totalProcessorTime = process.TotalProcessorTime.TotalMilliseconds;
                var uptime = GetProcessUptime();
                return (totalProcessorTime / (Environment.ProcessorCount * uptime)) * 100;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting CPU usage");
                return 0.0;
            }
        }

        public void RecordApiRequest(string endpoint, string method)
        {
            try
            {
                if (_counters.TryGetValue("api_requests", out var counter))
                {
                    counter.Add(1, new KeyValuePair<string, object?>[]
                    {
                        new("endpoint", endpoint),
                        new("method", method)
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error recording API request metric");
            }
        }

        public void RecordApiResponse(string endpoint, double duration)
        {
            try
            {
                if (_histograms.TryGetValue("api_response_time", out var histogram))
                {
                    histogram.Record(duration, new KeyValuePair<string, object?>[]
                    {
                        new("endpoint", endpoint)
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error recording API response metric");
            }
        }

        private void InitializeMetrics()
        {
            try
            {
                // API Metrics
                _counters["api_requests"] = _meter.CreateCounter<long>(
                    "api_requests_total",
                    description: "Total API requests");

                _histograms["api_response_time"] = _meter.CreateHistogram<double>(
                    "api_response_time_seconds",
                    unit: "s",
                    description: "API response time");

                // Process Metrics
                _gauges["cpu_usage"] = _meter.CreateObservableGauge<double>(
                    "process_cpu_usage",
                    () => GetCpuUsage(),
                    description: "Process CPU usage percentage");

                _gauges["uptime"] = _meter.CreateObservableGauge<double>(
                    "process_uptime_milliseconds",
                    () => GetProcessUptime(),
                    description: "Process uptime in milliseconds");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error initializing metrics");
            }
        }
    }
}