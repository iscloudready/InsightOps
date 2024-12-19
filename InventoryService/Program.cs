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

static async Task WaitForDatabase(InventoryDbContext context, ILogger logger, int maxRetries = 30)
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
    InventoryDbContext context = null;  // Declare context outside try block

    try
    {
        logger.LogInformation("Starting inventory database initialization...");
        context = services.GetRequiredService<InventoryDbContext>();

        // Create schema and set search path with better error handling
        await context.Database.ExecuteSqlRawAsync("CREATE SCHEMA IF NOT EXISTS inventory;");
        await context.Database.ExecuteSqlRawAsync("SET search_path TO inventory,public;");

        // Create migration history table without trying to move data
        try
        {
            await context.Database.ExecuteSqlRawAsync(@"
            CREATE TABLE IF NOT EXISTS inventory.__EFMigrationsHistory (
                MigrationId character varying(150) NOT NULL,
                ProductVersion character varying(32) NOT NULL,
                CONSTRAINT PK___EFMigrationsHistory PRIMARY KEY (MigrationId)
            );");
        }
        catch (PostgresException pgEx) when (pgEx.SqlState == "42P07")
        {
            logger.LogInformation("Migration history table already exists");
        }

        // First check database connectivity
        if (!(await context.Database.CanConnectAsync()))
        {
            logger.LogInformation("Database connection not established. Creating database...");
            await context.Database.EnsureCreatedAsync();
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
                // Ensure we're in the correct schema before migration
                await context.Database.ExecuteSqlRawAsync("SET search_path TO inventory;");
                await context.Database.MigrateAsync();
                logger.LogInformation("Successfully applied inventory database migrations");
            }
            catch (PostgresException pgEx) when (pgEx.SqlState == "23505")
            {
                // Handle duplicate key violations during migration
                logger.LogWarning("Duplicate key detected during migration. Attempting cleanup...");

                // Try to clean up any existing data with correct schema
                await context.Database.ExecuteSqlRawAsync(@"
                DO $$
                BEGIN
                    IF EXISTS (
                        SELECT 1 
                        FROM information_schema.tables 
                        WHERE table_schema = 'inventory' 
                        AND table_name = 'InventoryItems'
                    ) THEN
                        TRUNCATE TABLE inventory.""InventoryItems"" CASCADE;
                    END IF;
                END $$;");

                await context.Database.MigrateAsync();
            }
        }

        // Check if we need to seed data
        var hasData = await context.InventoryItems.AnyAsync();  //await context.Database.ExecuteSqlRawAsync(@"
        //SELECT EXISTS (
        //    SELECT 1 FROM inventory.""InventoryItems"" LIMIT 1
        //)");

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

        // Verify data integrity with explicit schema
        var itemCount = await context.Database.ExecuteSqlRawAsync(@"
        SELECT COUNT(*) FROM inventory.""InventoryItems""");
        logger.LogInformation("Current inventory contains {Count} items", itemCount);
    }
    catch (PostgresException pgEx)
    {
        logger.LogError(pgEx, "PostgreSQL error during inventory database initialization. Error Code: {ErrorCode}, Detail: {Detail}",
            pgEx.SqlState,
            pgEx.Detail);

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
            case "42P01": // Relation does not exist
                logger.LogWarning("Relations not found, attempting to create...");
                await context.Database.MigrateAsync();
                break;
            default:
                throw;
        }
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