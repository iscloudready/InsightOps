// FrontendService/Controllers/HomeController.cs
using System;
using System.Diagnostics;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using FrontendService.Models;
using System.Collections.Generic;
using System.Linq;
using FrontendService.Models.DTOs;
using System.Net.Http.Json;

public class HomeController : Controller
{
    private readonly IHttpClientFactory _clientFactory;
    private readonly ILogger<HomeController> _logger;
    private readonly IConfiguration _configuration;

    public HomeController(
        IHttpClientFactory clientFactory,
        ILogger<HomeController> logger,
        IConfiguration configuration)
    {
        _clientFactory = clientFactory;
        _logger = logger;
        _configuration = configuration;
    }

    [HttpGet]
    public async Task<IActionResult> GetDashboardData()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var baseUrl = _configuration["ServiceUrls:ApiGateway"] ?? "http://localhost:5011";
            client.BaseAddress = new Uri(baseUrl);

            // Generate simulated metrics since API might not be available
            var metrics = GenerateSimulatedMetrics();
            var orders = new List<OrderDto>();
            var inventory = new List<InventoryItemDto>();

            try
            {
                // Make multiple requests in parallel
                var tasks = new[]
                {
                client.GetAsync("/api/gateway/orders"),
                client.GetAsync("/api/gateway/inventory")
            };

                var results = await Task.WhenAll(tasks);

                if (results[0].IsSuccessStatusCode)
                    orders = await results[0].Content.ReadFromJsonAsync<List<OrderDto>>() ?? new List<OrderDto>();

                if (results[1].IsSuccessStatusCode)
                    inventory = await results[1].Content.ReadFromJsonAsync<List<InventoryItemDto>>() ?? new List<InventoryItemDto>();

                _logger.LogInformation("Retrieved {OrderCount} orders and {InventoryCount} inventory items",
                    orders.Count, inventory.Count);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to fetch data from API, using empty collections");
            }

            var data = new
            {
                activeOrders = orders.Count,
                pendingOrders = orders.Count(o => o.Status == "Pending"),
                completedOrders = orders.Count(o => o.Status == "Completed"),
                totalOrderValue = orders.Sum(o => o.TotalPrice),

                inventoryCount = inventory.Count,
                lowStockItems = inventory.Count(i => i.Quantity <= 10),
                totalInventoryValue = inventory.Sum(i => i.Price * i.Quantity),
                outOfStockItems = inventory.Count(i => i.Quantity == 0),

                systemHealth = "Healthy", // Will be determined by health checks
                responseTime = $"{metrics.AverageResponseTime}ms",
                cpuUsage = metrics.CpuUsage,
                memoryUsage = metrics.MemoryUsage,
                storageUsage = metrics.StorageUsage,
                requestRate = metrics.RequestRate,
                errorRate = metrics.ErrorRate,

                // Add trend data for charts
                orderTrends = GenerateOrderTrends(),
                inventoryTrends = GenerateInventoryTrends()
            };

            return Json(data);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching dashboard data");
            return StatusCode(500, new { error = "Error fetching dashboard data", details = ex.Message });
        }
    }

    private List<OrderTrendData> GenerateOrderTrends()
    {
        var trends = new List<OrderTrendData>();
        var baseTime = DateTime.UtcNow.AddHours(-24);

        for (int i = 0; i < 24; i++)
        {
            trends.Add(new OrderTrendData
            {
                Time = baseTime.AddHours(i),
                Count = Random.Shared.Next(10, 100)
            });
        }
        return trends;
    }

    private List<InventoryTrendData> GenerateInventoryTrends()
    {
        var items = new[] { "Product A", "Product B", "Product C", "Product D", "Product E" };
        return items.Select(item => new InventoryTrendData
        {
            Item = item,
            Quantity = Random.Shared.Next(0, 100)
        }).ToList();
    }

    [HttpGet]
    public async Task<IActionResult> GetServiceStatus()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var baseUrl = _configuration["ServiceUrls:ApiGateway"] ?? "http://localhost:5011";
            client.BaseAddress = new Uri(baseUrl);

            var services = new[]
            {
            ("Order Service", "/api/gateway/orders/health"),
            ("Inventory Service", "/api/gateway/inventory/health"),
            ("Frontend Service", "/health")
        };

            var statuses = new List<ServiceStatus>();

            foreach (var (name, endpoint) in services)
            {
                try
                {
                    var response = await client.GetAsync(endpoint);
                    var isHealthy = response.IsSuccessStatusCode;
                    var metrics = GenerateServiceMetrics();
                    var resourceUsage = new Dictionary<string, double>
                    {
                        ["CPU"] = Random.Shared.Next(20, 80),
                        ["Memory"] = Random.Shared.Next(30, 70),
                        ["Disk"] = Random.Shared.Next(10, 50)
                    };

                    statuses.Add(new ServiceStatus
                    {
                        Name = name,
                        Status = isHealthy ? "Healthy" : "Unhealthy",
                        LastUpdated = DateTime.UtcNow,
                        Uptime = "99.9%",
                        Metrics = new Dictionary<string, string>
                        {
                            ["Requests"] = $"{metrics.RequestRate}/min",
                            ["ErrorRate"] = $"{metrics.ErrorRate:P2}",
                            ["AvgResponseTime"] = $"{metrics.AverageResponseTime}ms"
                        },
                        RecentErrors = new List<string>(),
                        HealthCheckDetails = isHealthy ? "All checks passed" : "Service degraded",
                        ResourceUsage = resourceUsage
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error checking service {ServiceName}", name);
                    statuses.Add(new ServiceStatus
                    {
                        Name = name,
                        Status = "Unknown",
                        LastUpdated = DateTime.UtcNow,
                        Uptime = "-",
                        RecentErrors = new List<string> { ex.Message },
                        HealthCheckDetails = "Health check failed",
                        ResourceUsage = new Dictionary<string, double>(),
                        Metrics = new Dictionary<string, string>()
                    });
                }
            }

            return Json(statuses);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching service status");
            return StatusCode(500, new { error = "Error fetching service status", details = ex.Message });
        }
    }

    private SimulatedMetrics GenerateSimulatedMetrics()
    {
        return new SimulatedMetrics
        {
            CpuUsage = Random.Shared.Next(20, 80),
            MemoryUsage = Random.Shared.Next(30, 70),
            StorageUsage = Random.Shared.Next(10, 50),
            RequestRate = Random.Shared.Next(100, 1000),
            ErrorRate = Random.Shared.NextDouble() / 100, // 0-1%
            AverageResponseTime = Random.Shared.Next(50, 200)
        };
    }

    private SimulatedMetrics GenerateServiceMetrics()
    {
        return new SimulatedMetrics
        {
            RequestRate = Random.Shared.Next(100, 1000),
            ErrorRate = Random.Shared.NextDouble() / 100,
            AverageResponseTime = Random.Shared.Next(50, 200)
        };
    }

    public IActionResult Index()
    {
        return View();
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
    }
}

public class SimulatedMetrics
{
    public double CpuUsage { get; set; }
    public double MemoryUsage { get; set; }
    public double StorageUsage { get; set; }
    public int RequestRate { get; set; }
    public double ErrorRate { get; set; }
    public int AverageResponseTime { get; set; }
}