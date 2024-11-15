using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using FrontendService.Models;
using System.Text.Json;
using Frontend.Models;
using FrontendService.Models.DTOs;

namespace FrontendService.Controllers;

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

            // Parallel requests for performance
            var responses = await Task.WhenAll(
                client.GetAsync("/api/gateway/orders"),
                client.GetAsync("/api/gateway/inventory"),
                client.GetAsync("/metrics"),
                client.GetAsync("/health")
            );

            var orders = await responses[0].Content.ReadFromJsonAsync<List<OrderDto>>();
            var inventory = await responses[1].Content.ReadFromJsonAsync<List<InventoryItemDto>>();
            var metrics = await ParsePrometheusMetrics(await responses[2].Content.ReadAsStringAsync());
            var health = await responses[3].Content.ReadAsStringAsync();

            var allServicesHealthy = responses.All(r => r.IsSuccessStatusCode);
            var responseTime = CalculateAverageResponseTime(responses);

            // Get trends data
            var orderTrends = await GetOrderTrendsData();
            var inventoryTrends = await GetInventoryTrendsData();

            return Json(new
            {
                // Order metrics
                activeOrders = orders?.Count ?? 0,
                pendingOrders = orders?.Count(o => o.Status == "Pending") ?? 0,
                completedOrders = orders?.Count(o => o.Status == "Completed") ?? 0,
                totalOrderValue = orders?.Sum(o => o.TotalPrice) ?? 0,

                // Inventory metrics
                inventoryCount = inventory?.Count ?? 0,
                lowStockItems = inventory?.Count(i => i.Quantity <= i.MinimumQuantity) ?? 0,
                totalInventoryValue = inventory?.Sum(i => i.Price * i.Quantity) ?? 0,
                outOfStockItems = inventory?.Count(i => i.Quantity == 0) ?? 0,

                // System metrics
                systemHealth = allServicesHealthy ? "Healthy" : "Degraded",
                responseTime = $"{responseTime:0}ms",
                cpuUsage = metrics.GetValueOrDefault("process_cpu_seconds_total", 0),
                memoryUsage = metrics.GetValueOrDefault("process_resident_memory_bytes", 0) / (1024 * 1024), // MB
                requestRate = metrics.GetValueOrDefault("http_requests_total", 0),
                errorRate = CalculateErrorRate(metrics),

                // Time series data
                orderTrends,
                inventoryTrends
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching dashboard data");
            return StatusCode(500, new { error = "Error fetching dashboard data", details = ex.Message });
        }
    }

    private async Task<List<OrderTrendData>> GetOrderTrendsData()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var response = await client.GetAsync("/api/gateway/orders/trends");
            if (response.IsSuccessStatusCode)
            {
                return await response.Content.ReadFromJsonAsync<List<OrderTrendData>>() ?? new List<OrderTrendData>();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching order trends");
        }
        return new List<OrderTrendData>();
    }

    private async Task<List<InventoryTrendData>> GetInventoryTrendsData()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var response = await client.GetAsync("/api/gateway/inventory/trends");
            if (response.IsSuccessStatusCode)
            {
                return await response.Content.ReadFromJsonAsync<List<InventoryTrendData>>() ?? new List<InventoryTrendData>();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching inventory trends");
        }
        return new List<InventoryTrendData>();
    }

    private async Task<ServiceUptimeInfo> GetServiceUptimeInfoAsync(string serviceName)
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var response = await client.GetAsync($"/api/gateway/{serviceName.ToLower().Replace(" ", "")}/metrics");

            if (response.IsSuccessStatusCode)
            {
                var metrics = await ParsePrometheusMetrics(await response.Content.ReadAsStringAsync());
                var uptimeSeconds = metrics.GetValueOrDefault("process_uptime_seconds", 0);
                var uptime = TimeSpan.FromSeconds(uptimeSeconds);

                return new ServiceUptimeInfo
                {
                    UptimeDisplay = uptime.TotalDays >= 1 ? $"{uptime.TotalDays:F1} days" : $"{uptime.TotalHours:F1} hours",
                    UptimePercentage = CalculateUptimePercentage(uptimeSeconds)
                };
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting uptime for {ServiceName}", serviceName);
        }

        return new ServiceUptimeInfo { UptimeDisplay = "Unknown", UptimePercentage = 0 };
    }

    private double CalculateUptimePercentage(double uptimeSeconds, double totalPossibleSeconds = 86400) // Default: 1 day in seconds
    {
        if (totalPossibleSeconds <= 0)
        {
            throw new ArgumentException("Total possible seconds must be greater than zero.", nameof(totalPossibleSeconds));
        }

        // Calculate uptime percentage as a value between 0 and 100
        double uptimePercentage = (uptimeSeconds / totalPossibleSeconds) * 100;

        // Clamp the value to a range of 0 to 100 to handle edge cases
        return Math.Clamp(uptimePercentage, 0, 100);
    }


    [HttpGet]
    public async Task<IActionResult> GetServiceStatus()
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var services = new[]
            {
                ("Order Service", "/api/gateway/orders/health", "/api/gateway/orders/metrics"),
                ("Inventory Service", "/api/gateway/inventory/health", "/api/gateway/inventory/metrics"),
                ("Frontend Service", "/health", "/metrics")
            };

            var statuses = new List<ServiceStatus>();

            foreach (var (name, healthEndpoint, metricsEndpoint) in services)
            {
                try
                {
                    var healthTask = client.GetAsync(healthEndpoint);
                    var metricsTask = client.GetAsync(metricsEndpoint);
                    await Task.WhenAll(healthTask, metricsTask);

                    var metrics = await ParsePrometheusMetrics(await metricsTask.Result.Content.ReadAsStringAsync());
                    var uptime = await GetServiceUptime(name);

                    statuses.Add(new ServiceStatus
                    {
                        Name = name,
                        Status = healthTask.Result.IsSuccessStatusCode ? "Healthy" : "Unhealthy",
                        LastUpdated = DateTime.UtcNow,
                        Uptime = uptime,
                        Metrics = new Dictionary<string, string>
                        {
                            { "Requests", FormatRequestRate(metrics) },
                            { "ErrorRate", FormatErrorRate(metrics) },
                            { "AvgResponseTime", FormatResponseTime(metrics) },
                            { "MemoryUsage", FormatMemoryUsage(metrics) }
                        },
                        RecentErrors = await GetRecentErrors(name),
                        HealthCheckDetails = await healthTask.Result.Content.ReadAsStringAsync()
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error checking service {ServiceName}", name);
                    statuses.Add(new ServiceStatus
                    {
                        Name = name,
                        Status = "Unhealthy",
                        LastUpdated = DateTime.UtcNow,
                        Uptime = "0%",
                        HealthCheckDetails = ex.Message
                    });
                }
            }

            return Json(statuses);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching service status");
            return StatusCode(500, new { error = "Error fetching service status" });
        }
    }

    private async Task<Dictionary<string, double>> ParsePrometheusMetrics(string metricsData)
    {
        var metrics = new Dictionary<string, double>();
        var lines = metricsData.Split('\n');

        foreach (var line in lines)
        {
            if (line.StartsWith('#')) continue;
            var parts = line.Split(' ');
            if (parts.Length == 2 && double.TryParse(parts[1], out var value))
            {
                metrics[parts[0]] = value;
            }
        }

        return metrics;
    }

    private double CalculateAverageResponseTime(IEnumerable<HttpResponseMessage> responses)
    {
        var times = responses
            .Where(r => r.Headers.Date.HasValue)
            .Select(r => (DateTime.UtcNow - r.Headers.Date.Value.UtcDateTime).TotalMilliseconds);

        return times.Any() ? times.Average() : 0;
    }

    private double CalculateErrorRate(Dictionary<string, double> metrics)
    {
        var totalRequests = metrics.GetValueOrDefault("http_requests_total", 0);
        var errorRequests = metrics.GetValueOrDefault("http_requests_errors_total", 0);

        return totalRequests > 0 ? (errorRequests / totalRequests) * 100 : 0;
    }

    private async Task<string> GetServiceUptime(string serviceName)
    {
        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");
            var response = await client.GetAsync($"/api/gateway/{serviceName.ToLower().Replace(" ", "")}/metrics");
            var metrics = await ParsePrometheusMetrics(await response.Content.ReadAsStringAsync());

            var uptimeSeconds = metrics.GetValueOrDefault("process_uptime_seconds", 0);
            var uptime = TimeSpan.FromSeconds(uptimeSeconds);

            return uptime.TotalDays >= 1
                ? $"{uptime.TotalDays:F1} days"
                : $"{uptime.TotalHours:F1} hours";
        }
        catch
        {
            return "Unknown";
        }
    }

    private async Task<List<string>> GetRecentErrors(string serviceName)
    {
        try
        {
            // Query Loki logs for errors
            var lokiUrl = _configuration["ServiceUrls:Loki"];
            var client = _clientFactory.CreateClient();
            var response = await client.GetAsync(
                $"{lokiUrl}/loki/api/v1/query?query={{service=\"{serviceName}\"}} |= \"error\" | limit 5");

            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                // Parse Loki response and extract error messages
                // This is a simplified implementation
                return content.Split('\n').Take(5).ToList();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching logs for {ServiceName}", serviceName);
        }

        return new List<string>();
    }

    private string FormatRequestRate(Dictionary<string, double> metrics)
    {
        var rate = metrics.GetValueOrDefault("http_requests_total", 0);
        return rate > 1000 ? $"{rate/1000:F1}k/min" : $"{rate:F0}/min";
    }

    private string FormatErrorRate(Dictionary<string, double> metrics)
    {
        return $"{CalculateErrorRate(metrics):F2}%";
    }

    private string FormatResponseTime(Dictionary<string, double> metrics)
    {
        var time = metrics.GetValueOrDefault("http_request_duration_seconds", 0) * 1000;
        return $"{time:F0}ms";
    }

    private string FormatMemoryUsage(Dictionary<string, double> metrics)
    {
        var bytes = metrics.GetValueOrDefault("process_resident_memory_bytes", 0);
        return $"{bytes / (1024*1024):F0}MB";
    }

    private async Task<string> GetRequestCount(string serviceName)
    {
        // Implement request count from metrics
        return "1.2k/min";
    }

    private async Task<string> GetErrorRate(string serviceName)
    {
        // Implement error rate calculation
        return "0.01%";
    }

    private async Task<string> GetAvgResponseTime(string serviceName)
    {
        // Implement average response time calculation
        return "125ms";
    }

    public async Task<IActionResult> Index()
    {
        var dashboardData = new DashboardViewModel();

        try
        {
            var client = _clientFactory.CreateClient("ApiGateway");

            // Parallel requests
            var orderTask = client.GetAsync("/api/gateway/orders");
            var inventoryTask = client.GetAsync("/api/gateway/inventory");
            await Task.WhenAll(orderTask, inventoryTask);

            if (orderTask.Result.IsSuccessStatusCode)
            {
                var content = await orderTask.Result.Content.ReadAsStringAsync();
                dashboardData.Orders = JsonSerializer.Deserialize<List<OrderDto>>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new List<OrderDto>();
            }

            if (inventoryTask.Result.IsSuccessStatusCode)
            {
                var content = await inventoryTask.Result.Content.ReadAsStringAsync();
                dashboardData.InventoryItems = JsonSerializer.Deserialize<List<InventoryItemDto>>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new List<InventoryItemDto>();
            }

            dashboardData.CalculateMetrics();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching dashboard data");
            TempData["Error"] = "Error loading dashboard data. Some metrics may be unavailable.";
        }

        return View(dashboardData);
    }

    public async Task<IActionResult> _Index()
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
