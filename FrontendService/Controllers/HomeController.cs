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
using FrontendService.Services.Monitoring;

public class HomeController : Controller
{
    private readonly IHttpClientFactory _clientFactory;
    private readonly ILogger<HomeController> _logger;
    private readonly IConfiguration _configuration;
    private readonly SystemMetricsCollector _metricsCollector;

    public HomeController(
        IHttpClientFactory clientFactory,
        ILogger<HomeController> logger,
        IConfiguration configuration,
        SystemMetricsCollector metricsCollector)
    {
        _clientFactory = clientFactory;
        _logger = logger;
        _configuration = configuration;
        _metricsCollector = metricsCollector;
    }

    [HttpGet]
    public async Task<IActionResult> GetDashboardData()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var baseUrl = _configuration["ServiceUrls:ApiGateway"] ?? "http://localhost:5011";
            client.BaseAddress = new Uri(baseUrl);

            // Get real system metrics
            var systemMetrics = _metricsCollector.GetSystemMetrics();
            var orders = new List<OrderDto>();
            var inventory = new List<InventoryItemDto>();
            var apiHealthy = true;

            try
            {
                // Start timing the API requests
                var stopwatch = Stopwatch.StartNew();

                // Make multiple requests in parallel
                var tasks = new[]
                {
                client.GetAsync("/api/gateway/orders"),
                client.GetAsync("/api/gateway/inventory")
            };

                var results = await Task.WhenAll(tasks);
                stopwatch.Stop();

                // Update response time with actual value
                var actualResponseTime = stopwatch.ElapsedMilliseconds;

                if (results[0].IsSuccessStatusCode)
                {
                    orders = await results[0].Content.ReadFromJsonAsync<List<OrderDto>>() ?? new List<OrderDto>();
                }
                else
                {
                    apiHealthy = false;
                    _logger.LogWarning("Orders API returned status code: {StatusCode}", results[0].StatusCode);
                }

                if (results[1].IsSuccessStatusCode)
                {
                    inventory = await results[1].Content.ReadFromJsonAsync<List<InventoryItemDto>>() ?? new List<InventoryItemDto>();
                }
                else
                {
                    apiHealthy = false;
                    _logger.LogWarning("Inventory API returned status code: {StatusCode}", results[1].StatusCode);
                }

                _logger.LogInformation("Retrieved {OrderCount} orders and {InventoryCount} inventory items in {ResponseTime}ms",
                    orders.Count, inventory.Count, actualResponseTime);

                // Record metrics
                _metricsCollector.RecordMetric("api_response_time", actualResponseTime);
                _metricsCollector.RecordMetric("active_orders", orders.Count);
                _metricsCollector.RecordMetric("inventory_items", inventory.Count);
            }
            catch (Exception ex)
            {
                apiHealthy = false;
                _logger.LogWarning(ex, "Failed to fetch data from API, using empty collections");
            }

            // Calculate trends based on historical metrics if available
            var orderTrends = await GetOrderTrends(orders);
            var inventoryTrends = await GetInventoryTrends(inventory);

            var data = new
            {
                // Order metrics
                activeOrders = orders.Count(o => o.Status != "Completed"),
                pendingOrders = orders.Count(o => o.Status == "Pending"),
                completedOrders = orders.Count(o => o.Status == "Completed"),
                totalOrderValue = orders.Sum(o => o.TotalPrice),

                // Inventory metrics
                inventoryCount = inventory.Count,
                lowStockItems = inventory.Count(i => i.Quantity <= 10),
                totalInventoryValue = inventory.Sum(i => i.Price * i.Quantity),
                outOfStockItems = inventory.Count(i => i.Quantity == 0),

                // System health and performance
                systemHealth = apiHealthy ? "Healthy" : "Degraded",
                responseTime = $"{_metricsCollector.GetAverageResponseTime():F0}ms",
                cpuUsage = systemMetrics.CpuUsage,
                memoryUsage = systemMetrics.MemoryUsage,
                storageUsage = systemMetrics.StorageUsage,
                requestRate = _metricsCollector.GetRequestRate(),
                errorRate = apiHealthy ? 0 : 100,

                // Trend data
                orderTrends = orderTrends,
                inventoryTrends = inventoryTrends,

                // Last update time
                lastUpdated = DateTime.UtcNow
            };

            return Json(data);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching dashboard data");
            return StatusCode(500, new { error = "Error fetching dashboard data", details = ex.Message });
        }
    }

    private async Task<List<OrderTrendData>> GetOrderTrends(List<OrderDto> currentOrders)
    {
        var trends = new List<OrderTrendData>();
        var now = DateTime.UtcNow;

        // Group current orders by hour
        var hourlyOrders = currentOrders
            .Where(o => o.OrderDate >= now.AddHours(-24))
            .GroupBy(o => o.OrderDate.Hour)
            .ToDictionary(g => g.Key, g => g.Count());

        // Create 24-hour trend data
        for (int i = 24; i >= 0; i--)
        {
            var hour = now.AddHours(-i);
            trends.Add(new OrderTrendData
            {
                Time = hour,
                Count = hourlyOrders.GetValueOrDefault(hour.Hour, 0)
            });
        }

        return trends;
    }

    private async Task<List<InventoryTrendData>> GetInventoryTrends(List<InventoryItemDto> currentInventory)
    {
        // Get top 5 items by value
        return currentInventory
            .OrderByDescending(i => i.Price * i.Quantity)
            .Take(5)
            .Select(i => new InventoryTrendData
            {
                Item = i.Name,
                Quantity = i.Quantity
            })
            .ToList();
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