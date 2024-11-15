// Frontend/Services/IInventoryService.cs
// Add to both IOrderService.cs and OrderService.cs
using FrontendService.Models.DTOs;
using FrontendService.Models.Requests;
using FrontendService.Models.Responses;

// Add to both IInventoryService.cs and InventoryService.cs
using FrontendService.Models.DTOs;
// FrontendService/Services/IInventoryService.cs

namespace FrontendService.Services
{
    public interface IInventoryService
    {
        Task<IEnumerable<InventoryItemDto>> GetAllItemsAsync();
        Task<InventoryItemDto> GetItemByIdAsync(int id);
        Task<IEnumerable<InventoryItemDto>> GetLowStockItemsAsync();
        Task<InventoryItemDto> UpdateStockAsync(int id, int quantity);
        Task<InventoryItemDto> CreateItemAsync(InventoryItemDto item);
    }
}