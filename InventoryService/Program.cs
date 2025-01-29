using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using InventoryService.Repositories;
using InventoryService.Data;
using System.Reflection;
using System.Text.Json;
using InventoryService.Services;
using InventoryService.Interfaces;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using InventoryService.Models;
using Npgsql;
using InsightOps.Observability.Extensions;
using InsightOps.Observability.Metrics;
using InsightOps.Observability.Options;
using InsightOps.Observability.SignalR;
using Polly;
using Polly.Extensions.Http;
using Polly.Timeout;
using Serilog;
using Microsoft.Extensions.Logging;
using ILogger = Microsoft.Extensions.Logging.ILogger;

static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
{
    return HttpPolicyExtensions
        .HandleTransientHttpError()
        .Or<TimeoutRejectedException>()
        .WaitAndRetryAsync(
            retryCount: 3,
            sleepDurationProvider: retryAttempt =>
                TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
            onRetry: (exception, timeSpan, retryCount, context) =>
            {
                Log.Warning(
                    "Retry {RetryCount} after {RetryTime}s delay due to {ExceptionType}: {ExceptionMessage}",
                    retryCount,
                    timeSpan.TotalSeconds,
                    exception.Exception?.GetType().Name,
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
                    "Circuit breaker opened for {DurationSec}s due to: {ExceptionMessage}",
                    duration.TotalSeconds,
                    exception.Exception?.Message);
            },
            onReset: () =>
            {
                Log.Information("Circuit breaker reset");
            });
}

static async Task HandleDuplicateKeyViolation(DbContext context, PostgresException ex)
{
    if (ex.TableName == "InventoryItems")
    {
        await context.Database.MigrateAsync();
    }
}

static async Task WaitForDatabase(InventoryDbContext context, ILogger<Program> logger, int maxRetries = 30)
{
    for (int i = 0; i < maxRetries; i++)
    {
        try
        {
            await context.Database.CanConnectAsync();
            logger.LogInformation("Successfully connected to database");
            return;
        }
        catch (PostgresException ex) when (ex.SqlState == "57P03")
        {
            logger.LogWarning("Database is starting up. Attempt {Attempt} of {MaxRetries}. Waiting 2 seconds...",
                i + 1, maxRetries);
            await Task.Delay(2000);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error while waiting for database");
            throw;
        }
    }
    throw new TimeoutException("Database did not become available in time");
}

var builder = WebApplication.CreateBuilder(args);

// Configure Serilog first
builder.Host.UseSerilog((context, config) =>
   config.ReadFrom.Configuration(context.Configuration));

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

builder.Services.AddDbContext<InventoryDbContext>((serviceProvider, options) =>
{
    var logger = serviceProvider.GetRequiredService<ILogger<InventoryDbContext>>();
    var connectionString = builder.Configuration.GetConnectionString("Postgres");
    connectionString = $"{connectionString};SearchPath=inventory,public";

    options.UseNpgsql(connectionString, npgsqlOptions =>
    {
        npgsqlOptions.EnableRetryOnFailure(5, TimeSpan.FromSeconds(30), null);
        npgsqlOptions.MigrationsHistoryTable("__EFMigrationsHistory", "inventory");
    });
});

// Register Observability Services
builder.Services.Configure<ObservabilityOptions>(builder.Configuration.GetSection("Observability"));
builder.Services.AddSingleton<RealTimeMetricsCollector>();
builder.Services.AddSingleton<SystemMetricsCollector>();

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
   "InventoryService",
   options =>
   {
       options.Common.ServiceName = "InventoryService";
   });

// Add metrics background service
builder.Services.AddHostedService<MetricsBackgroundService>();

builder.Services.AddHttpClient("InventoryService", client =>
{
    var baseUrl = builder.Configuration["ServiceUrls:ApiGateway"] ?? "http://apigateway:7237";
    client.BaseAddress = new Uri(baseUrl);
    client.DefaultRequestHeaders.Add("Accept", "application/json");
    client.Timeout = TimeSpan.FromSeconds(30);
})
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

builder.Services.AddScoped<IInventoryRepository, InventoryRepository>();
builder.Services.AddScoped<IInventoryService, InventoryService.Services.InventoryService>();
builder.Services.AddControllers();
builder.Services.AddAuthorization();

builder.Services.AddHealthChecks()
   .AddUrlGroup(
       new Uri($"{builder.Configuration["ServiceUrls:ApiGateway"]}/health"),
       name: "apigateway-check",
       failureStatus: HealthStatus.Degraded,
       timeout: TimeSpan.FromSeconds(5));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();
    InventoryDbContext context = null;

    try
    {
        logger.LogInformation("Starting database initialization...");
        context = services.GetRequiredService<InventoryDbContext>();
        await WaitForDatabase(context, logger);
        await context.Database.ExecuteSqlRawAsync("CREATE SCHEMA IF NOT EXISTS inventory;");
        await context.Database.ExecuteSqlRawAsync("SET search_path TO inventory,public;");

        if (!(await context.Database.CanConnectAsync()))
        {
            await context.Database.EnsureCreatedAsync();
        }

        await context.Database.ExecuteSqlRawAsync(@"
       CREATE TABLE IF NOT EXISTS inventory.__EFMigrationsHistory (
           MigrationId character varying(150) NOT NULL,
           ProductVersion character varying(32) NOT NULL,
           CONSTRAINT PK___EFMigrationsHistory PRIMARY KEY (MigrationId)
       );");

        var pendingMigrations = (await context.Database.GetPendingMigrationsAsync()).ToList();
        if (pendingMigrations.Any())
        {
            await context.Database.MigrateAsync();
        }

        if (!await context.InventoryItems.AnyAsync())
        {
            var items = new List<InventoryItem>
           {
               new InventoryItem
               {
                   Name = "Sample Item 1",
                   Quantity = 100,
                   Price = 9.99m,
                   MinimumQuantity = 20,
                   LastRestocked = DateTime.UtcNow
               },
               new InventoryItem
               {
                   Name = "Sample Item 2",
                   Quantity = 50,
                   Price = 19.99m,
                   MinimumQuantity = 10,
                   LastRestocked = DateTime.UtcNow
               }
           };

            await context.InventoryItems.AddRangeAsync(items);
            await context.SaveChangesAsync();
        }
    }
    catch (PostgresException pgEx)
    {
        logger.LogError(pgEx, "PostgreSQL error during initialization");
        if (context != null)
        {
            switch (pgEx.SqlState)
            {
                case "42P07":
                case "23505":
                    await HandleDuplicateKeyViolation(context, pgEx);
                    break;
                case "42P06":
                    logger.LogInformation("Schema already exists");
                    break;
                case "57P03":
                    await WaitForDatabase(context, logger);
                    break;
                default:
                    throw;
            }
        }
        else throw;
    }
}

if (app.Environment.IsDevelopment() || app.Environment.EnvironmentName == "Docker")
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Inventory Service API V1");
        c.RoutePrefix = "swagger";
    });
}

app.UseRouting();
app.UseInsightOpsObservability();
app.UseAuthorization();

app.UseEndpoints(endpoints =>
{
    endpoints.MapControllers();
    endpoints.MapHub<MetricsHub>("/metrics-hub");
    endpoints.MapHealthChecks("/health", new HealthCheckOptions
    {
        ResponseWriter = async (context, report) =>
        {
            context.Response.ContentType = "application/json";
            var response = new
            {
                status = report.Status.ToString(),
                totalDuration = report.TotalDuration.TotalMilliseconds,
                checks = report.Entries.Select(x => new
                {
                    name = x.Key,
                    status = x.Value.Status.ToString(),
                    duration = x.Value.Duration.TotalMilliseconds,
                    description = x.Value.Description,
                    error = x.Value.Exception?.Message
                }).ToList()
            };

            var options = new System.Text.Json.JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
            };

            await System.Text.Json.JsonSerializer.SerializeAsync(context.Response.Body, response, options);
        }
    });
});

try
{
    Log.Information("Starting InventoryService...");
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