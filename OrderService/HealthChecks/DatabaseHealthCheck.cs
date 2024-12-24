using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using OrderService.Data;

namespace OrderService.HealthChecks
{
    public class DatabaseHealthCheck : IHealthCheck
    {
        private readonly OrderDbContext _context;
        private readonly ILogger<DatabaseHealthCheck> _logger;

        public DatabaseHealthCheck(OrderDbContext context, ILogger<DatabaseHealthCheck> logger)
        {
            _context = context;
            _logger = logger;
        }

        public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
        {
            try
            {
                // Verify database connectivity
                if (await _context.Database.CanConnectAsync(cancellationToken))
                {
                    // Check if we can query the Orders table
                    await _context.Orders.CountAsync(cancellationToken);
                    return HealthCheckResult.Healthy("Database is healthy and accessible");
                }

                return HealthCheckResult.Unhealthy("Cannot connect to database");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Database health check failed");
                return HealthCheckResult.Unhealthy("Database health check failed", ex);
            }
        }
    }
}