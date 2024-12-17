using InsightOps.Observability.Extensions;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using FrontendService.Services;
using InsightOps.Observability.Metrics;
using InsightOps.Observability.Options;
using InsightOps.Observability.SignalR;
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using System.Net.Http.Headers;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.DataProtection.AuthenticatedEncryption.ConfigurationModel;
using Microsoft.AspNetCore.DataProtection.AuthenticatedEncryption;
using Polly;
using Polly.Extensions.Http;
using Polly.Timeout;

// Retry policy configuration
static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .Or<TimeoutRejectedException>()
        .WaitAndRetryAsync(
            retryCount: 3,
            sleepDurationProvider: retryAttempt =>
                TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
            onRetry: (exception, timeSpan, retryCount, context) =>
            {
                Log.Warning(
                    "Retry {RetryCount} after {RetryTime}s delay due to {ExceptionType}: {ExceptionMessage}",
                    retryCount,
                    timeSpan.TotalSeconds,
                    exception.Exception?.GetType().Name,
                    exception.Exception?.Message
                );
            });
}

// Circuit breaker policy configuration
static IAsyncPolicy<HttpResponseMessage> GetCircuitBreakerPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .CircuitBreakerAsync(
            handledEventsAllowedBeforeBreaking: 5,
            durationOfBreak: TimeSpan.FromSeconds(30),
            onBreak: (exception, duration) =>
            {
                Log.Warning(
                    "Circuit breaker opened for {DurationSec}s due to: {ExceptionMessage}",
                    duration.TotalSeconds,
                    exception.Exception?.Message
                );
            },
            onReset: () =>
            {
                Log.Information("Circuit breaker reset");
            });
}

var builder = WebApplication.CreateBuilder(args);

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddHttpsRedirection(options =>
    {
        options.HttpsPort = 44300;
    });
    builder.WebHost.UseUrls("https://localhost:44300", "http://localhost:5010");
}

// Configure Serilog first
builder.Host.UseSerilog((context, config) =>
    config.ReadFrom.Configuration(context.Configuration));

// Register services from the Observability package
builder.Services.Configure<ObservabilityOptions>(builder.Configuration.GetSection("Observability"));
builder.Services.AddSingleton<InsightOps.Observability.Metrics.RealTimeMetricsCollector>();
builder.Services.AddSingleton<InsightOps.Observability.Metrics.SystemMetricsCollector>();

// If you have local monitoring services, register them as well
//builder.Services.AddSingleton<FrontendService.Services.Monitoring.MetricsCollector>();
//builder.Services.AddSingleton<FrontendService.Services.Monitoring.SystemMetricsCollector>();

// Configure SignalR
builder.Services.AddSignalR(options =>
{
    var signalRConfig = builder.Configuration.GetSection("SignalR").Get<SignalROptions>();
    options.EnableDetailedErrors = signalRConfig?.DetailedErrors ?? true;
    options.MaximumReceiveMessageSize = signalRConfig?.MaximumReceiveMessageSize ?? 102400;
});

// Add centralized observability
builder.Services.AddInsightOpsObservability(
    builder.Configuration,
    "FrontendService",
    options =>
    {
        options.Common.ServiceName = "FrontendService";
    });

// Register application services
builder.Services.AddHostedService<MetricsBackgroundService>();
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IInventoryService, InventoryService>();
builder.Services.AddSingleton<ServiceUrlResolver>();

// Configure MVC
builder.Services.AddControllersWithViews()
    .AddJsonOptions(options =>
    {
        var jsonConfig = builder.Configuration.GetSection("Application:JsonOptions").Get<InsightOps.Observability.Options.JsonSerializerOptions>();
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
        options.JsonSerializerOptions.PropertyNamingPolicy = null;
    });

// If in Docker environment, add encryption
// Update the data protection configuration
builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo("/app/Keys"))
    .SetApplicationName("InsightOps")
    .UseCryptographicAlgorithms(new AuthenticatedEncryptorConfiguration
    {
        EncryptionAlgorithm = EncryptionAlgorithm.AES_256_CBC,
        ValidationAlgorithm = ValidationAlgorithm.HMACSHA256
    });

// Register HttpClient with proper configuration
builder.Services.AddHttpClient("ApiGateway", client =>
{
    var apiGatewayUrl = builder.Configuration["ServiceUrls:ApiGateway"]
        ?? throw new InvalidOperationException("ApiGateway URL not configured");
    client.BaseAddress = new Uri(apiGatewayUrl);
    client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    client.Timeout = TimeSpan.FromSeconds(30);
})
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

builder.Services.AddHealthChecks()
    .AddUrlGroup(
        new Uri($"{builder.Configuration["ServiceUrls:ApiGateway"]}/health"),
        name: "apigateway-check",
        failureStatus: HealthStatus.Degraded,
        timeout: TimeSpan.FromSeconds(5))
    .AddUrlGroup(
        new Uri($"{builder.Configuration["ServiceUrls:OrderService"]}/health"),
        name: "orders-check",
        failureStatus: HealthStatus.Degraded,
        timeout: TimeSpan.FromSeconds(5))
    .AddUrlGroup(
        new Uri($"{builder.Configuration["ServiceUrls:InventoryService"]}/health"),
        name: "inventory-check",
        failureStatus: HealthStatus.Degraded,
        timeout: TimeSpan.FromSeconds(5))
    .AddCheck<ServiceConfigHealthCheck>("service-config-health")
    .AddCheck<DatabaseConnectivityCheck>("database-health")
    .AddCheck<ServicesConnectivityCheck>("services-connectivity");


var app = builder.Build();

// After builder.Build()
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = async (context, report) =>
    {
        context.Response.ContentType = "application/json";
        await context.Response.WriteAsync(JsonSerializer.Serialize(new
        {
            status = report.Status.ToString(),
            checks = report.Entries.Select(e => new
            {
                name = e.Key,
                status = e.Value.Status.ToString(),
                duration = e.Value.Duration
            })
        }));
    }
});

// Configure error handling
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    // Set scheme to HTTP for Docker environment
    app.Use(async (context, next) =>
    {
        context.Request.Scheme = "http";
        await next();
    });

    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

// Configure the HTTP request pipeline in correct order
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();  
app.UseAuthorization();

// Use centralized observability middleware
app.UseInsightOpsObservability();

// Request logging middleware
app.Use(async (context, next) =>
{
    var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
    logger.LogInformation(
        "Request Path: {Path}, Method: {Method}, Route: {@RouteValues}",
        context.Request.Path,
        context.Request.Method,
        context.GetRouteData()?.Values
    );
    await next();
});

// Endpoint configuration
app.UseEndpoints(endpoints =>
{
    // Keep SignalR hub mapping
    endpoints.MapHub<MetricsHub>("/metrics-hub");

    // Single default route for MVC
    endpoints.MapControllerRoute(
        name: "default",
        pattern: "{controller=Home}/{action=Index}/{id?}");

    // Health checks
    endpoints.MapHealthChecks("/health");
});

// Add root redirect
app.MapGet("/", context => {
    context.Response.Redirect("/Home/Index");
    return Task.CompletedTask;
});

// Start the application
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