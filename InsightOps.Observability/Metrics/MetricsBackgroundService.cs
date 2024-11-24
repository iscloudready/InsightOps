using InsightOps.Observability.Metrics;
using InsightOps.Observability.Options;
using InsightOps.Observability.SignalR;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

public class MetricsBackgroundService : BackgroundService
{
    private readonly ILogger<MetricsBackgroundService> _logger;
    private readonly RealTimeMetricsCollector _metricsCollector;
    private readonly SystemMetricsCollector _systemMetrics;
    private readonly IHubContext<MetricsHub> _hubContext;
    private readonly IConfiguration _configuration;

    public MetricsBackgroundService(
        ILogger<MetricsBackgroundService> logger,
        RealTimeMetricsCollector metricsCollector,
        SystemMetricsCollector systemMetrics,
        IHubContext<MetricsHub> hubContext,
        IConfiguration configuration)
    {
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _metricsCollector = metricsCollector ?? throw new ArgumentNullException(nameof(metricsCollector));
        _systemMetrics = systemMetrics ?? throw new ArgumentNullException(nameof(systemMetrics));
        _hubContext = hubContext ?? throw new ArgumentNullException(nameof(hubContext));
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var metricsInterval = _configuration.GetValue<int>("Observability:Common:MetricsInterval", 10);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CollectAndBroadcastMetrics(stoppingToken);
                await Task.Delay(TimeSpan.FromSeconds(metricsInterval), stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "Error collecting metrics");
            }
        }
    }

    private async Task CollectAndBroadcastMetrics(CancellationToken ct)
    {
        try
        {
            var systemMetrics = _systemMetrics.GetSystemMetrics();
            var metrics = _metricsCollector.GetEndpointMetrics();

            if (_hubContext != null && systemMetrics != null && metrics != null)
            {
                await _hubContext.Clients.All.SendAsync("MetricsUpdated", new
                {
                    System = systemMetrics,
                    Endpoints = metrics
                }, ct);
            }
            else
            {
                _logger.LogWarning("One or more dependencies are null in MetricsBackgroundService");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error in CollectAndBroadcastMetrics");
        }
    }
}