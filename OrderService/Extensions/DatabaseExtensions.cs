using Microsoft.EntityFrameworkCore;

namespace OrderService.Extensions
{
    // DatabaseExtensions.cs
    public static class DatabaseExtensions
    {
        public static async Task<bool> TryMigrateAsync(this DbContext context, ILogger logger)
        {
            try
            {
                if (await context.Database.GetPendingMigrationsAsync() is var pendingMigrations &&
                    pendingMigrations.Any())
                {
                    logger.LogInformation("Found {Count} pending migrations", pendingMigrations.Count());
                    foreach (var migration in pendingMigrations)
                    {
                        logger.LogInformation("Applying migration: {Migration}", migration);
                        try
                        {
                            await context.Database.MigrateAsync();
                            logger.LogInformation("Successfully applied migration: {Migration}", migration);
                        }
                        catch (Exception ex)
                        {
                            logger.LogError(ex, "Failed to apply migration: {Migration}", migration);
                            throw;
                        }
                    }
                    return true;
                }
                return false;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Migration failed");
                throw;
            }
        }
    }
}
