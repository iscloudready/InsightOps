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
using FrontendService.Services.Monitoring;
using FrontendService.Extensions;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;

var builder = WebApplication.CreateBuilder(args);

// Configure logging first
builder.Services.AddLogging(loggingBuilder =>
{
    loggingBuilder.ClearProviders();
    loggingBuilder.AddConsole();
    loggingBuilder.AddDebug();
    loggingBuilder.SetMinimumLevel(builder.Environment.IsDevelopment() ?
        LogLevel.Debug : LogLevel.Information);
});

// Configure Serilog based on environment
var lokiUrl = builder.Environment.IsDevelopment()
    ? "http://localhost:3100"
    : "http://loki:3100";

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.WithEnvironmentName()
    .Enrich.WithThreadId()
    .WriteTo.Console(
        outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
    .WriteTo.Http(
        requestUri: $"{lokiUrl}/loki/api/v1/push",
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

// Configure services and logging based on environment
if (builder.Environment.IsDevelopment() || builder.Environment.EnvironmentName == "Docker")
{
    builder.Services.Configure<LoggerFilterOptions>(options =>
    {
        options.MinLevel = LogLevel.Debug;
    });
}

// Add application services
builder.Services.AddApplicationServices(builder.Configuration);

// Configure monitoring endpoints
var tempoEndpoint = builder.Environment.IsDevelopment()
    ? "http://localhost:4317"
    : "http://tempo:4317";

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
    options.ListenAnyIP(5010);
});

// Disable Data Protection warnings
builder.Services.AddDataProtection()
    .DisableAutomaticKeyGeneration();

var app = builder.Build();

// Configure error handling with detailed messages
if (app.Environment.IsDevelopment() || app.Environment.EnvironmentName == "Docker")
{
    app.UseDeveloperExceptionPage();
    app.UseExceptionHandler(errorApp =>
    {
        errorApp.Run(async context =>
        {
            var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
            context.Response.StatusCode = 500;
            context.Response.ContentType = "application/json";

            var exception = context.Features.Get<IExceptionHandlerFeature>();
            if (exception != null)
            {
                logger.LogError(exception.Error, "An unhandled exception occurred");
                await context.Response.WriteAsJsonAsync(new
                {
                    error = "An error occurred.",
                    detail = exception.Error.Message,
                    stackTrace = exception.Error.StackTrace,
                    path = context.Request.Path,
                    timestamp = DateTime.UtcNow
                });
            }
        });
    });
}
else
{
    app.UseExceptionHandler("/Home/Error");
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
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

// Configure endpoints
app.UseEndpoints(endpoints =>
{
    endpoints.MapControllerRoute(
        name: "default",
        pattern: "{controller=Home}/{action=Index}/{id?}");

    endpoints.MapHealthChecks("/health");
    endpoints.MapPrometheusScrapingEndpoint("/metrics");
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