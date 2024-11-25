using InsightOps.Observability.Metrics;
using InsightOps.Observability.Options;
using InsightOps.Observability.SignalR;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace InsightOps.Observability.BackgroundServices
{
    public class MetricsBackgroundService : BackgroundService
    {
        private readonly ILogger<MetricsBackgroundService> _logger;
        private readonly RealTimeMetricsCollector _metricsCollector;
        private readonly SystemMetricsCollector _systemMetrics;
        private readonly IHubContext<MetricsHub> _hubContext;
        private readonly IOptions<ObservabilityOptions> _options;

        public MetricsBackgroundService(
            ILogger<MetricsBackgroundService> logger,
            RealTimeMetricsCollector metricsCollector,
            SystemMetricsCollector systemMetrics,
            IHubContext<MetricsHub> hubContext,
            IOptions<ObservabilityOptions> options)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _metricsCollector = metricsCollector ?? throw new ArgumentNullException(nameof(metricsCollector));
            _systemMetrics = systemMetrics ?? throw new ArgumentNullException(nameof(systemMetrics));
            _hubContext = hubContext ?? throw new ArgumentNullException(nameof(hubContext));
            _options = options ?? throw new ArgumentNullException(nameof(options));
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    var systemMetrics = _systemMetrics.GetSystemMetrics();
                    var metrics = _metricsCollector.GetEndpointMetrics();

                    await _hubContext.Clients.All.SendAsync("MetricsUpdated", new
                    {
                        System = systemMetrics,
                        Endpoints = metrics
                    }, stoppingToken);

                    await Task.Delay(TimeSpan.FromSeconds(_options.Value.Common.MetricsInterval), stoppingToken);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    _logger.LogError(ex, "Error collecting metrics");
                }
            }
        }
    }
}
