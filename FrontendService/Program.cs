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

var builder = WebApplication.CreateBuilder(args);

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

// Configure MVC
builder.Services.AddControllersWithViews()
    .AddJsonOptions(options =>
    {
        var jsonConfig = builder.Configuration.GetSection("Application:JsonOptions").Get<InsightOps.Observability.Options.JsonSerializerOptions>();
        options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
        options.JsonSerializerOptions.PropertyNamingPolicy = null;
    });

builder.Services.AddDataProtection()
    .PersistKeysToFileSystem(new DirectoryInfo("/app/Keys"))
    .SetApplicationName("InsightOps");

var app = builder.Build();

// Configure error handling
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Home/Error");
}

// Configure the HTTP request pipeline
app.UseRouting();
app.UseStaticFiles();
app.UseAuthorization();

// Use centralized observability middleware
app.UseInsightOpsObservability();

// Configure endpoints
app.UseEndpoints(endpoints =>
{
    // Map SignalR hub
    endpoints.MapHub<MetricsHub>("/metrics-hub");

    // Map controllers
    endpoints.MapControllerRoute(
        name: "default",
        pattern: "{controller=Home}/{action=Index}/{id?}");

    // Map health checks (if not handled by UseInsightOpsObservability)
    endpoints.MapHealthChecks("/health");
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