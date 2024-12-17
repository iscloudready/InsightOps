using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OrderService.Repositories;
using OrderService.Data; // Add this for DbInitializer
using System.Reflection;
using System.Text.Json;
using OrderService.Interfaces;
using OrderService.Services;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Npgsql;
using Polly;

static async Task HandleDuplicateKeyViolation(DbContext context, PostgresException ex)
{
    // Add specific handling based on the table/constraint involved
    if (ex.TableName == "InventoryItems" || ex.TableName == "Orders")
    {
        await context.Database.MigrateAsync();
    }
    else
    {
        //throw; // Rethrow if we can't handle this specific violation
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
static async Task WaitForDatabase(OrderDbContext context, ILogger logger, int maxRetries = 30)
{
    for (int i = 0; i < maxRetries; i++)
    {
        try
        {
            await context.Database.CanConnectAsync();
            logger.LogInformation("Successfully connected to database");
            return;
        }
        catch (PostgresException ex) when (ex.SqlState == "57P03") // database is starting up
        {
            logger.LogWarning("Database is starting up. Attempt {Attempt} of {MaxRetries}. Waiting 2 seconds...",
                i + 1, maxRetries);
            await Task.Delay(2000); // Wait 2 seconds before retrying
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

builder.Configuration
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy());

// Configure PostgreSQL Database connection with retry policy
builder.Services.AddDbContext<OrderDbContext>((serviceProvider, options) =>
{
    var logger = serviceProvider.GetRequiredService<ILogger<OrderDbContext>>();
    var connectionString = builder.Configuration.GetConnectionString("Postgres");

    // Add default schema to connection string
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

// Add OrderRepository as a scoped service
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<OrderService.Services.IOrderService, OrderService.Services.OrderService>();

// Add Authorization services
builder.Services.AddAuthorization();

builder.Services.AddControllers();

builder.Services.AddHealthChecks();

// Configure Swagger
builder.Services.AddEndpointsApiExplorer();

// Configure HttpClient for the OrderService
builder.Services.AddHttpClient("OrderService", client =>
{
    client.BaseAddress = new Uri("http://localhost:5000");
});

// Add OpenTelemetry for both Metrics and Tracing
builder.Services.AddOpenTelemetry()
    .WithTracing(tracerProviderBuilder =>
    {
        tracerProviderBuilder
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri("http://localhost:4317"); // Adjust based on OTLP endpoint (e.g., Tempo)
            })
            .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService("OrderService"));
    })
    .WithMetrics(metricProviderBuilder =>
    {
        metricProviderBuilder
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddRuntimeInstrumentation()
            .AddPrometheusExporter();
    });

// Build and configure the app
var app = builder.Build();

app.MapHealthChecks("/health", new HealthCheckOptions
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

// Enhanced database initialization with migrations and seeding
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();
    OrderDbContext context = null;  // Declare context outside try block

    try
    {
        logger.LogInformation("Starting database initialization...");
        context = services.GetRequiredService<OrderDbContext>();

        // Wait for database to be ready
        await WaitForDatabase(context, logger);

        // Create schema and make it part of search path
        await context.Database.ExecuteSqlRawAsync("CREATE SCHEMA IF NOT EXISTS orders;");
        await context.Database.ExecuteSqlRawAsync("SET search_path TO orders,public;");

        // First check database connectivity
        if (!(await context.Database.CanConnectAsync()))
        {
            logger.LogInformation("Database connection not established. Creating database...");
            await context.Database.EnsureCreatedAsync();
        }

        // Move migration history table to orders schema
        await context.Database.ExecuteSqlRawAsync(@"
        CREATE TABLE IF NOT EXISTS orders.__EFMigrationsHistory (
            MigrationId character varying(150) NOT NULL,
            ProductVersion character varying(32) NOT NULL,
            CONSTRAINT PK___EFMigrationsHistory PRIMARY KEY (MigrationId)
        );");

        // Check for pending migrations
        var pendingMigrations = await context.Database.GetPendingMigrationsAsync();
        var pendingMigrationsList = pendingMigrations.ToList();

        if (pendingMigrationsList.Any())
        {
            logger.LogInformation("Found {Count} pending migrations: {@Migrations}",
                pendingMigrationsList.Count,
                pendingMigrationsList);
            await context.Database.MigrateAsync();
            logger.LogInformation("Successfully applied pending migrations");
        }
        else
        {
            logger.LogInformation("No pending migrations found. Database is up to date.");
        }

        // Check if we need to seed data
        var hasData = await context.Orders.AnyAsync();
        if (!hasData)
        {
            logger.LogInformation("Initializing seed data...");
            await DbInitializer.InitializeAsync(context, logger);
            logger.LogInformation("Seed data initialization completed");
        }
        else
        {
            logger.LogInformation("Database already contains data. Skipping seed initialization.");
        }

        logger.LogInformation("Database initialization completed successfully");
    }
    catch (PostgresException pgEx)
    {
        logger.LogError(pgEx, "PostgreSQL error during database initialization. Error Code: {ErrorCode}, Detail: {Detail}",
            pgEx.SqlState,
            pgEx.Detail);

        if (context != null)
        {

            switch (pgEx.SqlState)
            {
                case "42P07": // Table already exists
                    logger.LogInformation("Schema objects already exist, continuing with migrations...");
                    await context.Database.MigrateAsync();
                    break;
                case "23505": // Unique violation
                    logger.LogWarning("Duplicate key detected during initialization, attempting recovery...");
                    await HandleDuplicateKeyViolation(context, pgEx);
                    break;
                case "42P06": // Schema already exists
                    logger.LogInformation("Schema already exists, continuing...");
                    break;
                case "57P03": // database is starting up
                    logger.LogWarning("Database is starting up, waiting...");
                    await WaitForDatabase(context, logger);
                    break;
                default:
                    throw; // Rethrow unknown Postgres errors
            }
        }
        else
        {
            throw;
        }
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "An unexpected error occurred while initializing the inventory database: {Message}", ex.Message);
        throw;
    }
}

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

// Map Prometheus endpoint for scraping metrics
app.MapPrometheusScrapingEndpoint("/metrics");

// Map health check endpoint
app.MapHealthChecks("/health");

// Configure the HTTP request pipeline.
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
app.UseEndpoints(endpoints =>
{
    endpoints.MapControllers();
});

app.Run();