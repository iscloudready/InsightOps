// InventoryService/Repositories/InventoryRepository.cs
using Microsoft.EntityFrameworkCore;
using InventoryService.Models;
using InventoryService.Interfaces;
using InventoryService.Data;

namespace InventoryService.Repositories
{
    public class InventoryRepository : IInventoryRepository
    {
        private readonly InventoryDbContext _context;
        private readonly ILogger<InventoryRepository> _logger;

        public InventoryRepository(InventoryDbContext context, ILogger<InventoryRepository> logger)
        {
            _context = context ?? throw new ArgumentNullException(nameof(context));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task<IEnumerable<InventoryItem>> GetAllItemsAsync()
        {
            try
            {
                return await _context.InventoryItems
                    .OrderBy(i => i.Name)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving all inventory items");
                throw;
            }
        }

        public async Task<InventoryItem?> GetItemByIdAsync(int id)
        {
            try
            {
                return await _context.InventoryItems
                    .FirstOrDefaultAsync(i => i.Id == id);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving inventory item with ID: {ItemId}", id);
                throw;
            }
        }

        public async Task<InventoryItem?> GetItemByNameAsync(string name)
        {
            if (string.IsNullOrWhiteSpace(name))
                throw new ArgumentNullException(nameof(name));

            try
            {
                return await _context.InventoryItems
                    .FirstOrDefaultAsync(i => i.Name.ToLower() == name.ToLower());
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving inventory item with name: {ItemName}", name);
                throw;
            }
        }

        public async Task<InventoryItem> CreateItemAsync(InventoryItem item)
        {
            if (item == null)
                throw new ArgumentNullException(nameof(item));

            try
            {
                // Check for duplicate names
                if (await ItemExistsByNameAsync(item.Name))
                {
                    throw new InvalidOperationException($"An item with name {item.Name} already exists");
                }

                item.LastRestocked = DateTime.UtcNow;
                _context.InventoryItems.Add(item);
                await _context.SaveChangesAsync();

                _logger.LogInformation("Created new inventory item with ID: {ItemId}", item.Id);
                return item;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while creating new inventory item");
                throw;
            }
        }

        public async Task<InventoryItem> UpdateItemAsync(InventoryItem item)
        {
            if (item == null)
                throw new ArgumentNullException(nameof(item));

            try
            {
                var existingItem = await _context.InventoryItems.FindAsync(item.Id);
                if (existingItem == null)
                    throw new KeyNotFoundException($"Inventory item with ID {item.Id} not found");

                // Check if name is being changed and if new name already exists
                if (existingItem.Name != item.Name && await ItemExistsByNameAsync(item.Name))
                {
                    throw new InvalidOperationException($"An item with name {item.Name} already exists");
                }

                // Update properties
                existingItem.Name = item.Name;
                existingItem.Price = item.Price;
                existingItem.Quantity = item.Quantity;
                existingItem.MinimumQuantity = item.MinimumQuantity;
                existingItem.LastRestocked = DateTime.UtcNow;

                await _context.SaveChangesAsync();

                _logger.LogInformation("Updated inventory item with ID: {ItemId}", item.Id);
                return existingItem;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while updating inventory item with ID: {ItemId}", item.Id);
                throw;
            }
        }

        public async Task<bool> DeleteItemAsync(int id)
        {
            try
            {
                var item = await _context.InventoryItems.FindAsync(id);
                if (item == null)
                    return false;

                _context.InventoryItems.Remove(item);
                await _context.SaveChangesAsync();

                _logger.LogInformation("Deleted inventory item with ID: {ItemId}", id);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while deleting inventory item with ID: {ItemId}", id);
                throw;
            }
        }

        public async Task<bool> UpdateStockAsync(int id, int quantity)
        {
            try
            {
                var item = await _context.InventoryItems.FindAsync(id);
                if (item == null)
                    return false;

                if (quantity < 0)
                    throw new ArgumentException("Quantity cannot be negative", nameof(quantity));

                item.Quantity = quantity;
                item.LastRestocked = DateTime.UtcNow;
                await _context.SaveChangesAsync();

                _logger.LogInformation("Updated stock quantity to {Quantity} for item with ID: {ItemId}",
                    quantity, id);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while updating stock for item with ID: {ItemId}", id);
                throw;
            }
        }

        public async Task<IEnumerable<InventoryItem>> GetLowStockItemsAsync()
        {
            try
            {
                return await _context.InventoryItems
                    .Where(i => i.Quantity <= i.MinimumQuantity)
                    .OrderBy(i => i.Quantity)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving low stock items");
                throw;
            }
        }

        public async Task<bool> ItemExistsAsync(int id)
        {
            try
            {
                return await _context.InventoryItems.AnyAsync(i => i.Id == id);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while checking existence of item with ID: {ItemId}", id);
                throw;
            }
        }

        public async Task<bool> ItemExistsByNameAsync(string name)
        {
            try
            {
                return await _context.InventoryItems
                    .AnyAsync(i => i.Name.ToLower() == name.ToLower());
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while checking existence of item with name: {ItemName}", name);
                throw;
            }
        }

        public async Task<IEnumerable<InventoryItem>> GetItemsWithStockBelowAsync(int threshold)
        {
            try
            {
                return await _context.InventoryItems
                    .Where(i => i.Quantity < threshold)
                    .OrderBy(i => i.Quantity)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving items below threshold: {Threshold}", threshold);
                throw;
            }
        }

        public async Task<int> GetTotalUniqueItemsAsync()
        {
            try
            {
                return await _context.InventoryItems.CountAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while counting total unique items");
                throw;
            }
        }

        public async Task<int> GetTotalStockQuantityAsync()
        {
            try
            {
                return await _context.InventoryItems.SumAsync(i => i.Quantity);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while calculating total stock quantity");
                throw;
            }
        }
    }
}