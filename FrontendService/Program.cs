using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry;
using OpenTelemetry.Extensions.Hosting;
using OpenTelemetry.Instrumentation.AspNetCore;
using OpenTelemetry.Instrumentation.Http;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// Load configuration files
builder.Configuration
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

// Add services to the container
builder.Services.AddControllersWithViews();

// Configure HttpClient for API Gateway
builder.Services.AddHttpClient("ApiGateway", client =>
{
    client.BaseAddress = new Uri("http://localhost:5000");
    client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
});

// Configure Health Checks
builder.Services.AddHealthChecks();

// Configure OpenTelemetry for tracing and metrics
builder.Services.AddOpenTelemetry()
    .WithTracing(tracerProviderBuilder =>
    {
        tracerProviderBuilder
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri("http://localhost:4317");
            });
    })
    .WithMetrics(metricProviderBuilder =>
    {
        metricProviderBuilder
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddRuntimeInstrumentation()
            .AddPrometheusExporter();
    });

// Configure Kestrel to use HTTP only
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(80); // HTTP on port 80
});

// Configure Data Protection to use in-memory storage
//builder.Services.AddDataProtection()
//    .SetApplicationName("YourAppName") // Optional: set a shared app name if multiple services need shared data protection keys
//    .PersistKeysToInMemory(); // Store keys in memory to avoid persistence issues in Docker

var app = builder.Build();

// Use the developer exception page in development mode
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}

// Remove HTTPS redirection middleware since we're using HTTP-only
// app.UseHttpsRedirection();

// Enable routing and static file serving if needed
app.UseRouting();
app.UseStaticFiles(); // Serve static files if required

// Configure endpoints
app.UseEndpoints(endpoints =>
{
    endpoints.MapControllerRoute(
        name: "default",
        pattern: "{controller=Home}/{action=Index}/{id?}");
    endpoints.MapHealthChecks("/health");
    endpoints.MapPrometheusScrapingEndpoint("/metrics");
});

// Run the application
app.Run();
