// FrontendService/Models/Responses/OrderResponse.cs
namespace FrontendService.Models.Responses
{
    public class OrderResponse
    {
        public int OrderId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public decimal TotalPrice { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime OrderDate { get; set; }
        public bool Success { get; set; }
        public string? Message { get; set; }
    }
}