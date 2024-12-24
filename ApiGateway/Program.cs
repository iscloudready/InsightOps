using Microsoft.OpenApi.Models;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.SignalR;
using System.Text.Json;
using Polly;
using Polly.Extensions.Http;
using Serilog;
using Serilog.Events;
using InsightOps.Observability.Extensions;
using InsightOps.Observability.Metrics;
using InsightOps.Observability.Options;
using InsightOps.Observability.SignalR;

var builder = WebApplication.CreateBuilder(args);

// Configure Configuration Sources
builder.Configuration
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

// Configure Serilog
builder.Host.UseSerilog((hostingContext, loggerConfiguration) => {
    loggerConfiguration
        .ReadFrom.Configuration(hostingContext.Configuration)
        .MinimumLevel.Information()
        .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
        .MinimumLevel.Override("System", LogEventLevel.Warning)
        .Enrich.FromLogContext()
        .Enrich.WithProperty("Application", "ApiGateway")
        .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
        .WriteTo.Http(
            requestUri: hostingContext.Configuration["Serilog:Loki:Url"] ?? "http://loki:3100/loki/api/v1/push",
            queueLimitBytes: null);
});

// Register Observability Services
builder.Services.Configure<ObservabilityOptions>(
    builder.Configuration.GetSection("Observability"));

// Register SignalR Services (Fix for IHubContext issue)
builder.Services.AddSignalR();

// Register Metrics and Background Services
builder.Services.AddSingleton<RealTimeMetricsCollector>();
builder.Services.AddSingleton<SystemMetricsCollector>();
builder.Services.AddSingleton<MetricsHub>();
builder.Services.AddHostedService<MetricsBackgroundService>();

// Add Centralized Observability
builder.Services.AddInsightOpsObservability(
    builder.Configuration,
    "ApiGateway",
    options => {
        options.Common.ServiceName = "ApiGateway";
        options.Common.MetricsEndpoint = "/metrics";
        options.Common.HealthCheckEndpoint = "/health";
    });

// Configure Services
builder.Services.AddControllers()
    .AddJsonOptions(options => {
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    });

// Configure HTTP Clients with Resilience Patterns
builder.Services.AddHttpClient("OrderService", client => {
    client.BaseAddress = new Uri(builder.Configuration["ServiceUrls:OrderService"] ?? "http://orderservice:5012");
    client.DefaultRequestHeaders.Add("Accept", "application/json");
})
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

builder.Services.AddHttpClient("InventoryService", client => {
    client.BaseAddress = new Uri(builder.Configuration["ServiceUrls:InventoryService"] ?? "http://inventoryservice:5013");
    client.DefaultRequestHeaders.Add("Accept", "application/json");
})
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

// Configure CORS
builder.Services.AddCors(options => {
    options.AddPolicy("AllowFrontend", corsBuilder => {
        var allowedOrigins = builder.Configuration.GetSection("AllowedOrigins").Get<string[]>()
                            ?? new[] { "http://localhost:5010" };

        corsBuilder
            .WithOrigins(allowedOrigins)
            .AllowAnyMethod()
            .AllowAnyHeader()
            .AllowCredentials();
    });
});

// Configure Health Checks
builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy())
    .AddUrlGroup(new Uri($"{builder.Configuration["ServiceUrls:OrderService"]}/health"),
                name: "orders-service",
                failureStatus: HealthStatus.Degraded)
    .AddUrlGroup(new Uri($"{builder.Configuration["ServiceUrls:InventoryService"]}/health"),
                name: "inventory-service",
                failureStatus: HealthStatus.Degraded);

// Configure Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c => {
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "API Gateway Service",
        Version = "v1",
        Description = "API Gateway Service for InsightOps Microservices"
    });
});

var app = builder.Build();

// Configure Error Handling
app.UseExceptionHandler(errorApp => {
    errorApp.Run(async context => {
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/json";

        var error = context.Features.Get<IExceptionHandlerFeature>();
        var logger = errorApp.ApplicationServices.GetRequiredService<ILogger<Program>>();

        logger.LogError(error?.Error, "An unhandled exception occurred");

        var response = new
        {
            StatusCode = context.Response.StatusCode,
            Message = app.Environment.IsDevelopment() ? error?.Error.Message : "An internal error occurred.",
            Details = app.Environment.IsDevelopment() ? error?.Error.StackTrace : null
        };

        await context.Response.WriteAsJsonAsync(response);
    });
});

// Health Checks Configuration
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = async (context, report) => {
        context.Response.ContentType = "application/json";
        var response = new
        {
            status = report.Status.ToString(),
            checks = report.Entries.Select(x => new {
                name = x.Key,
                status = x.Value.Status.ToString(),
                description = x.Value.Description
            })
        };
        await JsonSerializer.SerializeAsync(context.Response.Body, response);
    }
});

// Development Tools
if (app.Environment.IsDevelopment() || app.Environment.EnvironmentName == "Docker")
{
    app.UseSwagger(c => {
        c.RouteTemplate = "swagger/{documentName}/swagger.json";
    });
    app.UseSwaggerUI(c => {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "API Gateway Service V1");
        c.RoutePrefix = "swagger";
    });
}

// Configure Pipeline
app.UseRouting();
app.UseCors("AllowFrontend");

// Use Observability Middleware
app.UseInsightOpsObservability();

// Request Logging Middleware
app.UseSerilogRequestLogging(options => {
    options.MessageTemplate = "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed:0.0000} ms";
    options.GetLevel = (httpContext, elapsed, ex) =>
        ex != null ? LogEventLevel.Error :
        httpContext.Response.StatusCode > 499 ? LogEventLevel.Error :
        elapsed > 500 ? LogEventLevel.Warning :
        LogEventLevel.Information;
});

// Map Endpoints
app.UseEndpoints(endpoints => {
    endpoints.MapControllers();
    endpoints.MapHub<MetricsHub>("/metrics-hub");
    endpoints.MapHealthChecks("/health");
});

// Resilience Pattern Definitions
static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .WaitAndRetryAsync(3, retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)));
}

static IAsyncPolicy<HttpResponseMessage> GetCircuitBreakerPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .CircuitBreakerAsync(5, TimeSpan.FromSeconds(30));
}

try
{
    Log.Information("Starting API Gateway");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "API Gateway terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}
