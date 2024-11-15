// OrderService/Models/Responses/OrderStatusResponse.cs
namespace OrderService.Models.Responses
{
    public class OrderStatusResponse
    {
        public int OrderId { get; set; }
        public string Status { get; set; } = string.Empty;
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public DateTime LastUpdated { get; set; }
        public decimal TotalPrice { get; set; }
        public string? Notes { get; set; }
    }
}