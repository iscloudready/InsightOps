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
    public async Task<IActionResult> CreateOrder(CreateOrderDto model)
    {
        try
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            var response = await _orderService.CreateOrderAsync(model);

            if (response.Success)
            {
                TempData["Success"] = "Order created successfully";
                return RedirectToAction(nameof(Index));
            }

            TempData["Error"] = response.Message ?? "Failed to create order";
            return RedirectToAction(nameof(Index));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating order");
            TempData["Error"] = "An error occurred while creating the order";
            return RedirectToAction(nameof(Index));
        }
    }
}