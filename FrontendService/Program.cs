using InsightOps.Observability.Extensions;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using FrontendService.Services;

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

// Use centralized observability middleware (includes health checks, metrics, etc.)
app.UseInsightOpsObservability();

// Standard ASP.NET Core middleware
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

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