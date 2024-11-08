using System.Collections.Generic;
using System.Linq;
using InventoryService.Models;

namespace InventoryService.Repositories
{
    public class InventoryRepository
    {
        private readonly List<InventoryItem> _items = new List<InventoryItem>();

        public IEnumerable<InventoryItem> GetAllItems() => _items;

        public InventoryItem GetItemById(int id) => _items.FirstOrDefault(i => i.Id == id);

        public void AddItem(InventoryItem item) => _items.Add(item);
    }
}
