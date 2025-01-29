using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using OrderService.Repositories;
using OrderService.Data;
using System.Reflection;
using System.Text.Json;
using OrderService.Interfaces;
using OrderService.Services;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
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
    if (ex.TableName == "InventoryItems" || ex.TableName == "Orders")
    {
        await context.Database.MigrateAsync();
    }
}

static async Task ResetDatabase(OrderDbContext context)
{
    await context.Database.ExecuteSqlRawAsync(@"
       DROP SCHEMA IF EXISTS orders CASCADE;
       CREATE SCHEMA orders;
       SET search_path TO orders,public;
   ");
}

static async Task WaitForDatabase(OrderDbContext context, ILogger<Program> logger, int maxRetries = 30)
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
        Title = "Order Service API",
        Version = "v1",
        Description = "Order Service API Description"
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

builder.Services.AddDbContext<OrderDbContext>((serviceProvider, options) =>
{
    var logger = serviceProvider.GetRequiredService<ILogger<OrderDbContext>>();
    var connectionString = builder.Configuration.GetConnectionString("Postgres");
    connectionString = $"{connectionString};SearchPath=orders,public";

    options.UseNpgsql(connectionString, npgsqlOptions =>
    {
        npgsqlOptions.EnableRetryOnFailure(5, TimeSpan.FromSeconds(30), null);
        npgsqlOptions.MigrationsHistoryTable("__EFMigrationsHistory", "orders");
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
   "OrderService",
   options =>
   {
       options.Common.ServiceName = "OrderService";
   });

// Add metrics background service
builder.Services.AddHostedService<MetricsBackgroundService>();

builder.Services.AddHttpClient("OrderService", client =>
{
    var baseUrl = builder.Configuration["ServiceUrls:ApiGateway"] ?? "http://apigateway:7237";
    client.BaseAddress = new Uri(baseUrl);
    client.DefaultRequestHeaders.Add("Accept", "application/json");
    client.Timeout = TimeSpan.FromSeconds(30);
})
.AddPolicyHandler(GetRetryPolicy())
.AddPolicyHandler(GetCircuitBreakerPolicy());

builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<IOrderService, OrderService.Services.OrderService>();
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
    OrderDbContext context = null;

    try
    {
        logger.LogInformation("Starting database initialization...");
        context = services.GetRequiredService<OrderDbContext>();
        await WaitForDatabase(context, logger);
        await context.Database.ExecuteSqlRawAsync("CREATE SCHEMA IF NOT EXISTS orders;");
        await context.Database.ExecuteSqlRawAsync("SET search_path TO orders,public;");

        if (!(await context.Database.CanConnectAsync()))
        {
            await context.Database.EnsureCreatedAsync();
        }

        await context.Database.ExecuteSqlRawAsync(@"
       CREATE TABLE IF NOT EXISTS orders.__EFMigrationsHistory (
           MigrationId character varying(150) NOT NULL,
           ProductVersion character varying(32) NOT NULL,
           CONSTRAINT PK___EFMigrationsHistory PRIMARY KEY (MigrationId)
       );");

        var pendingMigrations = (await context.Database.GetPendingMigrationsAsync()).ToList();
        if (pendingMigrations.Any())
        {
            await context.Database.MigrateAsync();
        }

        var hasData = await context.Orders.AnyAsync();
        if (!hasData)
        {
            await DbInitializer.InitializeAsync(context, logger);
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
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Order Service API V1");
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