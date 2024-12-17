using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace FrontendService.Services
{
    public class ServiceConfigHealthCheck : IHealthCheck
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<ServiceConfigHealthCheck> _logger;

        public ServiceConfigHealthCheck(IConfiguration configuration, ILogger<ServiceConfigHealthCheck> logger)
        {
            _configuration = configuration;
            _logger = logger;
        }

        public Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
        {
            try
            {
                var serviceUrls = new Dictionary<string, string>
            {
                { "ApiGateway", _configuration["ServiceUrls:ApiGateway"] },
                { "OrderService", _configuration["ServiceUrls:OrderService"] },
                { "InventoryService", _configuration["ServiceUrls:InventoryService"] }
            };

                foreach (var (service, url) in serviceUrls)
                {
                    if (string.IsNullOrEmpty(url))
                    {
                        _logger.LogError("Service URL not configured for {Service}", service);
                        return Task.FromResult(HealthCheckResult.Unhealthy(
                            $"Service URL not configured: {service}"));
                    }
                }

                _logger.LogInformation("Service URLs configured successfully: {@ServiceUrls}", serviceUrls);
                return Task.FromResult(HealthCheckResult.Healthy("Service URLs configured properly",
                    new Dictionary<string, object> { { "urls", serviceUrls } }));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error checking service configuration");
                return Task.FromResult(HealthCheckResult.Unhealthy("Error checking service configuration", ex));
            }
        }
    }
}
