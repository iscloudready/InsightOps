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
                // Apply migrations to ensure the schema is up-to-date
                await context.Database.MigrateAsync();
                Console.WriteLine("Database migrations applied successfully.");

                // Seed data only if the Orders table is empty
                if (!context.Orders.Any())
                {
                    Console.WriteLine("Seeding data into Orders table...");

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

                    await context.Orders.AddRangeAsync(orders);
                    await context.SaveChangesAsync();

                    Console.WriteLine("Database seeding completed.");
                }
                else
                {
                    Console.WriteLine("Orders table already contains data, skipping seeding.");
                }
            }
            catch (DbUpdateException dbEx)
            {
                Console.WriteLine($"Database update error: {dbEx.Message}");
                // Handle database update issues, such as unique constraint violations
                throw;
            }
            catch (InvalidOperationException invEx)
            {
                Console.WriteLine($"Invalid operation: {invEx.Message}");
                // Handle invalid EF operations, such as schema mismatches
                throw;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"An unexpected error occurred: {ex.Message}");
                throw;
            }
        }
    }
}
