using Microsoft.EntityFrameworkCore;
using OrderService.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace OrderService.Data
{
    public static class DbInitializer
    {
        public static async Task InitializeAsync(OrderDbContext context)
        {
            try
            {
                // Ensure the database is created only if it doesn't already exist
                if (!await context.Database.EnsureCreatedAsync())
                {
                    Console.WriteLine("Database already exists, skipping initialization.");
                    return;
                }

                // Check if the database schema is up-to-date
                await context.Database.MigrateAsync();

                // Seed data only if the Orders table is empty
                if (!context.Orders.Any())
                {
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

                    context.Orders.AddRange(orders);
                    await context.SaveChangesAsync();
                    Console.WriteLine("Database seeding completed.");
                }
                else
                {
                    Console.WriteLine("Orders table already contains data, skipping seeding.");
                }
            }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "42P07")
            {
                Console.WriteLine($"PostgresException: Relation already exists - {ex.Message}");
                // Log and continue without throwing, as this error may not be critical
            }
            catch (InvalidOperationException ex)
            {
                Console.WriteLine($"InvalidOperationException: {ex.Message}");
                // This exception can occur if there are schema mismatches or EF issues.
                throw; // Re-throw if you need to halt initialization on this error.
            }
            catch (Exception ex)
            {
                Console.WriteLine($"An error occurred during database initialization: {ex.Message}");
                throw; // Rethrow to propagate the error if needed
            }
        }
    }
}
