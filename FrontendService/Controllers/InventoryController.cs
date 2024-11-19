using FrontendService.Models.DTOs;
using FrontendService.Services;
using Microsoft.AspNetCore.Mvc;

public class InventoryController : Controller
{
    private readonly IInventoryService _inventoryService;
    private readonly ILogger<InventoryController> _logger;

    public InventoryController(
        IInventoryService inventoryService,
        ILogger<InventoryController> logger)
    {
        _inventoryService = inventoryService;
        _logger = logger;
    }

    [HttpGet]
    public async Task<IActionResult> Index()
    {
        try
        {
            _logger.LogInformation("Loading inventory page");
            var inventory = await _inventoryService.GetAllItemsAsync();
            return View(inventory);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading inventory page");
            TempData["Error"] = "Failed to load inventory. Please try again.";
            return View("Error");
        }
    }

    [HttpPost]
    public async Task<IActionResult> AddInventoryItem([FromForm] InventoryItemDto model)
    {
        try
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            var createdItem = await _inventoryService.CreateItemAsync(model);
            TempData["Success"] = "Item added successfully";
            return RedirectToAction(nameof(Index));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating inventory item");
            TempData["Error"] = "Failed to add item";
            return RedirectToAction(nameof(Index));
        }
    }

    [HttpPost]
    public async Task<IActionResult> UpdateStock(int id, int quantity)
    {
        try
        {
            await _inventoryService.UpdateStockAsync(id, quantity);
            TempData["Success"] = "Stock updated successfully";
            return RedirectToAction(nameof(Index));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating stock for item {ItemId}", id);
            TempData["Error"] = "Failed to update stock";
            return RedirectToAction(nameof(Index));
        }
    }
}