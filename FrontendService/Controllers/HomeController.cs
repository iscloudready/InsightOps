using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using FrontendService.Models;
using System.Text.Json;
using Frontend.Models;

namespace FrontendService.Controllers;

public class HomeController : Controller
{
    private readonly IHttpClientFactory _clientFactory;
    private readonly ILogger<HomeController> _logger;

    public HomeController(IHttpClientFactory clientFactory, ILogger<HomeController> logger)
    {
        _clientFactory = clientFactory;
        _logger = logger;
    }

    [HttpGet]
    public async Task<IActionResult> GetDashboardData()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var dashboardData = new
            {
                ActiveOrders = 0,
                InventoryCount = 0,
                SystemHealth = "Healthy",
                ResponseTime = "0ms"
            };

            // Fetch Orders
            var ordersResponse = await client.GetAsync("/api/gateway/orders");
            var inventoryResponse = await client.GetAsync("/api/gateway/inventory");

            if (ordersResponse.IsSuccessStatusCode && inventoryResponse.IsSuccessStatusCode)
            {
                var orders = await ordersResponse.Content.ReadFromJsonAsync<List<OrderDto>>();
                var inventory = await inventoryResponse.Content.ReadFromJsonAsync<List<InventoryItemDto>>();

                dashboardData = new
                {
                    ActiveOrders = orders?.Count ?? 0,
                    InventoryCount = inventory?.Count ?? 0,
                    SystemHealth = "Healthy",
                    ResponseTime = $"{ordersResponse.Headers.Date?.Millisecond ?? 0}ms"
                };
            }

            return Json(dashboardData);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching dashboard data");
            return StatusCode(500, "Error fetching dashboard data");
        }
    }

    [HttpGet]
    public async Task<IActionResult> GetServiceStatus()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var services = new[]
            {
                    new { name = "Order Service", endpoint = "/api/gateway/orders/health" },
                    new { name = "Inventory Service", endpoint = "/api/gateway/inventory/health" },
                    new { name = "Frontend Service", endpoint = "/health" }
                };

            var statuses = new List<ServiceStatus>();

            foreach (var service in services)
            {
                try
                {
                    var response = await client.GetAsync(service.endpoint);
                    statuses.Add(new ServiceStatus
                    {
                        Name = service.name,
                        Status = response.IsSuccessStatusCode ? "Healthy" : "Unhealthy",
                        LastUpdated = DateTime.UtcNow
                    });
                }
                catch
                {
                    statuses.Add(new ServiceStatus
                    {
                        Name = service.name,
                        Status = "Unhealthy",
                        LastUpdated = DateTime.UtcNow
                    });
                }
            }

            return Json(statuses);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching service status");
            return StatusCode(500, "Error fetching service status");
        }
    }

    public async Task<IActionResult> Index()
    {
        var dashboardData = new DashboardViewModel();

        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");

            // Fetch Orders
            var orderResponse = await client.GetAsync("/api/gateway/orders");
            if (orderResponse.IsSuccessStatusCode)
            {
                var orderContent = await orderResponse.Content.ReadAsStringAsync();
                dashboardData.Orders = JsonSerializer.Deserialize<List<OrderDto>>(orderContent,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }

            // Fetch Inventory
            var inventoryResponse = await client.GetAsync("/api/gateway/inventory");
            if (inventoryResponse.IsSuccessStatusCode)
            {
                var inventoryContent = await inventoryResponse.Content.ReadAsStringAsync();
                dashboardData.InventoryItems = JsonSerializer.Deserialize<List<InventoryItemDto>>(inventoryContent,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }

            // Calculate dashboard metrics
            dashboardData.CalculateMetrics();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching dashboard data");
            // Don't throw - we'll show what we can with null checks in the view
        }

        return View(dashboardData);
    }

    [HttpPost]
    public async Task<IActionResult> CreateOrder(CreateOrderViewModel model)
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var response = await client.PostAsJsonAsync("/api/gateway/orders", model);

            if (response.IsSuccessStatusCode)
            {
                TempData["Success"] = "Order created successfully!";
            }
            else
            {
                TempData["Error"] = "Failed to create order. Please try again.";
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating order");
            TempData["Error"] = "An error occurred while creating the order.";
        }

        return RedirectToAction(nameof(Index));
    }

    public async Task<IActionResult> Inventory()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var response = await client.GetAsync("/api/gateway/inventory");

            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                var inventory = JsonSerializer.Deserialize<List<InventoryItemDto>>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                return View(inventory);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching inventory");
            TempData["Error"] = "Failed to load inventory data.";
        }

        return View(new List<InventoryItemDto>());
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
    }


    public IActionResult Privacy()
    {
        return View();
    }
}
