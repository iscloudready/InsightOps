// Updated InventoryRepository
using InventoryService.Models;
using Microsoft.EntityFrameworkCore;

namespace InventoryService.Repositories
{
    public class InventoryRepository
    {
        private readonly InventoryDbContext _context;

        public InventoryRepository(InventoryDbContext context)
        {
            _context = context;
        }

        public async Task<IEnumerable<InventoryItem>> GetAllItems()
            => await _context.InventoryItems.ToListAsync();

        public async Task<InventoryItem> GetItemById(int id)
            => await _context.InventoryItems.FindAsync(id);

        public async Task<InventoryItem> AddItem(InventoryItem item)
        {
            _context.InventoryItems.Add(item);
            await _context.SaveChangesAsync();
            return item;
        }
    }
}