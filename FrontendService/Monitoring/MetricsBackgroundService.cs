using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Options;
using System.Diagnostics;

namespace FrontendService.Monitoring
{
    public class MetricsBackgroundService : BackgroundService
    {
        private readonly RealTimeMetricsCollector _metricsCollector;
        private readonly ILogger<MetricsBackgroundService> _logger;
        private readonly IHubContext<MetricsHub> _hubContext;
        private readonly MonitoringOptions _options;

        public MetricsBackgroundService(
            RealTimeMetricsCollector metricsCollector,
            ILogger<MetricsBackgroundService> logger,
            IHubContext<MetricsHub> hubContext,
            IOptions<MonitoringOptions> options)
        {
            _metricsCollector = metricsCollector;
            _logger = logger;
            _hubContext = hubContext;
            _options = options.Value;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            try
            {
                while (!stoppingToken.IsCancellationRequested)
                {
                    await CollectAndBroadcastMetrics(stoppingToken);
                    await Task.Delay(_options.MetricsInterval, stoppingToken);
                }
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("Metrics collection stopped");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in metrics collection");
            }
        }

        private async Task CollectAndBroadcastMetrics(CancellationToken cancellationToken)
        {
            try
            {
                var metrics = GetCurrentMetrics();
                await _hubContext.Clients.All.SendAsync("MetricsUpdate", metrics, cancellationToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error collecting or broadcasting metrics");
            }
        }

        private object GetCurrentMetrics()
        {
            return new
            {
                Timestamp = DateTime.UtcNow,
                Cpu = GetCpuUsage(),
                Memory = GetMemoryUsage(),
                ActiveRequests = GetActiveRequests(),
                ErrorRate = GetErrorRate()
            };
        }

        private double GetCpuUsage() //  proc.UpTime.TotalMilliseconds
        {
            using var proc = Process.GetCurrentProcess();
            return proc.TotalProcessorTime.TotalMilliseconds /
                   (Environment.ProcessorCount) * 100;
        }

        private double GetMemoryUsage()
        {
            using var proc = Process.GetCurrentProcess();
            return proc.WorkingSet64 / (double)(1024 * 1024); // MB
        }

        private int GetActiveRequests()
        {
            // Implementation depends on your request tracking mechanism
            return 0;
        }

        private double GetErrorRate()
        {
            // Implementation depends on your error tracking mechanism
            return 0;
        }
    }
}
