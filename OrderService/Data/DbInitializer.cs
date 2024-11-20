// OrderService/Data/DbInitializer.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Npgsql;
using OrderService.Models;

namespace OrderService.Data
{
    public static class DbInitializer
    {
        public static async Task InitializeAsync(
            OrderDbContext context,
            ILogger logger)
        {
            try
            {
                logger.LogInformation("Starting database initialization");

                // Check if we can connect to the database
                if (!await context.Database.CanConnectAsync())
                {
                    logger.LogError("Cannot connect to the database");
                    throw new Exception("Database connection failed");
                }

                // Check for pending migrations
                var pendingMigrations = await context.Database.GetPendingMigrationsAsync();
                if (pendingMigrations.Any())
                {
                    logger.LogInformation("Applying {Count} pending migrations", pendingMigrations.Count());
                    foreach (var migration in pendingMigrations)
                    {
                        logger.LogInformation("Applying migration: {Migration}", migration);
                    }
                    await context.Database.MigrateAsync();
                }

                // Check if data seeding is needed
                if (!await context.Orders.AnyAsync())
                {
                    logger.LogInformation("Seeding initial data");

                    var orders = new List<Order>
                    {
                        new Order
                        {
                            ItemName = "Sample Item 1",
                            Quantity = 5,
                            OrderDate = DateTime.UtcNow.AddDays(-1),
                            TotalPrice = 49.99m,
                            Status = "Completed"
                        },
                        new Order
                        {
                            ItemName = "Sample Item 2",
                            Quantity = 3,
                            OrderDate = DateTime.UtcNow.AddHours(-2),
                            TotalPrice = 29.99m,
                            Status = "Pending"
                        }
                    };

                    try
                    {
                        await context.Orders.AddRangeAsync(orders);
                        await context.SaveChangesAsync();
                        logger.LogInformation("Successfully seeded {Count} orders", orders.Count);
                    }
                    catch (DbUpdateException ex)
                    {
                        logger.LogError(ex, "Error occurred while seeding data");
                        throw new Exception("Failed to seed initial data", ex);
                    }
                }
                else
                {
                    logger.LogInformation("Database already contains data, skipping seeding");
                }

                logger.LogInformation("Database initialization completed successfully");
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "An error occurred during database initialization");

                if (ex is DbUpdateException dbEx)
                {
                    logger.LogError("Database Update Error Details:");
                    if (dbEx.InnerException != null)
                    {
                        logger.LogError("Inner Exception: {Message}", dbEx.InnerException.Message);
                    }
                }
                else if (ex is PostgresException pgEx)
                {
                    logger.LogError("Postgres Error Details:");
                    logger.LogError("  Error Code: {Code}", pgEx.SqlState);
                    logger.LogError("  Error Message: {Message}", pgEx.MessageText);
                    logger.LogError("  Detail: {Detail}", pgEx.Detail);
                }

                // Always throw the exception to prevent the application from starting with an incompletely initialized database
                throw new Exception("Database initialization failed", ex);
            }
        }

        private static async Task EnsureTableExists(OrderDbContext context, string tableName, ILogger logger)
        {
            try
            {
                // Check if table exists
                var exists = await context.Database.ExecuteSqlRawAsync(
                    $"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '{tableName}')");

                if (exists == 0)
                {
                    logger.LogWarning("Table {TableName} does not exist", tableName);
                    // Let migrations handle table creation
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error checking table existence: {TableName}", tableName);
                throw;
            }
        }
    }
}