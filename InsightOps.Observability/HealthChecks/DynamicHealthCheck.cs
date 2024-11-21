namespace InsightOps.Observability.HealthChecks
{
    using Microsoft.Extensions.Diagnostics.HealthChecks;
    using Microsoft.Extensions.Logging;
    using System.Net.Http;

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
            // Extract services and endpoints from tags
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

                    // Update overall health status
                    isHealthy &= healthy;
                }
                catch (Exception ex)
                {
                    // Log the error and mark the service as unhealthy
                    _logger.LogError(ex, "Health check failed for {Service}", service);
                    results[service] = new { Status = "Unhealthy", Error = ex.Message };
                    isHealthy = false;
                }
            }

            // Return the health check result with additional data
            return isHealthy
                ? HealthCheckResult.Healthy("All services are healthy", results)
                : HealthCheckResult.Unhealthy("Some services are unhealthy", null, results);
        }
    }
}
