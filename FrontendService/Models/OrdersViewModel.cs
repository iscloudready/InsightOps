using FrontendService.Models.DTOs;

namespace FrontendService.Models
{
    public class OrdersViewModel
    {
        public IEnumerable<OrderDto> Orders { get; set; }
        public IEnumerable<InventoryItemDto> AvailableItems { get; set; }
    }
}
