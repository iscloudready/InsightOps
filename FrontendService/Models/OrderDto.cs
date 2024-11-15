// FrontendService/Models/DTOs/OrderDto.cs
namespace FrontendService.Models.DTOs
{
    public class OrderDto
    {
        public int Id { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public decimal TotalPrice { get; set; }
        public string Status { get; set; } = "Pending";
        public DateTime OrderDate { get; set; }
    }
}