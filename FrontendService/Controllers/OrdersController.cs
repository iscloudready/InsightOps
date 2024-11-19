using FrontendService.Models.Requests;
using FrontendService.Services;
using Microsoft.AspNetCore.Mvc;

public class OrdersController : Controller
{
    private readonly IOrderService _orderService;
    private readonly IInventoryService _inventoryService;
    private readonly ILogger<OrdersController> _logger;

    public OrdersController(
        IOrderService orderService,
        IInventoryService inventoryService,
        ILogger<OrdersController> logger)
    {
        _orderService = orderService;
        _inventoryService = inventoryService;
        _logger = logger;
    }

    [HttpGet]
    public async Task<IActionResult> Index()
    {
        try
        {
            _logger.LogInformation("Loading orders page");
            var orders = await _orderService.GetAllOrdersAsync();
            ViewBag.InventoryItems = await _inventoryService.GetAllItemsAsync();
            return View(orders);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading orders page");
            TempData["Error"] = "Failed to load orders. Please try again.";
            return View("Error");
        }
    }

    [HttpPost]
    public async Task<IActionResult> CreateOrder([FromForm] CreateOrderDto model)
    {
        try
        {
            if (!ModelState.IsValid)
            {
                TempData["Error"] = "Please fill in all required fields.";
                return RedirectToAction(nameof(Index));
            }

            var result = await _orderService.CreateOrderAsync(model);
            if (result.Success)
            {
                TempData["Success"] = "Order created successfully!";
            }
            else
            {
                TempData["Error"] = result.Message ?? "Failed to create order.";
            }
            return RedirectToAction(nameof(Index));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating order");
            TempData["Error"] = "An error occurred while creating the order.";
            return RedirectToAction(nameof(Index));
        }
    }

    [HttpPost]
    public async Task<IActionResult> UpdateStatus(int id, string status)
    {
        try
        {
            var result = await _orderService.UpdateOrderStatusAsync(id, status);
            return Json(new { success = result });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating order status");
            return Json(new { success = false, message = ex.Message });
        }
    }

    [HttpGet]
    public async Task<IActionResult> GetDetails(int id)
    {
        try
        {
            var order = await _orderService.GetOrderByIdAsync(id);
            if (order == null)
                return NotFound();
            return Json(order);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting order details");
            return Json(new { success = false, message = ex.Message });
        }
    }

    //[HttpGet]
    //public async Task<IActionResult> GetMetrics()
    //{
    //    try
    //    {
    //        var metrics = new
    //        {
    //            totalOrders = await _orderService.GetTotalOrderCount(),
    //            pendingOrders = await _orderService.GetOrderCountByStatus("Pending"),
    //            completedOrders = await _orderService.GetOrderCountByStatus("Completed"),
    //            totalValue = await _orderService.GetTotalOrderValue()
    //        };
    //        return Json(metrics);
    //    }
    //    catch (Exception ex)
    //    {
    //        _logger.LogError(ex, "Error getting order metrics");
    //        return Json(new { success = false, message = ex.Message });
    //    }
    //}

    //[HttpGet]
    //public async Task<IActionResult> GetTrends()
    //{
    //    try
    //    {
    //        var trends = await _orderService.GetOrderTrends();
    //        return Json(trends);
    //    }
    //    catch (Exception ex)
    //    {
    //        _logger.LogError(ex, "Error getting order trends");
    //        return Json(new { success = false, message = ex.Message });
    //    }
    //}
}