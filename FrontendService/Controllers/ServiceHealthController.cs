using FrontendService.Models;
using Microsoft.AspNetCore.Mvc;

[Route("system-health")]
public class ServiceHealthController : Controller // ControllerBase
{
    private readonly IHttpClientFactory _clientFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<ServiceHealthController> _logger;

    public ServiceHealthController(
        IHttpClientFactory clientFactory,
        IConfiguration configuration,
        ILogger<ServiceHealthController> logger)
    {
        _clientFactory = clientFactory;
        _configuration = configuration;
        _logger = logger;
    }

    [HttpGet]
    public async Task<IActionResult> Index()
    {
        var model = new HealthStatusViewModel();

        try
        {
            // Application Services
            var applicationServices = new HealthStatusViewModel.ServiceGroup
            {
                Name = "Application Services"
            };

            applicationServices.Services.AddRange(await CheckApplicationServices());
            model.ServiceGroups.Add(applicationServices);

            // Infrastructure Services
            var infrastructureServices = new HealthStatusViewModel.ServiceGroup
            {
                Name = "Infrastructure Services"
            };

            infrastructureServices.Services.AddRange(await CheckInfrastructureServices());
            model.ServiceGroups.Add(infrastructureServices);

            model.LastUpdated = DateTime.UtcNow;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking services health");
            TempData["Error"] = "Failed to check services health";
        }

        return View(model);
    }

    [HttpGet("details/{serviceName}")]  // This will match /system-health/details/{serviceName}
    public async Task<IActionResult> Details(string serviceName)
    {
        var service = await GetServiceDetails(serviceName);
        return Json(service);
    }

    [HttpGet("metrics/{serviceName}")]  // This will match /system-health/metrics/{serviceName}
    public async Task<IActionResult> Metrics(string serviceName)
    {
        var metrics = await GetServiceMetrics(serviceName);
        return Json(metrics);
    }

    [HttpGet("refresh")]  // This will match /system-health/refresh
    public async Task<IActionResult> Refresh()
    {
        return RedirectToAction(nameof(Index));
    }

    private async Task<HealthStatusViewModel.ServiceHealth> GetServiceDetails(string serviceName)
    {
        try
        {
            // First check application services
            var applicationEndpoints = new Dictionary<string, string>
            {
                ["API Gateway"] = _configuration["ServiceUrls:ApiGateway"] + "/health",
                ["Order Service"] = _configuration["ServiceUrls:OrderService"] + "/health",
                ["Inventory Service"] = _configuration["ServiceUrls:InventoryService"] + "/health",
                ["Frontend Service"] = "/health"
            };

            // Then check infrastructure services
            var infrastructureEndpoints = new Dictionary<string, string>
            {
                ["Prometheus"] = _configuration["Observability:Infrastructure:PrometheusEndpoint"] + "/-/healthy",
                ["Grafana"] = _configuration["Observability:Infrastructure:GrafanaEndpoint"] + "/api/health",
                ["Loki"] = _configuration["Observability:Infrastructure:LokiUrl"] + "/ready",
                ["Tempo"] = _configuration["Observability:Infrastructure:TempoEndpoint"] + "/status"
            };

            var endpoints = applicationEndpoints.Concat(infrastructureEndpoints)
                                             .ToDictionary(x => x.Key, x => x.Value);

            if (!endpoints.ContainsKey(serviceName))
            {
                _logger.LogWarning("Service {ServiceName} not found", serviceName);
                return new HealthStatusViewModel.ServiceHealth
                {
                    Name = serviceName,
                    Status = "Not Found",
                    LastChecked = DateTime.UtcNow,
                    Details = "Service not found in configured endpoints"
                };
            }

            using var client = _clientFactory.CreateClient();
            var response = await client.GetAsync(endpoints[serviceName]);
            var content = await response.Content.ReadAsStringAsync();

            return new HealthStatusViewModel.ServiceHealth
            {
                Name = serviceName,
                Status = response.IsSuccessStatusCode ? "Healthy" : "Unhealthy",
                LastChecked = DateTime.UtcNow,
                Details = content,
                Metrics = await GetServiceMetrics(endpoints[serviceName].Replace("/health", "/metrics"))
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting details for service {ServiceName}", serviceName);
            return new HealthStatusViewModel.ServiceHealth
            {
                Name = serviceName,
                Status = "Error",
                LastChecked = DateTime.UtcNow,
                Details = $"Error getting service details: {ex.Message}"
            };
        }
    }

    private async Task<List<HealthStatusViewModel.ServiceHealth>> CheckApplicationServices()
    {
        var services = new List<HealthStatusViewModel.ServiceHealth>();
        var endpoints = new[]
        {
            ("API Gateway", _configuration["ServiceUrls:ApiGateway"] + "/health"),
            ("Order Service", _configuration["ServiceUrls:OrderService"] + "/health"),
            ("Inventory Service", _configuration["ServiceUrls:InventoryService"] + "/health"),
            ("Frontend Service", _configuration["ServiceUrls:FrontendService"] + "/health")
        };

        using var client = _clientFactory.CreateClient();
        foreach (var (name, url) in endpoints)
        {
            try
            {
                var response = await client.GetAsync(url);
                var content = await response.Content.ReadAsStringAsync();

                services.Add(new HealthStatusViewModel.ServiceHealth
                {
                    Name = name,
                    Status = response.IsSuccessStatusCode ? "Healthy" : "Unhealthy",
                    LastChecked = DateTime.UtcNow,
                    Details = content,
                    Metrics = await GetServiceMetrics(url.Replace("/health", "/metrics"))
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error checking health for {ServiceName}", name);
                services.Add(new HealthStatusViewModel.ServiceHealth
                {
                    Name = name,
                    Status = "Unhealthy",
                    LastChecked = DateTime.UtcNow,
                    Details = ex.Message
                });
            }
        }

        return services;
    }

    private async Task<List<HealthStatusViewModel.ServiceHealth>> CheckInfrastructureServices()
    {
        var services = new List<HealthStatusViewModel.ServiceHealth>();
        var endpoints = new[]
        {
            ("Prometheus", _configuration["Observability:Development:Infrastructure:PrometheusEndpoint"] + "/query"), // http://localhost:9091/query
            ("Grafana", _configuration["Observability:Development:Infrastructure:GrafanaEndpoint"] + "/login"), // http://localhost:3001/login
            ("Loki", _configuration["Observability:Development:Infrastructure:LokiUrl"] + "/ready"), // http://localhost:3101/ready
            ("Tempo", _configuration["Observability:Development:Infrastructure:TempoEndpoint"] + "/status"), // http://localhost:3200/status
            ("Database", _configuration["Observability:Development:Infrastructure:DatabaseUrl"]) // http://localhost:5433
        };
        using var client = _clientFactory.CreateClient();
        foreach (var (name, url) in endpoints)
        {
            try
            {
                var response = await client.GetAsync(url);
                var content = await response.Content.ReadAsStringAsync();

                services.Add(new HealthStatusViewModel.ServiceHealth
                {
                    Name = name,
                    Status = response.IsSuccessStatusCode ? "Healthy" : "Unhealthy",
                    LastChecked = DateTime.UtcNow,
                    Details = content
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error checking health for {ServiceName}", name);
                services.Add(new HealthStatusViewModel.ServiceHealth
                {
                    Name = name,
                    Status = "Unhealthy",
                    LastChecked = DateTime.UtcNow,
                    Details = ex.Message
                });
            }
        }

        return services;
    }

    private async Task<Dictionary<string, string>> GetServiceMetrics(string metricsUrl)
    {
        try
        {
            using var client = _clientFactory.CreateClient();
            var response = await client.GetAsync(metricsUrl);
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                // Parse Prometheus metrics format
                return ParsePrometheusMetrics(content);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching metrics from {Url}", metricsUrl);
        }
        return new Dictionary<string, string>();
    }

    private Dictionary<string, string> ParsePrometheusMetrics(string metricsContent)
    {
        var metrics = new Dictionary<string, string>();
        var lines = metricsContent.Split('\n');

        foreach (var line in lines)
        {
            if (string.IsNullOrWhiteSpace(line) || line.StartsWith("#"))
                continue;

            var parts = line.Split(' ');
            if (parts.Length >= 2)
            {
                metrics[parts[0]] = parts[1];
            }
        }

        return metrics;
    }
}