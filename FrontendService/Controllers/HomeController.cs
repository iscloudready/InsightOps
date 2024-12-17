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
using InsightOps.Observability.Metrics;  // Use the observability package metrics
//using FrontendService.Services.Monitoring;
using System.Text.Json;
using Polly.CircuitBreaker;
using FrontendService.Extensions;

public class HomeController : Controller
{
    private readonly IHttpClientFactory _clientFactory;
    private readonly ILogger<HomeController> _logger;
    private readonly IConfiguration _configuration;
    private readonly InsightOps.Observability.Metrics.SystemMetricsCollector _systemMetrics;
    private readonly InsightOps.Observability.Metrics.RealTimeMetricsCollector _realTimeMetrics;

    public HomeController(
        IHttpClientFactory clientFactory,
        ILogger<HomeController> logger,
        IConfiguration configuration,
        SystemMetricsCollector systemMetrics,
        RealTimeMetricsCollector realTimeMetrics)
    {
        _clientFactory = clientFactory;
        _logger = logger;
        _configuration = configuration;
        _systemMetrics = systemMetrics;
        _realTimeMetrics = realTimeMetrics;
    }

    public IActionResult Index()
    {
        return View();
    }

    [HttpGet]
    public async Task<IActionResult> GetDashboardData()
    {
        try
        {
            // Add service URL logging at the start
            _logger.LogInformation("Service URLs Configuration:");
            _logger.LogInformation("API Gateway URL: {Url}", _configuration["ServiceUrls:ApiGateway"]);
            _logger.LogInformation("Order Service URL: {Url}", _configuration["ServiceUrls:OrderService"]);
            _logger.LogInformation("Inventory Service URL: {Url}", _configuration["ServiceUrls:InventoryService"]);

            var client = _clientFactory.CreateClient("ApiGateway");
            var baseUrl = _configuration["ServiceUrls:ApiGateway"];
            _logger.LogInformation("Using API Gateway URL: {BaseUrl}", baseUrl);

            // Add configuration validation
            if (string.IsNullOrEmpty(baseUrl))
            {
                _logger.LogWarning("API Gateway URL not configured, using default");
                baseUrl = "http://localhost:7237";
            }

            // Fallback to default URL if not configured
            client.BaseAddress = new Uri(baseUrl);

            // Get real system metrics
            var systemMetrics = _systemMetrics.GetSystemMetrics();
            _logger.LogInformation("System Metrics - CPU: {CPU}%, Memory: {Memory}%, Storage: {Storage}%",
                systemMetrics.CpuUsage,
                systemMetrics.MemoryUsage,
                systemMetrics.StorageUsage);

            var orders = new List<OrderDto>();
            var inventory = new List<InventoryItemDto>();
            var apiHealthy = true;
            var responseTime = 0L;

            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                var stopwatch = Stopwatch.StartNew();

                _logger.LogInformation("Making API requests to endpoints: /api/gateway/orders and /api/gateway/inventory");

                // Make multiple requests in parallel with timeout
                var orderTask = client.GetAsync("/api/gateway/orders", cts.Token);
                var inventoryTask = client.GetAsync("/api/gateway/inventory", cts.Token);

                await Task.WhenAll(orderTask, inventoryTask);
                var orderResponse = await orderTask;
                var inventoryResponse = await inventoryTask;

                stopwatch.Stop();
                responseTime = stopwatch.ElapsedMilliseconds;

                // Process Orders
                if (orderResponse.IsSuccessStatusCode)
                {
                    var content = await orderResponse.Content.ReadAsStringAsync();
                    _logger.LogInformation("Orders API Raw Response: {Content}", content);

                    try
                    {
                        orders = await orderResponse.Content.ReadFromJsonAsync<List<OrderDto>>(cancellationToken: cts.Token)
                            ?? new List<OrderDto>();
                        _logger.LogInformation("Successfully parsed {Count} orders", orders.Count);
                    }
                    catch (JsonException ex)
                    {
                        _logger.LogError(ex, "Failed to parse orders JSON response");
                        apiHealthy = false;
                    }
                }
                else
                {
                    apiHealthy = false;
                    _logger.LogWarning("Orders API failed with status code: {StatusCode}", orderResponse.StatusCode);
                    var errorContent = await orderResponse.Content.ReadAsStringAsync();
                    _logger.LogWarning("Orders API error response: {Error}", errorContent);
                }

                // Process Inventory
                if (inventoryResponse.IsSuccessStatusCode)
                {
                    var content = await inventoryResponse.Content.ReadAsStringAsync();
                    _logger.LogInformation("Inventory API Raw Response: {Content}", content);

                    try
                    {
                        inventory = await inventoryResponse.Content.ReadFromJsonAsync<List<InventoryItemDto>>(cancellationToken: cts.Token)
                            ?? new List<InventoryItemDto>();
                        _logger.LogInformation("Successfully parsed {Count} inventory items", inventory.Count);
                    }
                    catch (JsonException ex)
                    {
                        _logger.LogError(ex, "Failed to parse inventory JSON response");
                        apiHealthy = false;
                    }
                }
                else
                {
                    apiHealthy = false;
                    _logger.LogWarning("Inventory API failed with status code: {StatusCode}", inventoryResponse.StatusCode);
                    var errorContent = await inventoryResponse.Content.ReadAsStringAsync();
                    _logger.LogWarning("Inventory API error response: {Error}", errorContent);
                }

                // Record metrics using RealTimeMetricsCollector
                _realTimeMetrics.RecordCustomMetric("api_response_time", responseTime);
                _realTimeMetrics.RecordCustomMetric("active_orders", orders.Count);
                _realTimeMetrics.RecordCustomMetric("inventory_items", inventory.Count);

                var requestRate = _realTimeMetrics.GetCustomRequestRate();

                // Generate response data
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
                    responseTime = $"{responseTime}ms",
                    cpuUsage = systemMetrics.CpuUsage,
                    memoryUsage = systemMetrics.MemoryUsage,
                    storageUsage = systemMetrics.StorageUsage,
                    requestRate = requestRate,
                    errorRate = apiHealthy ? 0 : 100,

                    // For debugging
                    apiStatus = new
                    {
                        ordersEndpoint = orderResponse.StatusCode.ToString(),
                        inventoryEndpoint = inventoryResponse.StatusCode.ToString(),
                        responseTimeMs = responseTime,
                        healthy = apiHealthy
                    },

                    // Trend data
                    orderTrends = apiHealthy ? await GetOrderTrends(orders) : GenerateOrderTrends(),
                    inventoryTrends = apiHealthy ? await GetInventoryTrends(inventory) : GenerateInventoryTrends(),

                    // Last update time
                    lastUpdated = DateTime.UtcNow
                };

                return Json(data);
            }
            catch (OperationCanceledException)
            {
                _logger.LogWarning("API request timeout after {Timeout} seconds", 10);
                return StatusCode(504, new { error = "API Gateway timeout", details = "Request timed out" });
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error when calling API Gateway");
                return StatusCode(502, new { error = "API Gateway error", details = ex.Message });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error fetching dashboard data: {Message}", ex.Message);
                return StatusCode(500, new { error = "Internal server error", details = ex.Message });
            }
        }
        catch (BrokenCircuitException)
        {
            _logger.LogWarning("Circuit breaker is open, returning fallback data");

            var systemMetrics = _systemMetrics.GetSystemMetrics();
            return Json(new
            {
                activeOrders = 0,
                inventoryCount = 0,
                systemHealth = "Degraded",
                responseTime = "0ms",
                cpuUsage = systemMetrics.CpuUsage,
                memoryUsage = systemMetrics.MemoryUsage,
                storageUsage = systemMetrics.StorageUsage,
                errorRate = 100,
                apiStatus = new
                {
                    ordersEndpoint = "Circuit Open",
                    inventoryEndpoint = "Circuit Open",
                    healthy = false
                },
                orderTrends = GenerateOrderTrends(),
                inventoryTrends = GenerateInventoryTrends(),
                lastUpdated = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Critical error in GetDashboardData: {Message}", ex.Message);
            return StatusCode(500, new { error = "Critical error", details = ex.Message });
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