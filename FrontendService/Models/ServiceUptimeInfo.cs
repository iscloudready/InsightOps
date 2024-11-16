namespace FrontendService.Models
{
    public record ServiceUptimeInfo
    {
        public string UptimeDisplay { get; init; }
        public double UptimePercentage { get; init; }
    }

    public record OrderTrendData
    {
        public DateTime Time { get; init; }
        public int Count { get; init; }
    }

    public record InventoryTrendData
    {
        public string Item { get; init; }
        public int Quantity { get; init; }
    }

    public class ServiceMetrics
    {
        public double CpuUsage { get; set; }
        public double MemoryUsage { get; set; }
        public double RequestRate { get; set; }
        public double ErrorRate { get; set; }
        public TimeSpan Uptime { get; set; }
    }

    public class ServiceHealth
    {
        public bool IsHealthy { get; set; }
        public string Status { get; set; }
        public string Details { get; set; }
        public DateTime LastChecked { get; set; }
    }

    public class DashboardData
    {
        public int ActiveOrders { get; set; }
        public int PendingOrders { get; set; }
        public int CompletedOrders { get; set; }
        public decimal TotalOrderValue { get; set; }
        public int InventoryCount { get; set; }
        public int LowStockItems { get; set; }
        public decimal TotalInventoryValue { get; set; }
        public int OutOfStockItems { get; set; }
        public string SystemHealth { get; set; }
        public string ResponseTime { get; set; }
        public double CpuUsage { get; set; }
        public double MemoryUsage { get; set; }
        public double StorageUsage { get; set; }
        public double RequestRate { get; set; }
        public double ErrorRate { get; set; }
        public List<OrderTrendData> OrderTrends { get; set; } = new();
        public List<InventoryTrendData> InventoryTrends { get; set; } = new();
    }
}
