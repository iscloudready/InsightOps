using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace FrontendService.Services
{
    public class CustomHealthCheck : IHealthCheck
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<CustomHealthCheck> _logger;

        public CustomHealthCheck(IConfiguration configuration, ILogger<CustomHealthCheck> logger)
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

                _logger.LogInformation("Service URLs: {@ServiceUrls}", serviceUrls);

                return Task.FromResult(HealthCheckResult.Healthy("Service URLs configured",
                    new Dictionary<string, object> { { "urls", serviceUrls } }));
            }
            catch (Exception ex)
            {
                return Task.FromResult(HealthCheckResult.Unhealthy("Error checking service URLs", ex));
            }
        }
    }
}
