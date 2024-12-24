using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using System.Reflection;
using System.Text.Json;
using InventoryService.Repositories;
using InventoryService.Data;
using InventoryService.Services;
using InventoryService.Interfaces;
using InventoryService.HealthChecks;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;
using Serilog;
using InsightOps.Observability.Extensions;
using InsightOps.Observability.Options;
using InsightOps.Observability.SignalR;
using Microsoft.AspNetCore.SignalR;
using InventoryService.Models;

var builder = WebApplication.CreateBuilder(args);

// Configure swagger first
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Inventory Service API",
        Version = "v1",
        Description = "Inventory Service API Description"
    });
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    c.IncludeXmlComments(xmlPath);
});

builder.Configuration
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

// Configure PostgreSQL Database connection with retry policy
builder.Services.AddDbContext<InventoryDbContext>(options =>
{
    var connectionString = builder.Configuration.GetConnectionString("Postgres");
    connectionString = $"{connectionString};SearchPath=inventory,public";

    options.UseNpgsql(connectionString,
        npgsqlOptionsAction: sqlOptions =>
        {
            sqlOptions.EnableRetryOnFailure(
                maxRetryCount: 5,
                maxRetryDelay: TimeSpan.FromSeconds(30),
                errorCodesToAdd: null);
            sqlOptions.MigrationsHistoryTable("__EFMigrationsHistory", "inventory");
        });
});

// Register Observability Services
builder.Services.Configure<ObservabilityOptions>(
    builder.Configuration.GetSection("Observability"));

// Register SignalR services (Fix for IHubContext)
builder.Services.AddSignalR();

// Register MetricsHub and Background Service
builder.Services.AddSingleton<MetricsHub>();
builder.Services.AddHostedService<MetricsBackgroundService>();

// Add Centralized Observability
builder.Services.AddInsightOpsObservability(
    builder.Configuration,
    "InventoryService",
    options => {
        options.Common.ServiceName = "InventoryService";
        options.Common.MetricsEndpoint = "/metrics";
        options.Common.HealthCheckEndpoint = "/health";
    });

// Add InventoryRepository as a scoped service
builder.Services.AddScoped<IInventoryRepository, InventoryRepository>();
builder.Services.AddScoped<InventoryService.Services.IInventoryService, InventoryService.Services.InventoryService>();

// Authorization
builder.Services.AddAuthorization();
builder.Services.AddControllers();

// Health Checks
builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy())
    .AddCheck<DatabaseHealthCheck>("database-health");

// Configure Swagger
builder.Services.AddEndpointsApiExplorer();

var app = builder.Build();

// Initialize Database
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();
    var context = services.GetRequiredService<InventoryDbContext>();

    try
    {
        logger.LogInformation("Starting inventory database initialization...");

        await context.Database.MigrateAsync();
        logger.LogInformation("Database initialization completed successfully");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Database initialization failed");
        throw;
    }
}

// Configure Error Handling
app.UseExceptionHandler(errorApp =>
{
    errorApp.Run(async context =>
    {
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/json";
        var error = context.Features.Get<IExceptionHandlerFeature>();
        if (error != null)
        {
            await context.Response.WriteAsJsonAsync(new { error = "An error occurred." });
        }
    });
});

// Development tools (Swagger)
if (app.Environment.IsDevelopment() || app.Environment.EnvironmentName == "Docker")
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Inventory Service API V1");
        c.RoutePrefix = "swagger";
    });
}

// Configure Middleware Pipeline
app.UseRouting();
app.UseInsightOpsObservability();
app.UseAuthorization();

// Map Endpoints
app.UseEndpoints(endpoints =>
{
    endpoints.MapControllers();
    endpoints.MapHub<MetricsHub>("/metrics-hub");  // SignalR Metrics Hub
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

// Run the App
try
{
    Log.Information("Starting Inventory Service");
    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Inventory Service terminated unexpectedly");
    throw;
}
finally
{
    Log.CloseAndFlush();
}
