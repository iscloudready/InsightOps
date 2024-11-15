// InventoryService/Services/IInventoryService.cs
using InventoryService.Models;

namespace InventoryService.Services
{
    public interface IInventoryService
    {
        Task<bool> CheckAvailabilityAsync(string itemName, int quantity);
        Task<bool> ReserveStockAsync(string itemName, int quantity);
        Task<IEnumerable<LowStockAlert>> GetLowStockAlertsAsync();
    }
}