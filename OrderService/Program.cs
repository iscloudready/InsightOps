using Microsoft.EntityFrameworkCore;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using OpenTelemetry.Resources;
using OrderService.Data;
using OrderService.Repositories;

var builder = WebApplication.CreateBuilder(args);

// Configure PostgreSQL Database connection
builder.Services.AddDbContext<OrderDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Postgres")));

// Add OrderRepository as a scoped service
builder.Services.AddScoped<OrderRepository>();

// Configure Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

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

// Map Prometheus endpoint for scraping metrics
app.MapPrometheusScrapingEndpoint("/metrics");

// Enable Swagger in development mode
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();
