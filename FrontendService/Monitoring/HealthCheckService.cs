using Microsoft.Extensions.Diagnostics.HealthChecks;
using System.Diagnostics;

namespace FrontendService.Monitoring
{
    public class HealthCheckService : IHealthCheck
    {
        private readonly IHttpClientFactory _clientFactory;
        private readonly ILogger<HealthCheckService> _logger;
        private readonly RealTimeMetricsCollector _metricsCollector;
        private readonly DateTime _startTime;

        public HealthCheckService(
            IHttpClientFactory clientFactory,
            ILogger<HealthCheckService> logger,
            RealTimeMetricsCollector metricsCollector)
        {
            _clientFactory = clientFactory;
            _logger = logger;
            _metricsCollector = metricsCollector;
            _startTime = DateTime.UtcNow;
        }

        public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
        {
            var services = new[]
            {
                ("api-gateway", "/health"),
                ("order-service", "/health"),
                ("inventory-service", "/health")
            };

            var results = new Dictionary<string, object>();
            var isHealthy = true;

            foreach (var (service, endpoint) in services)
            {
                try
                {
                    using var client = _clientFactory.CreateClient(service);
                    var response = await client.GetAsync(endpoint, cancellationToken);
                    var serviceHealthy = response.IsSuccessStatusCode;

                    results[service] = new
                    {
                        Status = serviceHealthy ? "Healthy" : "Unhealthy",
                        StatusCode = response.StatusCode,
                        Uptime = (DateTime.UtcNow - _startTime).ToString()
                    };

                    // Update metrics instead of using UpdateServiceHealth
                    if (serviceHealthy)
                    {
                        _metricsCollector.RecordApiRequest(endpoint, "GET");
                        _metricsCollector.RecordApiResponse(endpoint, 0);
                    }

                    isHealthy &= serviceHealthy;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Health check failed for {Service}", service);
                    results[service] = new { Status = "Unhealthy", Error = ex.Message };
                    isHealthy = false;
                }
            }

            return isHealthy
                ? HealthCheckResult.Healthy("All services are healthy", results)
                : HealthCheckResult.Unhealthy("One or more services are unhealthy", null, results);
        }
    }
}