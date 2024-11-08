using Microsoft.AspNetCore.Mvc;
using InventoryService.Models;
using InventoryService.Repositories;

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
        public IActionResult GetAllItems()
        {
            return Ok(_repository.GetAllItems());
        }

        [HttpGet("{id}")]
        public IActionResult GetItemById(int id)
        {
            var item = _repository.GetItemById(id);
            if (item == null) return NotFound();
            return Ok(item);
        }

        [HttpPost]
        public IActionResult CreateItem([FromBody] InventoryItem item)
        {
            item.Id = _repository.GetAllItems().Count() + 1;
            _repository.AddItem(item);
            return CreatedAtAction(nameof(GetItemById), new { id = item.Id }, item);
        }
    }
}
