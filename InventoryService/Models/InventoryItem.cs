// InventoryService/Models/InventoryItem.cs
namespace InventoryService.Models
{
    public class InventoryItem
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public decimal Price { get; set; }
        public DateTime LastRestocked { get; set; }
        public int MinimumQuantity { get; set; } = 10;

        // Business logic methods
        public bool IsLowStock()
        {
            return Quantity <= MinimumQuantity;
        }

        public bool HasSufficientStock(int requestedQuantity)
        {
            return Quantity >= requestedQuantity;
        }

        public void UpdateStock(int newQuantity)
        {
            Quantity = newQuantity;
            LastRestocked = DateTime.UtcNow;
        }
    }
}