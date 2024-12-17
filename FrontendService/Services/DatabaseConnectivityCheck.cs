using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace FrontendService.Services
{
    public class DatabaseConnectivityCheck : IHealthCheck
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<DatabaseConnectivityCheck> _logger;

        public DatabaseConnectivityCheck(IConfiguration configuration, ILogger<DatabaseConnectivityCheck> logger)
        {
            _configuration = configuration;
            _logger = logger;
        }

        public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
        {
            try
            {
                using var httpClient = new HttpClient();
                var dbHealthEndpoint = $"{_configuration["ServiceUrls:ApiGateway"]}/health/database";
                var response = await httpClient.GetAsync(dbHealthEndpoint, cancellationToken);

                if (response.IsSuccessStatusCode)
                {
                    _logger.LogInformation("Database health check passed");
                    return HealthCheckResult.Healthy("Database connection is healthy");
                }

                _logger.LogWarning("Database health check failed with status code: {StatusCode}", response.StatusCode);
                return HealthCheckResult.Degraded("Database health check failed");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error checking database connectivity");
                return HealthCheckResult.Unhealthy("Database connectivity check failed", ex);
            }
        }
    }
}
