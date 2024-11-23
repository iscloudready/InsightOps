using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Diagnostics;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using Serilog.Events;
using System.Net.Http.Headers;
using Polly;
using Polly.Extensions.Http;
using Polly.Timeout;
using FrontendService.Services;
using FrontendService.Services.Monitoring;
using FrontendService.Extensions;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Serilog.Core;
using System.IO;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
//using FrontendService.Monitoring;
//using InsightOps.Observability.Metrics;
//using InsightOps.Observability.SignalR;
//using InsightOps.Observability.Configurations;
//using SystemMetricsCollector = InsightOps.Observability.Metrics.SystemMetricsCollector;
using FrontendService.Monitoring;  // New monitoring namespace

var builder = WebApplication.CreateBuilder(args);

// Ensure the Data Protection keys directory exists
var keysDirectory = "/app/Keys";
Directory.CreateDirectory(keysDirectory);

// Configure logging first
builder.Services.AddLogging(loggingBuilder =>
{
    loggingBuilder.ClearProviders();
    loggingBuilder.AddConsole();
    loggingBuilder.AddDebug();
    loggingBuilder.SetMinimumLevel(builder.Environment.IsDevelopment() ?
        LogLevel.Debug : LogLevel.Information);
});

// Add after existing builder.Services configurations:
builder.Services.AddSingleton<RealTimeMetricsCollector>();
//builder.Services.AddSingleton<CustomMetricsCollector>();

// Add monitoring configuration
builder.Services.Configure<MonitoringOptions>(options =>
{
    options.MetricsInterval = TimeSpan.FromSeconds(10);
    options.RetentionDays = 7;
    options.EnableDetailedMetrics = true;
});

// Configure SignalR for real-time updates
builder.Services.AddSignalR(options =>
{
    options.EnableDetailedErrors = true;
    options.MaximumReceiveMessageSize = 102400;
});

builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo(keysDirectory))
    .SetDefaultKeyLifetime(TimeSpan.FromDays(90));

// Configure Serilog based on environment
var lokiUrl = builder.Environment.IsDevelopment()
    ? "http://localhost:3101"
    : "http://loki:3101";

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("service", "Frontend")
    .Enrich.WithProperty("environment", builder.Environment.EnvironmentName)
    .Enrich.WithProperty("traceId", Activity.Current?.Id ?? "")
    .WriteTo.Console(
        outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties}{NewLine}{Exception}")
    .WriteTo.Http(
        requestUri: $"{lokiUrl}/loki/api/v1/push",
        restrictedToMinimumLevel: LogEventLevel.Information,
        queueLimitBytes: null)
    .CreateLogger();

builder.Host.UseSerilog();

// Add services to the container
builder.Services.AddControllersWithViews()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
        options.JsonSerializerOptions.PropertyNamingPolicy = null;
    });

// Register services
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IInventoryService, InventoryService>();

// Configure services and logging based on environment
if (builder.Environment.IsDevelopment() || builder.Environment.EnvironmentName == "Docker")
{
    builder.Services.Configure<LoggerFilterOptions>(options =>
    {
        options.MinLevel = LogLevel.Debug;
    });
}

// First register core services
builder.Services.AddSingleton<MetricsCollector>();
builder.Services.AddSingleton<SystemMetricsCollector>();
builder.Services.AddHostedService<MetricsBackgroundService>();

// Register application services
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IInventoryService, InventoryService>();

// Configure HttpClient with proper policies
builder.Services.AddHttpClient("ApiGateway", client =>
{
    var apiGatewayUrl = builder.Configuration["ServiceUrls:ApiGateway"] ?? "http://localhost:7237";
    //_logger.LogInformation("Configuring API Gateway URL: {Url}", apiGatewayUrl);
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
            Console.WriteLine($"Retry {retryCount} after {timeSpan.TotalMilliseconds}ms delay due to {exception.Exception?.Message}");
        })
)
.AddTransientHttpErrorPolicy(p =>
    p.CircuitBreakerAsync(
        handledEventsAllowedBeforeBreaking: 10,
        durationOfBreak: TimeSpan.FromSeconds(5),
        onBreak: (exception, duration) =>
        {
            Console.WriteLine($"Circuit breaker opened for {duration.TotalSeconds}s due to {exception.Exception?.Message}");
        },
        onReset: () =>
        {
            Console.WriteLine("Circuit breaker reset");
        })
);

// Configure health checks
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

// Configure monitoring endpoints
var tempoEndpoint = builder.Environment.IsDevelopment()
    ? "http://localhost:4317"
    : "http://tempo:4317";

// Add to Program.cs
//builder.Services.AddHealthChecks()
//    .AddCheck<DatabaseHealthCheck>("database")
//    .AddCheck<ApiGatewayHealthCheck>("api-gateway")
//    .AddCheck<StorageHealthCheck>("storage");

// Configure OpenTelemetry
builder.Services.AddOpenTelemetry()
    .WithTracing(tracerProviderBuilder =>
    {
        tracerProviderBuilder
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri(tempoEndpoint);
            })
            .SetResourceBuilder(
                ResourceBuilder.CreateDefault()
                    .AddService("Frontend")
                    .AddTelemetrySdk()
                    .AddEnvironmentVariableDetector());
    })
    .WithMetrics(metricProviderBuilder =>
    {
        metricProviderBuilder
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddRuntimeInstrumentation()
            .AddPrometheusExporter();
    });

// Configure Kestrel
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(80);
    // options.ListenAnyIP(5010);
});

var app = builder.Build();

// Add SignalR endpoint
//app.MapHub("/metrics-hub");
// Program.cs
app.UseHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = async (context, report) =>
    {
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        logger.LogInformation("Health check status: {Status}", report.Status);

        context.Response.ContentType = "application/json";
        await context.Response.WriteAsJsonAsync(new
        {
            status = report.Status.ToString(),
            checks = report.Entries.Select(e => new
            {
                name = e.Key,
                status = e.Value.Status.ToString(),
                description = e.Value.Description
            })
        });
    }
});

app.Use(async (context, next) =>
{
    var metricsCollector = context.RequestServices
        .GetRequiredService<RealTimeMetricsCollector>();

    var sw = Stopwatch.StartNew();
    try
    {
        metricsCollector.RecordApiRequest(
            context.Request.Path,
            context.Request.Method);

        await next();

        sw.Stop();
        metricsCollector.RecordApiResponse(
            context.Request.Path,
            sw.Elapsed.TotalSeconds);
    }
    catch
    {
        sw.Stop();
        throw;
    }
});

app.MapHub<MetricsHub>("/metrics-hub");

// Configure error handling with detailed messages
if (app.Environment.IsDevelopment() || app.Environment.EnvironmentName == "Docker")
{
    // app.UseMiddleware<RouteDebugMiddleware>();
    app.UseDeveloperExceptionPage();
    app.UseExceptionHandler(errorApp =>
    {
        errorApp.Run(async context =>
        {
            var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            context.Response.ContentType = "application/json";

            var exception = context.Features.Get<IExceptionHandlerFeature>();
            if (exception != null)
            {
                logger.LogError(exception.Error, "An unhandled exception occurred");

                var response = new
                {
                    StatusCode = context.Response.StatusCode,
                    Error = "An error occurred.",
                    Detail = exception.Error.Message,
                    StackTrace = app.Environment.IsDevelopment() ? exception.Error.StackTrace : null,
                    Path = context.Request.Path,
                    Timestamp = DateTime.UtcNow,
                    Environment = app.Environment.EnvironmentName,
                    RequestId = Activity.Current?.Id ?? context.TraceIdentifier
                };

                await context.Response.WriteAsJsonAsync(response);
            }
        });
    });
}
else
{
    // Production error handling
    app.UseExceptionHandler(errorApp =>
    {
        errorApp.Run(async context =>
        {
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            context.Response.ContentType = "application/json";

            await context.Response.WriteAsJsonAsync(new
            {
                StatusCode = context.Response.StatusCode,
                Message = "An unexpected error occurred. Please try again later.",
                RequestId = Activity.Current?.Id ?? context.TraceIdentifier
            });
        });
    });
}

app.UseStaticFiles();
app.UseRouting();
app.UseSerilogRequestLogging(options =>
{
    options.MessageTemplate =
        "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed:0.0000} ms";
});

// Configure middleware
app.UseHttpsRedirection();
app.UseAuthorization();

// Configure endpoints
app.UseEndpoints(endpoints =>
{
    // Default route
    endpoints.MapControllerRoute(
        name: "default",
        pattern: "{controller=Home}/{action=Index}/{id?}");

    // Specific routes for Orders and Inventory
    endpoints.MapControllerRoute(
        name: "orders",
        pattern: "Home/Orders",
        defaults: new { controller = "Orders", action = "Index" });

    endpoints.MapControllerRoute(
        name: "inventory",
        pattern: "Home/Inventory",
        defaults: new { controller = "Inventory", action = "Index" });

    endpoints.MapControllerRoute(
        name: "docker",
        pattern: "docker/{action=Index}/{id?}",
        defaults: new { controller = "DockerManagement" });

    // Health check and metrics endpoints
    endpoints.MapHealthChecks("/health", new HealthCheckOptions
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
                    description = x.Value.Description
                })
            };
            await JsonSerializer.SerializeAsync(context.Response.Body, response);
        }
    });

    endpoints.MapPrometheusScrapingEndpoint("/metrics");
});

// Add CORS if needed
app.UseCors(builder =>
{
    builder.AllowAnyOrigin()
           .AllowAnyMethod()
           .AllowAnyHeader();
});

// Add custom middleware for request logging
app.Use(async (context, next) =>
{
    var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
    try
    {
        logger.LogInformation(
            "Request {Method} {Path} started",
            context.Request.Method,
            context.Request.Path);

        await next();

        logger.LogInformation(
            "Request {Method} {Path} completed with status {StatusCode}",
            context.Request.Method,
            context.Request.Path,
            context.Response.StatusCode);
    }
    catch (Exception ex)
    {
        logger.LogError(ex,
            "Request {Method} {Path} failed",
            context.Request.Method,
            context.Request.Path);
        throw;
    }
});

try
{
    Log.Information("Starting up InsightOps Frontend...");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application startup failed");
    throw;
}
finally
{
    Log.CloseAndFlush();
}