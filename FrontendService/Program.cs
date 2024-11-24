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

// Ensure Data Protection keys directory exists
var keysDirectory = "/app/Keys";
Directory.CreateDirectory(keysDirectory);

// Configure Data Protection
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(keysDirectory))
    .SetDefaultKeyLifetime(TimeSpan.FromDays(90));

// Configure Serilog
builder.Host.UseInsightOpsSerilog(
    builder.Configuration,
    "FrontendService");

// Add centralized observability
builder.Services.AddInsightOpsObservability(
    builder.Configuration,
    "FrontendService");

// Register application services
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IInventoryService, InventoryService>();

// Add SignalR
builder.Services.AddSignalR();

// Configure Controllers
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
    client.Timeout = TimeSpan.FromSeconds(30);
})
.AddTransientHttpErrorPolicy(p =>
    p.WaitAndRetryAsync(
        retryCount: 5,
        sleepDurationProvider: retryAttempt =>
            TimeSpan.FromMilliseconds(100 * Math.Pow(2, retryAttempt)),
        onRetry: (exception, timeSpan, retryCount, context) =>
        {
            Log.Warning(
                "Retry {RetryCount} after {Delay}ms delay due to {ErrorMessage}",
                retryCount, timeSpan.TotalMilliseconds, exception.Exception?.Message);
        }))
.AddTransientHttpErrorPolicy(p =>
    p.CircuitBreakerAsync(
        handledEventsAllowedBeforeBreaking: 10,
        durationOfBreak: TimeSpan.FromSeconds(5),
        onBreak: (exception, duration) =>
        {
            Log.Warning(
                "Circuit breaker opened for {Duration}s due to {ErrorMessage}",
                duration.TotalSeconds, exception.Exception?.Message);
        },
        onReset: () =>
        {
            Log.Information("Circuit breaker reset");
        }));

// Configure Health Checks
builder.Services.AddHealthChecks()
    .AddUrlGroup(
        new Uri($"{builder.Configuration["ServiceUrls:ApiGateway"]}/health"),
        name: "api-gateway",
        failureStatus: Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Degraded)
    .AddUrlGroup(
        new Uri($"{builder.Configuration["ServiceUrls:OrderService"]}/health"),
        name: "orders-api",
        failureStatus: Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Degraded)
    .AddUrlGroup(
        new Uri($"{builder.Configuration["ServiceUrls:InventoryService"]}/health"),
        name: "inventory-api",
        failureStatus: Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Degraded);

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

// Use existing observability middleware
app.UseInsightOpsObservability();

app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

// Map SignalR hub
app.MapHub<MetricsHub>("/metrics-hub");

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

try
{
    Log.Information("Starting FrontendService...");
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