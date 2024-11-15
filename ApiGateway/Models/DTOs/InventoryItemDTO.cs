// ApiGateway/Models/DTOs/InventoryItemDTO.cs
namespace ApiGateway.Models.DTOs
{
    public class InventoryItemDTO
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public decimal Price { get; set; }
        public DateTime LastRestocked { get; set; }
        public int MinimumQuantity { get; set; }
    }
}