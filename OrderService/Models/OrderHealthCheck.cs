using Microsoft.Extensions.Diagnostics.HealthChecks;
using OrderService.Data;

public class OrderHealthCheck : IHealthCheck
{
    private readonly OrderDbContext _context;

    public OrderHealthCheck(OrderDbContext context)
    {
        _context = context;
    }

    public Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            await _context.Database.CanConnectAsync();
            return HealthCheckResult.Healthy();
        }
        catch
        {
            return HealthCheckResult.Unhealthy();
        }
    }
}