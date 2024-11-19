using FrontendService.Models.DTOs;

namespace FrontendService.Models
{
    public class InventoryViewModel
    {
        public IEnumerable<InventoryItemDto> Items { get; set; }
        public int LowStockCount => Items?.Count(i => i.IsLowStock) ?? 0;
        public int TotalCount => Items?.Count() ?? 0;
    }
}
