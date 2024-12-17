using FrontendService.Models.DTOs;
using FrontendService.Services;
using Microsoft.AspNetCore.Mvc;

[Route("[controller]")]
public class InventoryController : Controller
{
    private readonly IInventoryService _inventoryService;
    private readonly ILogger<InventoryController> _logger;
    private readonly IWebHostEnvironment _environment;

    public InventoryController(
        IInventoryService inventoryService,
        ILogger<InventoryController> logger,
        IWebHostEnvironment environment)
    {
        _inventoryService = inventoryService;
        _logger = logger;
        _environment = environment;
    }

    [HttpGet]
    [Route("")]
    public async Task<IActionResult> Index()
    {
        try
        {
            _logger.LogInformation("Loading inventory page");
            _logger.LogInformation("Using service URL: {ServiceUrl}",
                _inventoryService.GetServiceUrl());

            var inventory = await _inventoryService.GetAllItemsAsync();
            _logger.LogInformation("Retrieved {Count} inventory items",
                inventory?.Count() ?? 0);
            return View(inventory);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading inventory page");
            if (_environment.IsDevelopment())
            {
                ViewBag.ErrorDetails = ex.ToString();
            }
            TempData["Error"] = "Failed to load inventory. Please try again.";
            return View("Error");
        }
    }

    [HttpPost]
    [Route("add")]
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
    [Route("add-item")]
    public async Task<IActionResult> AddItem([FromForm] InventoryItemDto model)
    {
        try
        {
            if (!ModelState.IsValid)
            {
                TempData["Error"] = "Please fill in all required fields.";
                return RedirectToAction(nameof(Index));
            }

            model.LastRestocked = DateTime.UtcNow;
            var result = await _inventoryService.CreateItemAsync(model);
            TempData["Success"] = "Item added successfully!";
            return RedirectToAction(nameof(Index));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding inventory item");
            TempData["Error"] = "An error occurred while adding the item.";
            return RedirectToAction(nameof(Index));
        }
    }

    [HttpPost]
    [Route("update-stock")]
    public async Task<IActionResult> UpdateStock(int id, int quantity)
    {
        try
        {
            await _inventoryService.UpdateStockAsync(id, quantity);
            return Json(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating stock");
            return Json(new { success = false, message = ex.Message });
        }
    }

    [HttpGet]
    [Route("lowstock")]
    public async Task<IActionResult> GetLowStock()
    {
        try
        {
            var items = await _inventoryService.GetLowStockItemsAsync();
            return Json(items);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting low stock items");
            return Json(new { success = false, message = ex.Message });
        }
    }
}