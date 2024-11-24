using InsightOps.Observability.Extensions;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Observability.Extensions;
using Polly;
using Polly.Extensions.Http;
using Serilog;
using InsightOps.Observability.SignalR;
using Microsoft.AspNetCore.DataProtection;
using System.Net.Http.Headers;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using System.Text.Json;
using FrontendService.Services;

var builder = WebApplication.CreateBuilder(args);

// Get configuration values
var dataProtectionConfig = builder.Configuration.GetSection("DataProtection").Get<DataProtectionConfig>()
    ?? new DataProtectionConfig();
var httpClientConfig = builder.Configuration.GetSection("HttpClient").Get<HttpClientConfig>()
    ?? new HttpClientConfig();
var signalRConfig = builder.Configuration.GetSection("SignalR").Get<SignalRConfig>()
    ?? new SignalRConfig();

var dataProtectionPath = builder.Configuration["DataProtection:Keys"] ?? "/app/Keys";
var serviceName = builder.Configuration["Observability:Common:ServiceName"] ?? "FrontendService";
var retryCount = builder.Configuration.GetValue<int>("HttpClient:RetryCount", 5);
var retryDelayMs = builder.Configuration.GetValue<int>("HttpClient:RetryDelayMs", 100);
var circuitBreakerThreshold = builder.Configuration.GetValue<int>("HttpClient:CircuitBreakerThreshold", 10);
var circuitBreakerDelay = builder.Configuration.GetValue<int>("HttpClient:CircuitBreakerDelay", 5);
var httpClientTimeout = builder.Configuration.GetValue<int>("HttpClient:TimeoutSeconds", 30);

// Ensure Data Protection keys directory exists
Directory.CreateDirectory(dataProtectionPath);

// Configure Data Protection
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(dataProtectionConfig.Keys))
    .SetDefaultKeyLifetime(TimeSpan.FromDays(dataProtectionConfig.KeyLifetimeDays));
//builder.Services.AddDataProtection()
//   .PersistKeysToFileSystem(new DirectoryInfo(dataProtectionPath))
//   .SetDefaultKeyLifetime(TimeSpan.FromDays(90));

// Configure Serilog
builder.Host.UseInsightOpsSerilog(
    builder.Configuration,
    serviceName);

// Add centralized observability
builder.Services.AddInsightOpsObservability(
    builder.Configuration,
    serviceName);

// Register application services
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IInventoryService, InventoryService>();

builder.Services.AddSignalR();

builder.Services.AddControllersWithViews()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
        options.JsonSerializerOptions.PropertyNamingPolicy = null;
    });

// Configure HTTP clients
builder.Services.AddHttpClient("ApiGateway", client =>
{
    var apiGatewayUrl = builder.Configuration["ServiceUrls:ApiGateway"]
        ?? throw new InvalidOperationException("ApiGateway URL is not configured");
    client.BaseAddress = new Uri(apiGatewayUrl);
    client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    client.Timeout = TimeSpan.FromSeconds(httpClientTimeout);
})
.AddTransientHttpErrorPolicy(p =>
    p.WaitAndRetryAsync(
        retryCount: retryCount,
        sleepDurationProvider: retryAttempt =>
            TimeSpan.FromMilliseconds(retryDelayMs * Math.Pow(2, retryAttempt)),
        onRetry: (exception, timeSpan, attemptCount, context) =>
        {
            Log.Warning(
                "Retry {RetryCount} after {Delay}ms delay due to {ErrorMessage}",
                attemptCount, timeSpan.TotalMilliseconds, exception.Exception?.Message);
        }))
.AddTransientHttpErrorPolicy(p =>
    p.CircuitBreakerAsync(
        handledEventsAllowedBeforeBreaking: circuitBreakerThreshold,
        durationOfBreak: TimeSpan.FromSeconds(circuitBreakerDelay),
        onBreak: (exception, duration) =>
        {
            Log.Warning(
                "Circuit breaker opened for {Duration}s due to {ErrorMessage}",
                duration.TotalSeconds, exception.Exception?.Message);
        },
        onReset: () => Log.Information("Circuit breaker reset")));

// Configure Health Checks
var healthChecks = builder.Services.AddHealthChecks();

// Add health checks from configuration
foreach (var endpoint in builder.Configuration.GetSection("HealthChecks:Endpoints").GetChildren())
{
    var name = endpoint["Name"];
    var url = endpoint["Url"];
    if (!string.IsNullOrEmpty(name) && !string.IsNullOrEmpty(url))
    {
        healthChecks.AddUrlGroup(
            new Uri(url),
            name: name.ToLowerInvariant(),
            failureStatus: Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Degraded);
    }
}

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Home/Error");
}

// Configure Health Check endpoint
app.UseHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = async (context, report) =>
    {
        context.Response.ContentType = "application/json";
        var response = new
        {
            status = report.Status.ToString(),
            checks = report.Entries.Select(x => new
            {
                name = x.Key,
                status = x.Value.Status.ToString(),
                description = x.Value.Description,
                duration = x.Value.Duration.TotalMilliseconds,
                tags = x.Value.Tags
            }),
            totalDuration = report.TotalDuration.TotalMilliseconds
        };
        await JsonSerializer.SerializeAsync(context.Response.Body, response);
    }
});

app.UseInsightOpsObservability();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

app.MapHub<MetricsHub>("/metrics-hub");
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

try
{
    Log.Information("Starting {ServiceName}...", serviceName);
    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application start-up failed");
    throw;
}
finally
{
    Log.CloseAndFlush();
}