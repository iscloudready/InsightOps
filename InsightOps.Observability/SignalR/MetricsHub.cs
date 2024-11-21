namespace InsightOps.Observability.SignalR
{
    using InsightOps.Observability.Metrics;
    using Microsoft.AspNetCore.SignalR;

    public class MetricsHub : Hub
    {
        private readonly RealTimeMetricsCollector _metricsCollector;

        public MetricsHub(RealTimeMetricsCollector metricsCollector)
        {
            _metricsCollector = metricsCollector;
        }

        public async Task UpdateMetrics(string service, string metric, double value)
        {
            // Notify all connected clients
            await Clients.All.SendAsync("MetricUpdated", service, metric, value);
        }
    }
}
