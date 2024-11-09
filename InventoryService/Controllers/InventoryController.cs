// InventoryController.cs
using Microsoft.AspNetCore.Mvc;
using InventoryService.Models;
using InventoryService.Repositories;
using System.Threading.Tasks;
using System.Linq;

namespace InventoryService.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class InventoryController : ControllerBase
    {
        private readonly InventoryRepository _repository;

        public InventoryController(InventoryRepository repository)
        {
            _repository = repository;
        }

        [HttpGet]
        public async Task<IActionResult> GetAllItems()
        {
            var items = await _repository.GetAllItems();
            return Ok(items);
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetItemById(int id)
        {
            var item = await _repository.GetItemById(id);
            if (item == null) return NotFound();
            return Ok(item);
        }

        [HttpPost]
        public async Task<IActionResult> CreateItem([FromBody] InventoryItem item)
        {
            var createdItem = await _repository.AddItem(item);
            return CreatedAtAction(nameof(GetItemById), new { id = createdItem.Id }, createdItem);
        }
    }
}