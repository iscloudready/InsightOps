// FrontendService/Extensions/MetricsExtensions.cs
using InsightOps.Observability.Metrics;

namespace FrontendService.Extensions
{
    public static class MetricsExtensions
    {
        public static void RecordCustomMetric(
            this RealTimeMetricsCollector collector,
            string name,
            double value)
        {
            collector.RecordMetric(name, value);
        }

        public static double GetCustomRequestRate(
            this RealTimeMetricsCollector collector)
        {
            var metrics = collector.GetEndpointMetrics();
            return metrics.Values.Sum(m => m.ActiveRequests);
        }
    }
}