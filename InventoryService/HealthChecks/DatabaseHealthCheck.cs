using Microsoft.Extensions.Diagnostics.HealthChecks;
using InventoryService.Data;

namespace InventoryService.HealthChecks
{
    public class DatabaseHealthCheck : IHealthCheck
    {
        private readonly InventoryDbContext _context;
        private readonly ILogger<DatabaseHealthCheck> _logger;

        public DatabaseHealthCheck(InventoryDbContext context, ILogger<DatabaseHealthCheck> logger)
        {
            _context = context;
            _logger = logger;
        }

        public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
        {
            try
            {
                // Try to connect to database
                if (await _context.Database.CanConnectAsync(cancellationToken))
                {
                    return HealthCheckResult.Healthy("Database is healthy");
                }

                return HealthCheckResult.Unhealthy("Unable to connect to database");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error checking database health");
                return HealthCheckResult.Unhealthy("Database health check failed", ex);
            }
        }
    }
}