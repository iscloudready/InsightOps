// Frontend/Models/DashboardViewModel.cs
using FrontendService.Models;

namespace Frontend.Models
{
    public class DashboardViewModel
    {
        public List<OrderDto> Orders { get; set; } = new();
        public List<InventoryItemDto> InventoryItems { get; set; } = new();

        public int TotalOrders => Orders.Count;
        public int TotalInventoryItems => InventoryItems.Count;
        public decimal TotalOrderValue => Orders.Sum(o =>
            o.Quantity * (InventoryItems.FirstOrDefault(i => i.Name == o.ItemName)?.Price ?? 0));

        public int LowStockItems => InventoryItems.Count(i => i.Quantity < 10);

        public Dictionary<string, int> PopularItems => Orders
            .GroupBy(o => o.ItemName)
            .OrderByDescending(g => g.Count())
            .Take(5)
            .ToDictionary(g => g.Key, g => g.Count());

        public void CalculateMetrics()
        {
            // Additional metrics can be calculated here
        }
    }
}
