using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
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

var builder = WebApplication.CreateBuilder(args);

// Add after builder initialization
builder.Services.AddApplicationServices(builder.Configuration);

// Configure Serilog based on environment
var lokiUrl = builder.Environment.IsDevelopment()
    ? "http://localhost:3100"
    : "http://loki:3100";

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.WithEnvironmentName()  // Instead of WithMachineName
    .Enrich.WithThreadId()
    .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
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

// Configure HttpClient for API Gateway with environment-specific base URL
var apiGatewayUrl = builder.Environment.IsDevelopment()
    ? "http://localhost:7237"
    : "http://apigateway:80";

// With this enhanced version
builder.Services.AddHttpClient("ApiGateway", client => {
    client.BaseAddress = new Uri(apiGatewayUrl);
    client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
})
.AddTransientHttpErrorPolicy(p =>
    p.WaitAndRetryAsync(3, _ => TimeSpan.FromSeconds(1)))
.AddTransientHttpErrorPolicy(p =>
    p.CircuitBreakerAsync(5, TimeSpan.FromSeconds(30)));

// Configure monitoring endpoints
var tempoEndpoint = builder.Environment.IsDevelopment()
    ? "http://localhost:4317"
    : "http://tempo:4317";

// Configure Health Checks
builder.Services.AddHealthChecks()
    .AddUrlGroup(new Uri($"{apiGatewayUrl}/health"), "api-gateway");

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

builder.Services.AddSingleton<MetricsCollector>();

// Disable Data Protection warnings
builder.Services.AddDataProtection()
    .DisableAutomaticKeyGeneration();

var app = builder.Build();

// Configure error handling
if (app.Environment.IsDevelopment() || app.Environment.EnvironmentName == "Docker")
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Home/Error");
}

app.UseStaticFiles();
app.UseRouting();
app.UseSerilogRequestLogging();

// Configure endpoints
app.UseEndpoints(endpoints =>
{
    endpoints.MapControllerRoute(
        name: "default",
        pattern: "{controller=Home}/{action=Index}/{id?}");

    endpoints.MapHealthChecks("/health");
    endpoints.MapPrometheusScrapingEndpoint("/metrics");
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