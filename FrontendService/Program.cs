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

var builder = WebApplication.CreateBuilder(args);

// Add centralized observability with all configurations
builder.Services.AddInsightOpsObservability(
    builder.Configuration,
    "FrontendService",
    options =>
    {
        // Any service-specific overrides can go here if needed
        options.Common.ServiceName = "FrontendService";
    });

// Explicitly register required services for MetricsBackgroundService
builder.Services.Configure<ObservabilityOptions>(builder.Configuration.GetSection("Observability"));
builder.Services.AddSingleton<RealTimeMetricsCollector>();
builder.Services.AddSingleton<SystemMetricsCollector>();

// Add SignalR
builder.Services.AddSignalR(options =>
{
    var signalRConfig = builder.Configuration.GetSection("SignalR").Get<SignalROptions>();
    options.EnableDetailedErrors = signalRConfig?.DetailedErrors ?? true;
    options.MaximumReceiveMessageSize = signalRConfig?.MaximumReceiveMessageSize ?? 102400;
});

// Register BackgroundService
builder.Services.AddHostedService<MetricsBackgroundService>();

// Register application-specific services
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IInventoryService, InventoryService>();

// Add controllers with default JSON options (handled by observability stack)
builder.Services.AddControllersWithViews();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
}
else
{
    app.UseExceptionHandler("/Home/Error");
}

// Ensure proper middleware order
app.UseRouting();

// Use centralized observability middleware (includes health checks, metrics, etc.)
app.UseInsightOpsObservability();

// Standard ASP.NET Core middleware
app.UseStaticFiles();
//app.UseRouting();
// app.UseAuthentication();
app.UseAuthorization();

// Map SignalR hub
app.MapHub<MetricsHub>("/metrics-hub");

// Map default controller route
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