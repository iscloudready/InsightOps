// FrontendService/Models/DTOs/InventoryItemDto.cs
namespace FrontendService.Models.DTOs
{
    public class InventoryItemDto
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public decimal Price { get; set; }
        public DateTime LastRestocked { get; set; }
        public int MinimumQuantity { get; set; }
        public bool IsLowStock => Quantity <= MinimumQuantity;
    }
}