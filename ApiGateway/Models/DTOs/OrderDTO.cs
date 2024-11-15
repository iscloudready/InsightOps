// ApiGateway/Models/DTOs/OrderDTO.cs
namespace ApiGateway.Models.DTOs
{
    public class OrderDTO
    {
        public int Id { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public decimal TotalPrice { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime OrderDate { get; set; }
    }
}