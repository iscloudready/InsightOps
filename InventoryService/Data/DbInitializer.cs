using InventoryService.Models;
using Microsoft.EntityFrameworkCore;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace InventoryService.Data
{
    public static class DbInitializer
    {
        public static async Task InitializeAsync(InventoryDbContext context)
        {
            try
            {
                // Apply migrations to ensure the schema is up-to-date
                await context.Database.MigrateAsync();
                Console.WriteLine("Database migrations applied successfully.");

                // Seed data only if the InventoryItems table is empty
                if (!context.InventoryItems.Any())
                {
                    Console.WriteLine("Seeding data into InventoryItems table...");

                    var items = new List<InventoryItem>
                    {
                        new InventoryItem
                        {
                            Name = "Sample Item 1",
                            Quantity = 100,
                            Price = 9.99m,
                            MinimumQuantity = 20,
                            LastRestocked = DateTime.UtcNow
                        },
                        new InventoryItem
                        {
                            Name = "Sample Item 2",
                            Quantity = 50,
                            Price = 19.99m,
                            MinimumQuantity = 10,
                            LastRestocked = DateTime.UtcNow
                        },
                        new InventoryItem
                        {
                            Name = "Sample Item 3",
                            Quantity = 75,
                            Price = 14.99m,
                            MinimumQuantity = 15,
                            LastRestocked = DateTime.UtcNow
                        }
                    };

                    await context.InventoryItems.AddRangeAsync(items);
                    await context.SaveChangesAsync();

                    Console.WriteLine("Database seeding completed.");
                }
                else
                {
                    Console.WriteLine("InventoryItems table already contains data, skipping seeding.");
                }
            }
            catch (DbUpdateException dbEx)
            {
                Console.WriteLine($"Database update error: {dbEx.Message}");
                // Log and handle errors related to data updates
                throw;
            }
            catch (InvalidOperationException invEx)
            {
                Console.WriteLine($"Invalid operation: {invEx.Message}");
                // Log and rethrow exceptions related to invalid EF operations
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
