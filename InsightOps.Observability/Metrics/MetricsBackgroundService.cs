using InsightOps.Observability.Metrics;
using InsightOps.Observability.Options;
using InsightOps.Observability.SignalR;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

public class MetricsBackgroundService : BackgroundService
{
    private readonly ILogger<MetricsBackgroundService> _logger;
    private readonly RealTimeMetricsCollector _metricsCollector;
    private readonly SystemMetricsCollector _systemMetrics;
    private readonly IHubContext<MetricsHub> _hubContext;
    private readonly ObservabilityOptions _options;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CollectAndBroadcastMetrics(stoppingToken);
                await Task.Delay(TimeSpan.FromSeconds(_options.Common.MetricsInterval), stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "Error collecting metrics");
            }
        }
    }

    private async Task CollectAndBroadcastMetrics(CancellationToken ct)
    {
        var systemMetrics = _systemMetrics.GetSystemMetrics();
        var metrics = _metricsCollector.GetEndpointMetrics();

        await _hubContext.Clients.All.SendAsync("MetricsUpdated", new
        {
            System = systemMetrics,
            Endpoints = metrics
        }, ct);
    }
}