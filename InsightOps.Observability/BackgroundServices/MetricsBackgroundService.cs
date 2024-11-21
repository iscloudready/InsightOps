using InsightOps.Observability.Metrics;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace InsightOps.Observability.BackgroundServices
{
    public class MetricsBackgroundService : BackgroundService
    {
        private readonly RealTimeMetricsCollector _metricsCollector;
        private readonly ILogger<MetricsBackgroundService> _logger;

        public MetricsBackgroundService(RealTimeMetricsCollector metricsCollector, ILogger<MetricsBackgroundService> logger)
        {
            _metricsCollector = metricsCollector;
            _logger = logger;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                // Collect metrics and log them periodically
                await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
            }
        }
    }
}
