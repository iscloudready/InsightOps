using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OrderService.Repositories;
using OrderService.Data;
using System.Reflection;
using System.Text.Json;
using OrderService.Interfaces;
using OrderService.Services;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Npgsql;
using Polly;
using InsightOps.Observability.Extensions;
using InsightOps.Observability.Options;
using InsightOps.Observability.SignalR;
using Microsoft.AspNetCore.SignalR;
using Serilog;

static async Task WaitForDatabase(OrderDbContext context, Microsoft.Extensions.Logging.ILogger<Program> logger, int maxRetries = 30)
{
    for (int i = 0; i < maxRetries; i++)
    {
        try
        {
            // Attempt to connect to the database
            await context.Database.CanConnectAsync();
            logger.LogInformation("Successfully connected to the database.");
            return;
        }
        catch (PostgresException ex) when (ex.SqlState == "57P03")  // Database is starting up
        {
            logger.LogWarning("Database is starting up. Attempt {Attempt} of {MaxRetries}. Waiting 2 seconds...",
                i + 1, maxRetries);
            await Task.Delay(2000);  // Wait for 2 seconds before retrying
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error while waiting for the database to become available.");
            throw;
        }
    }

    throw new TimeoutException("Database did not become available within the specified retries.");
}


var builder = WebApplication.CreateBuilder(args);

// Configure swagger first
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Order Service API",
        Version = "v1",
        Description = "Order Service API Description"
    });
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    c.IncludeXmlComments(xmlPath);
});

// Configure appsettings
builder.Configuration
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

// Configure PostgreSQL Database connection with retry policy
builder.Services.AddDbContext<OrderDbContext>((serviceProvider, options) =>
{
    var logger = serviceProvider.GetRequiredService<Microsoft.Extensions.Logging.ILogger<OrderDbContext>>();
    var connectionString = builder.Configuration.GetConnectionString("Postgres");

    connectionString = $"{connectionString};SearchPath=orders,public";

    options.UseNpgsql(connectionString, npgsqlOptions =>
    {
        npgsqlOptions.EnableRetryOnFailure(
            maxRetryCount: 5,
            maxRetryDelay: TimeSpan.FromSeconds(30),
            errorCodesToAdd: null);
        npgsqlOptions.MigrationsHistoryTable("__EFMigrationsHistory", "orders");
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
    "OrderService",
    options => {
        options.Common.ServiceName = "OrderService";
        options.Common.MetricsEndpoint = "/metrics";
        options.Common.HealthCheckEndpoint = "/health";
    });

// Register Services
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<OrderService.Services.IOrderService, OrderService.Services.OrderService>();

// Authorization
builder.Services.AddAuthorization();
builder.Services.AddControllers();

// Health Checks
builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy());

// Configure Swagger
builder.Services.AddEndpointsApiExplorer();

var app = builder.Build();

// Initialize Database
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<Microsoft.Extensions.Logging.ILogger<Program>>();
    var context = services.GetRequiredService<OrderDbContext>();

    try
    {
        logger.LogInformation("Starting order database initialization...");

        // Wait for database to be ready
        await WaitForDatabase(context, logger);

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
        context.Response.StatusCode = 500;
        context.Response.ContentType = "application/json";
        var error = context.Features.Get<IExceptionHandlerFeature>();
        if (error != null)
        {
            await context.Response.WriteAsync(
                JsonSerializer.Serialize(new { error = "An error occurred." }));
        }
    });
});

// Development tools (Swagger)
if (app.Environment.IsDevelopment() || app.Environment.EnvironmentName == "Docker")
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Order Service API V1");
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
    endpoints.MapHub<MetricsHub>("/metrics-hub"); // Map SignalR Hub
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
    Log.Information("Starting OrderService...");
    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application failed to start");
    throw;
}
finally
{
    Log.CloseAndFlush();
}
