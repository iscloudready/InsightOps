using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using InventoryService.Repositories;
using InventoryService.Data; // Add this for DbInitializer
using System.Reflection;
using System.Text.Json;
using InventoryService.Services;
using InventoryService.Interfaces;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using InventoryService.Models;
using Npgsql;

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
    options.UseNpgsql(builder.Configuration.GetConnectionString("Postgres"),
        npgsqlOptionsAction: sqlOptions =>
        {
            sqlOptions.EnableRetryOnFailure(
                maxRetryCount: 5,
                maxRetryDelay: TimeSpan.FromSeconds(30),
                errorCodesToAdd: null);
        });
});

// Add InventoryRepository as a scoped service
// In Program.cs for both services
builder.Services.AddScoped<IInventoryRepository, InventoryRepository>();
builder.Services.AddScoped<InventoryService.Services.IInventoryService, InventoryService.Services.InventoryService>();

// Add Authorization services
builder.Services.AddAuthorization();

builder.Services.AddControllers();

builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy());

// Configure Swagger
builder.Services.AddEndpointsApiExplorer();

// Configure HttpClient for the InventoryService
builder.Services.AddHttpClient("InventoryService", client =>
{
    client.BaseAddress = new Uri("http://apigateway:7237");
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
            .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService("InventoryService"));
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

using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();

    try
    {
        logger.LogInformation("Starting inventory database initialization...");
        var context = services.GetRequiredService<InventoryDbContext>();

        // First check database connectivity
        if (!(await context.Database.CanConnectAsync()))
        {
            logger.LogInformation("Database connection not established. Creating database...");
            await context.Database.EnsureCreatedAsync();
        }

        // Special handling for migration history table
        try
        {
            // Try to create migration history table if it doesn't exist
            await context.Database.ExecuteSqlRawAsync(@"
                CREATE TABLE IF NOT EXISTS ""__EFMigrationsHistory"" (
                    ""MigrationId"" character varying(150) NOT NULL,
                    ""ProductVersion"" character varying(32) NOT NULL,
                    CONSTRAINT ""PK___EFMigrationsHistory"" PRIMARY KEY (""MigrationId"")
                );");
        }
        catch (PostgresException pgEx) when (pgEx.SqlState == "42P07" || pgEx.SqlState == "23505")
        {
            logger.LogInformation("Migration history table already exists, continuing with migrations...");
        }

        // Check for pending migrations
        var pendingMigrations = await context.Database.GetPendingMigrationsAsync();
        var pendingMigrationsList = pendingMigrations.ToList();

        if (pendingMigrationsList.Any())
        {
            logger.LogInformation("Found {Count} pending inventory migrations: {@Migrations}",
                pendingMigrationsList.Count,
                pendingMigrationsList);

            try
            {
                await context.Database.MigrateAsync();
                logger.LogInformation("Successfully applied inventory database migrations");
            }
            catch (PostgresException pgEx) when (pgEx.SqlState == "23505")
            {
                // Handle duplicate key violations during migration
                logger.LogWarning("Duplicate key detected during migration. Attempting cleanup...");

                // Try to clean up any existing data
                await context.Database.ExecuteSqlRawAsync(@"
                    DO $$
                    BEGIN
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'InventoryItems') THEN
                            TRUNCATE TABLE ""InventoryItems"" CASCADE;
                        END IF;
                    END $$;");

                // Retry migration
                await context.Database.MigrateAsync();
            }
        }
        else
        {
            logger.LogInformation("No pending migrations found. Inventory database is up to date.");
        }

        // Check if we need to seed data
        var hasData = await context.InventoryItems.AnyAsync();
        if (!hasData)
        {
            logger.LogInformation("Initializing inventory seed data...");

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
                },
                new InventoryItem
                {
                    Name = "Sample Item 3",
                    Quantity = 75,
                    Price = 14.99m,
                    MinimumQuantity = 15,
                    LastRestocked = DateTime.UtcNow
                }
            };

            try
            {
                await context.InventoryItems.AddRangeAsync(items);
                await context.SaveChangesAsync();
                logger.LogInformation("Successfully seeded {Count} inventory items", items.Count);
            }
            catch (DbUpdateException ex) when (ex.InnerException is PostgresException pgEx && pgEx.SqlState == "23505")
            {
                logger.LogWarning("Duplicate items detected during seeding. Skipping seed data.");
            }
        }
        else
        {
            logger.LogInformation("Inventory database already contains data. Skipping seed initialization.");
        }

        // Verify data integrity
        var itemCount = await context.InventoryItems.CountAsync();
        logger.LogInformation("Current inventory contains {Count} items", itemCount);
    }
    catch (PostgresException pgEx)
    {
        logger.LogError(pgEx, "PostgreSQL error during inventory database initialization. Error Code: {ErrorCode}, Detail: {Detail}",
            pgEx.SqlState,
            pgEx.Detail);

        if (pgEx.SqlState == "23505") // Unique violation
        {
            logger.LogError("Schema conflict detected. You may need to reset the database.");
            throw new InvalidOperationException("Schema conflict detected. Please reset the database and try again.", pgEx);
        }
        throw;
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
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Inventory Service API V1");
        c.RoutePrefix = "swagger";
    });
}

app.UseRouting();
app.UseEndpoints(endpoints =>
{
    endpoints.MapControllers();
});

app.Run();