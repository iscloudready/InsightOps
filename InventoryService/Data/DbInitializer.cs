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
                // Ensure the database is created only if it doesn't already exist
                if (!await context.Database.EnsureCreatedAsync())
                {
                    Console.WriteLine("Database already exists, skipping initialization.");
                    return;
                }

                // Run migrations to ensure the schema is up-to-date
                await context.Database.MigrateAsync();

                // Seed data only if the InventoryItems table is empty
                if (!context.InventoryItems.Any())
                {
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

                    context.InventoryItems.AddRange(items);
                    await context.SaveChangesAsync();
                    Console.WriteLine("Database seeding completed.");
                }
                else
                {
                    Console.WriteLine("InventoryItems table already contains data, skipping seeding.");
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
