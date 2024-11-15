// InventoryService/Controllers/InventoryController.cs
using Microsoft.AspNetCore.Mvc;
using InventoryService.Models;
using InventoryService.Services;
using InventoryService.Interfaces;

namespace InventoryService.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class InventoryController : ControllerBase
    {
        private readonly IInventoryService _inventoryService;
        private readonly IInventoryRepository _repository;
        private readonly ILogger<InventoryController> _logger;

        public InventoryController(
            IInventoryService inventoryService,
            IInventoryRepository repository,
            ILogger<InventoryController> logger)
        {
            _inventoryService = inventoryService;
            _repository = repository;
            _logger = logger;
        }

        [HttpGet]
        public async Task<IActionResult> GetAllItems()
        {
            try
            {
                var items = await _repository.GetAllItemsAsync();
                return Ok(items);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving all inventory items");
                return StatusCode(500, "An error occurred while retrieving inventory items");
            }
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetItemById(int id)
        {
            try
            {
                var item = await _repository.GetItemByIdAsync(id);
                if (item == null)
                    return NotFound();
                return Ok(item);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving inventory item {ItemId}", id);
                return StatusCode(500, "An error occurred while retrieving the inventory item");
            }
        }

        [HttpPost]
        public async Task<IActionResult> CreateItem([FromBody] InventoryItem item)
        {
            try
            {
                var createdItem = await _repository.CreateItemAsync(item);
                return CreatedAtAction(nameof(GetItemById), new { id = createdItem.Id }, createdItem);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating inventory item");
                return StatusCode(500, "An error occurred while creating the inventory item");
            }
        }

        [HttpGet("lowstock")]
        public async Task<IActionResult> GetLowStockAlerts()
        {
            try
            {
                var alerts = await _inventoryService.GetLowStockAlertsAsync();
                return Ok(alerts);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving low stock alerts");
                return StatusCode(500, "An error occurred while retrieving low stock alerts");
            }
        }

        [HttpPut("{id}/stock")]
        public async Task<IActionResult> UpdateStock(int id, [FromBody] int quantity)
        {
            try
            {
                var success = await _repository.UpdateStockAsync(id, quantity);
                if (!success)
                    return NotFound();
                return Ok("Stock updated successfully");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating stock for item {ItemId}", id);
                return StatusCode(500, "An error occurred while updating the stock");
            }
        }
    }
}