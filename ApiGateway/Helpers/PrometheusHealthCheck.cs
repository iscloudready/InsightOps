using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace ApiGateway.Helpers
{
    public class PrometheusHealthCheck : IHealthCheck
    {
        public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
        {
            try
            {
                using var client = new HttpClient() { Timeout = TimeSpan.FromSeconds(5) };
                var result = await client.GetAsync("http://prometheus:9090/-/healthy", cancellationToken);
                return result.IsSuccessStatusCode
                    ? HealthCheckResult.Healthy()
                    : HealthCheckResult.Degraded();
            }
            catch
            {
                return HealthCheckResult.Degraded();
            }
        }
    }
}
