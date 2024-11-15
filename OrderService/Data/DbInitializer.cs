// OrderService/Data/DbInitializer.cs
using Microsoft.EntityFrameworkCore;
using OrderService.Models;

namespace OrderService.Data
{
    public static class DbInitializer
    {
        public static async Task InitializeAsync(OrderDbContext context)
        {
            await context.Database.MigrateAsync();

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
            }
        }
    }
}