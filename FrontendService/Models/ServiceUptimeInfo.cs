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
}
