using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Logging;

public class DynamicHealthCheck : IHealthCheck
{
    private readonly IHttpClientFactory _clientFactory;
    private readonly ILogger<DynamicHealthCheck> _logger;

    public DynamicHealthCheck(IHttpClientFactory clientFactory, ILogger<DynamicHealthCheck> logger)
    {
        _clientFactory = clientFactory;
        _logger = logger;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var servicesToCheck = context.Registration.Tags
            .Select(tag => tag.Split('|')) // Format: "service|endpoint"
            .Select(parts => (Service: parts[0], Endpoint: parts[1]))
            .ToList();

        var results = new Dictionary<string, object>();
        var isHealthy = true;

        foreach (var (service, endpoint) in servicesToCheck)
        {
            try
            {
                using var client = _clientFactory.CreateClient(service);
                var response = await client.GetAsync(endpoint, cancellationToken);
                var healthy = response.IsSuccessStatusCode;

                results[service] = new
                {
                    Status = healthy ? "Healthy" : "Unhealthy",
                    StatusCode = response.StatusCode
                };

                isHealthy &= healthy;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Health check failed for {Service}", service);
                results[service] = new { Status = "Unhealthy", Error = ex.Message };
                isHealthy = false;
            }
        }

        // Build and return the health check result
        return isHealthy
            ? new HealthCheckResult(HealthStatus.Healthy, "All services are healthy", data: results)
            : new HealthCheckResult(HealthStatus.Unhealthy, "Some services are unhealthy", data: results);
    }
}
