// InventoryService/Models/LowStockAlert.cs
namespace InventoryService.Models
{
    public class LowStockAlert
    {
        public int ItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public int CurrentQuantity { get; set; }
        public int MinimumQuantity { get; set; }
        public decimal Price { get; set; }
        public DateTime LastRestocked { get; set; }
        public int QuantityToReorder => MinimumQuantity * 2 - CurrentQuantity;
        public string AlertLevel
        {
            get
            {
                if (CurrentQuantity == 0) return "Critical";
                if (CurrentQuantity <= MinimumQuantity / 2) return "High";
                if (CurrentQuantity <= MinimumQuantity) return "Medium";
                return "Low";
            }
        }
    }
}