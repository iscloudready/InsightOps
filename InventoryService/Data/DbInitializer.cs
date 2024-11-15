// InventoryService/Data/DbInitializer.cs
using InventoryService.Models;
using Microsoft.EntityFrameworkCore;

namespace InventoryService.Data
{
    public static class DbInitializer
    {
        public static async Task InitializeAsync(InventoryDbContext context)
        {
            await context.Database.MigrateAsync();

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
            }
        }
    }
}