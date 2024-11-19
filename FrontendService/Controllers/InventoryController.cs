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

    //[HttpDelete]
    //public async Task<IActionResult> DeleteItem(int id)
    //{
    //    try
    //    {
    //        await _inventoryService.DeleteItemAsync(id);
    //        return Json(new { success = true });
    //    }
    //    catch (Exception ex)
    //    {
    //        _logger.LogError(ex, "Error deleting inventory item");
    //        return Json(new { success = false, message = ex.Message });
    //    }
    //}

    //// Add these methods to InventoryController
    //[HttpGet]
    //public async Task<IActionResult> StockHistory(int id)
    //{
    //    try
    //    {
    //        var history = await _inventoryService.GetStockHistory(id);
    //        return Json(history);
    //    }
    //    catch (Exception ex)
    //    {
    //        _logger.LogError(ex, "Error getting stock history");
    //        return Json(new { success = false, message = ex.Message });
    //    }
    //}

    //[HttpGet]
    //public async Task<IActionResult> GetMetrics()
    //{
    //    try
    //    {
    //        var metrics = new
    //        {
    //            totalItems = await _inventoryService.GetTotalItemCount(),
    //            lowStockCount = (await _inventoryService.GetLowStockItemsAsync()).Count(),
    //            totalValue = await _inventoryService.GetTotalInventoryValue(),
    //            recentRestocks = await _inventoryService.GetRecentRestocks()
    //        };
    //        return Json(metrics);
    //    }
    //    catch (Exception ex)
    //    {
    //        _logger.LogError(ex, "Error getting inventory metrics");
    //        return Json(new { success = false, message = ex.Message });
    //    }
    //}
}