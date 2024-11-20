// FrontendService/Monitoring/MetricsHub.cs
using Microsoft.AspNetCore.SignalR;

namespace FrontendService.Monitoring
{
    public class MetricsHub : Hub
    {
        private readonly RealTimeMetricsCollector _metricsCollector;

        public MetricsHub(RealTimeMetricsCollector metricsCollector)
        {
            _metricsCollector = metricsCollector;
        }

        public async Task UpdateMetrics(string service, string metric, double value)
        {
            await Clients.All.SendAsync("MetricUpdated", service, metric, value);
        }
    }
}