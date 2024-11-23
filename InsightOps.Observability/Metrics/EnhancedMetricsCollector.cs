using InsightOps.Observability.Metrics;
using InsightOps.Observability.SignalR;
using Microsoft.AspNetCore.SignalR;

public class EnhancedMetricsCollector : RealTimeMetricsCollector
{
    private readonly IHubContext<MetricsHub> _hubContext;

    public EnhancedMetricsCollector(IHubContext<MetricsHub> hubContext)
    {
        _hubContext = hubContext;
    }

    public async Task RecordRequestWithNotificationAsync(string path, int statusCode, double duration)
    {
        RecordRequestStarted(path);
        RecordRequestCompleted(path, statusCode, duration);

        // Notify SignalR clients
        await _hubContext.Clients.All.SendAsync("RequestMetricUpdated", path, statusCode, duration);
    }

    public async Task RecordMetricAsync(string metric, double value)
    {
        base.RecordMetric(metric, value);
        await _hubContext.Clients.All.SendAsync("MetricUpdated", metric, value);
    }
}