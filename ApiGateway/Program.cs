using Microsoft.OpenApi.Models;
using Microsoft.AspNetCore.Builder;
using OpenTelemetry;
using OpenTelemetry.Extensions.Hosting;
using OpenTelemetry.Instrumentation.AspNetCore;
using OpenTelemetry.Instrumentation.Http;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using System.Reflection;
using System.Text.Json;
using Polly;
using Polly.Extensions.Http;
using Serilog;
using Serilog.Events;
using Microsoft.AspNetCore.Diagnostics;

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

// Configure Services
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    });

// Configure HTTP Clients with Resilience Patterns
builder.Services.AddHttpClient("OrderService", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["ServiceUrls:OrderService"] ?? "http://orderservice:5012");
    client.DefaultRequestHeaders.Add("Accept", "application/json");
})
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

builder.Services.AddHttpClient("InventoryService", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["ServiceUrls:InventoryService"] ?? "http://inventoryservice:5013");
    client.DefaultRequestHeaders.Add("Accept", "application/json");
})
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", corsBuilder =>
    {
        // Safely retrieve AllowedOrigins from configuration
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
    .AddUrlGroup(new Uri($"{builder.Configuration["ServiceUrls:OrderService"]}/health"), name: "orders-service")
    .AddUrlGroup(new Uri($"{builder.Configuration["ServiceUrls:InventoryService"]}/health"), name: "inventory-service");

// Configure Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "API Gateway Service",
        Version = "v1",
        Description = "API Gateway Service for InsightOps Microservices"
    });
});

// Configure OpenTelemetry
builder.Services.AddOpenTelemetry()
    .WithTracing(tracerProviderBuilder =>
    {
        tracerProviderBuilder
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri("http://tempo:4317");
            })
            .SetResourceBuilder(
                ResourceBuilder.CreateDefault()
                    .AddService("ApiGateway")
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

var app = builder.Build();

// Configure Error Handling
app.UseExceptionHandler(errorApp =>
{
    errorApp.Run(async context =>
    {
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

// Configure Development Tools
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

// Configure Middleware Pipeline
app.UseSerilogRequestLogging(options =>
{
    options.MessageTemplate = "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed:0.0000} ms";
    options.GetLevel = (httpContext, elapsed, ex) =>
        ex != null ? LogEventLevel.Error :
        httpContext.Response.StatusCode > 499 ? LogEventLevel.Error :
        elapsed > 500 ? LogEventLevel.Warning :
        LogEventLevel.Information;
});

app.UseRouting();
app.UseCors("AllowFrontend");

// Map Endpoints
app.UseEndpoints(endpoints =>
{
    endpoints.MapControllers();
    endpoints.MapHealthChecks("/health");
    endpoints.MapPrometheusScrapingEndpoint("/metrics");
});

// Resilience Pattern Definitions
static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .WaitAndRetryAsync(
            3,
            retryAttempt => TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
            onRetry: (exception, timeSpan, retryCount, context) =>
            {
                Log.Warning(
                    "Retry {RetryCount} after {RetryTime}s delay due to {ExceptionMessage}",
                    retryCount,
                    timeSpan.TotalSeconds,
                    exception.Exception?.Message);
            });
}

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
                    "Circuit breaker opened for {DurationSeconds}s due to {ExceptionMessage}",
                    duration.TotalSeconds,
                    exception?.Exception?.Message);
            },
            onReset: () =>
            {
                Log.Information("Circuit breaker reset");
            });
}

app.Run();