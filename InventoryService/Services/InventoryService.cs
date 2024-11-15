// InventoryService/Services/InventoryService.cs
using InventoryService.Interfaces;
using InventoryService.Models;

namespace InventoryService.Services
{
    public class InventoryService : IInventoryService
    {
        private readonly IInventoryRepository _inventoryRepository;
        private readonly ILogger<InventoryService> _logger;

        public InventoryService(IInventoryRepository inventoryRepository, ILogger<InventoryService> logger)
        {
            _inventoryRepository = inventoryRepository;
            _logger = logger;
        }

        public async Task<bool> CheckAvailabilityAsync(string itemName, int quantity)
        {
            var item = await _inventoryRepository.GetItemByNameAsync(itemName);
            if (item == null)
                return false;

            return item.Quantity >= quantity;
        }

        public async Task<bool> ReserveStockAsync(string itemName, int quantity)
        {
            try
            {
                var item = await _inventoryRepository.GetItemByNameAsync(itemName);
                if (item == null || item.Quantity < quantity)
                    return false;

                var newQuantity = item.Quantity - quantity;
                return await _inventoryRepository.UpdateStockAsync(item.Id, newQuantity);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reserving stock for item {ItemName}", itemName);
                return false;
            }
        }

        public async Task<IEnumerable<LowStockAlert>> GetLowStockAlertsAsync()
        {
            var lowStockItems = await _inventoryRepository.GetLowStockItemsAsync();
            return lowStockItems.Select(item => new LowStockAlert
            {
                ItemId = item.Id,
                ItemName = item.Name,
                CurrentQuantity = item.Quantity,
                MinimumQuantity = item.MinimumQuantity,
                Price = item.Price,
                LastRestocked = item.LastRestocked
            });
        }
    }
}