// OrderService/Data/DbInitializer.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Npgsql;
using OrderService.Models;

namespace OrderService.Data
{
    public static class DbInitializer
    {
        public static async Task InitializeAsync(OrderDbContext context, ILogger logger)
        {
            try
            {
                // Create schema and set search path
                await context.Database.ExecuteSqlRawAsync("CREATE SCHEMA IF NOT EXISTS orders;");
                await context.Database.ExecuteSqlRawAsync("SET search_path TO orders,public;");

                // Only try to create the migrations history table once
                try
                {
                    await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS orders.__EFMigrationsHistory (
                        MigrationId character varying(150) NOT NULL,
                        ProductVersion character varying(32) NOT NULL,
                        CONSTRAINT PK___EFMigrationsHistory PRIMARY KEY (MigrationId)
                    );");
                }
                catch (PostgresException pgEx) when (pgEx.SqlState == "42P07")
                {
                    logger.LogInformation("Migration history table already exists");
                }

                // Check for pending migrations
                var pendingMigrations = await context.Database.GetPendingMigrationsAsync();
                var pendingMigrationsList = pendingMigrations.ToList();

                if (pendingMigrationsList.Any())
                {
                    logger.LogInformation("Found {Count} pending migrations: {@Migrations}",
                        pendingMigrationsList.Count,
                        pendingMigrationsList);

                    try
                    {
                        await context.Database.MigrateAsync();
                        logger.LogInformation("Successfully applied pending migrations");
                    }
                    catch (PostgresException pgEx) when (pgEx.SqlState == "42P07")
                    {
                        logger.LogInformation("Tables already exist, continuing...");
                    }
                }

                // Check if data needs to be seeded
                if (!await context.Orders.AnyAsync())
                {
                    logger.LogInformation("Initializing seed data...");

                    // Add sample orders
                    var orders = new[]
                    {
                    new Order
                    {
                        ItemName = "Test Item 1",
                        Quantity = 5,
                        TotalPrice = 49.99M,
                        Status = "Pending",
                        OrderDate = DateTime.UtcNow
                    },
                    new Order
                    {
                        ItemName = "Test Item 2",
                        Quantity = 3,
                        TotalPrice = 29.99M,
                        Status = "Pending",
                        OrderDate = DateTime.UtcNow
                    }
                };

                    await context.Orders.AddRangeAsync(orders);
                    await context.SaveChangesAsync();
                    logger.LogInformation("Seed data initialized successfully");
                }
                else
                {
                    logger.LogInformation("Database already contains data");
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "An error occurred during database initialization");
                throw new Exception("Database initialization failed", ex);
            }
        }


        public static async Task _InitializeAsync(
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
