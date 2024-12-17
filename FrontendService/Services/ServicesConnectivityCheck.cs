using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace FrontendService.Services
{
    public class ServicesConnectivityCheck : IHealthCheck
    {
        private readonly IHttpClientFactory _clientFactory;
        private readonly ILogger<ServicesConnectivityCheck> _logger;
        private readonly IConfiguration _configuration;

        public ServicesConnectivityCheck(
            IHttpClientFactory clientFactory,
            ILogger<ServicesConnectivityCheck> logger,
            IConfiguration configuration)
        {
            _clientFactory = clientFactory;
            _logger = logger;
            _configuration = configuration;
        }

        public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
        {
            var serviceChecks = new Dictionary<string, object>();
            bool isHealthy = true;

            try
            {
                var services = new[]
                {
                ("ApiGateway", _configuration["ServiceUrls:ApiGateway"]),
                ("OrderService", _configuration["ServiceUrls:OrderService"]),
                ("InventoryService", _configuration["ServiceUrls:InventoryService"])
            };

                using var client = _clientFactory.CreateClient();
                client.Timeout = TimeSpan.FromSeconds(5);

                foreach (var (name, baseUrl) in services)
                {
                    try
                    {
                        var response = await client.GetAsync($"{baseUrl}/health", cancellationToken);
                        var status = new
                        {
                            StatusCode = response.StatusCode,
                            IsHealthy = response.IsSuccessStatusCode
                        };

                        serviceChecks.Add(name, status);
                        isHealthy &= response.IsSuccessStatusCode;

                        _logger.LogInformation("{Service} health check: {Status}", name, status);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Error checking {Service} health", name);
                        serviceChecks.Add(name, new { Error = ex.Message });
                        isHealthy = false;
                    }
                }

                return isHealthy
                    ? HealthCheckResult.Healthy("All services are healthy", serviceChecks)
                    : HealthCheckResult.Unhealthy("One or more services are unhealthy", null, serviceChecks);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error performing services connectivity check");
                return HealthCheckResult.Unhealthy("Error checking services connectivity", ex);
            }
        }
    }
}
