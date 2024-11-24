// InsightOps.Observability/Extensions/ObservabilityExtensions.cs
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using Serilog;
using Serilog.Events;
using InsightOps.Observability.Options;
//using InsightOps.Observability.HealthChecks;
using OpenTelemetry.Extensions.Hosting;
using InsightOps.Observability.Metrics;
using InsightOps.Observability.BackgroundServices;
using Microsoft.Extensions.Diagnostics.Metrics;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Exporter;
using Serilog.Extensions.Logging;

namespace InsightOps.Observability.Extensions;

public static class ObservabilityExtensions
{
    public static IServiceCollection AddInsightOpsObservability(
        this IServiceCollection services,
        IConfiguration configuration,
        string serviceName,
        Action<ObservabilityOptions>? configureOptions = null)
    {
        // Load and validate configuration
        var environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Development";
        var options = new ObservabilityOptions();
        configuration.GetSection("Observability").Bind(options);
        configureOptions?.Invoke(options);

        var envOptions = environment == "Development" ? options.Development : options.Docker;

        if (!Enum.TryParse<AppEnvironment>(environment, true, out var parsedEnvironment))
        {
            parsedEnvironment = AppEnvironment.Development; // Default if parsing fails
        }

        options.Common.ServiceName = serviceName;
        options.Common.Environment = parsedEnvironment;

        // Register options
        services.Configure<ObservabilityOptions>(opt =>
        {
            opt = options;
        });

        // Configure OpenTelemetry
        ConfigureOpenTelemetry(services, envOptions, options.Common);

        // Configure Serilog
        ConfigureSerilog(services, envOptions, options.Common);

        // Configure Metrics Collection
        ConfigureMetrics(services, options.Common);

        // Configure Health Checks
        ConfigureHealthChecks(services, envOptions);

        return services;
    }

    private static void ConfigureOpenTelemetry(
        IServiceCollection services,
        EnvironmentOptions envOptions,
        CommonOptions commonOptions)
    {
        services.AddOpenTelemetry()
            .WithTracing(builder =>
            {
                builder
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddOtlpExporter(options =>
                    {
                        if (string.IsNullOrEmpty(envOptions.Infrastructure.TempoEndpoint))
                        {
                            throw new InvalidOperationException("TempoEndpoint is not configured in EnvironmentOptions.");
                        }
                        options.Endpoint = new Uri(envOptions.Infrastructure.TempoEndpoint);
                    })
                    .SetResourceBuilder(
                        ResourceBuilder.CreateDefault()
                            .AddService(commonOptions.ServiceName)
                            .AddTelemetrySdk()
                            .AddAttributes(new Dictionary<string, object>
                            {
                                ["environment"] = commonOptions.Environment.ToString(),
                                ["service.version"] = GetServiceVersion()
                            }));
            })
            .WithMetrics(builder =>
            {
                builder
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation()
                    .AddPrometheusExporter((PrometheusAspNetCoreOptions options) =>
                    {
                        if (string.IsNullOrEmpty(commonOptions.MetricsEndpoint))
                        {
                            throw new InvalidOperationException("MetricsEndpoint is not configured in CommonOptions.");
                        }
                        options.ScrapeEndpointPath = commonOptions.MetricsEndpoint;
                    });
            });
    }

    private static void ConfigureSerilog(
        IServiceCollection services,
        EnvironmentOptions envOptions,
        CommonOptions commonOptions)
    {
        // Build the Serilog logger
        var loggerConfig = new LoggerConfiguration()
            .MinimumLevel.Information()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
            .MinimumLevel.Override("System", LogEventLevel.Warning)
            .Enrich.FromLogContext()
            .Enrich.WithProperty("service", commonOptions.ServiceName)
            .Enrich.WithProperty("environment", commonOptions.Environment)
            .WriteTo.Console(
                outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties}{NewLine}{Exception}")
            .WriteTo.Http(
                requestUri: $"{envOptions.Infrastructure.LokiUrl}/loki/api/v1/push",
                queueLimitBytes: null);

        if (commonOptions.EnableDetailedMetrics)
        {
            loggerConfig.MinimumLevel.Debug();
        }

        Log.Logger = loggerConfig.CreateLogger();

        // Add Serilog as the logging provider
        services.AddSingleton<ILoggerFactory>(sp => new SerilogLoggerFactory(Log.Logger));
        services.AddLogging(builder =>
        {
            builder.ClearProviders(); // Remove default providers
            builder.AddSerilog(Log.Logger, dispose: true);
        });
    }


    private static void ConfigureMetrics(
        IServiceCollection services,
        CommonOptions commonOptions)
    {
        services.AddSingleton<RealTimeMetricsCollector>();
        services.AddSingleton<SystemMetricsCollector>();
        services.AddHostedService<MetricsBackgroundService>();

        services.Configure<Options.MetricsOptions>(options =>
        {
            options.Interval = TimeSpan.FromSeconds(commonOptions.MetricsInterval);
            options.RetentionDays = commonOptions.RetentionDays;
            options.EnableDetailedMetrics = commonOptions.EnableDetailedMetrics;
        });
    }

    private static void ConfigureHealthChecks(IServiceCollection services, EnvironmentOptions envOptions)
    {
        var healthChecks = services.AddHealthChecks();

        // Add infrastructure health checks
        if (!string.IsNullOrWhiteSpace(envOptions.Infrastructure.PrometheusEndpoint) &&
            Uri.TryCreate($"{envOptions.Infrastructure.PrometheusEndpoint}/-/healthy", UriKind.Absolute, out var prometheusUri))
        {
            healthChecks.AddUrlGroup(prometheusUri, name: "prometheus", tags: new[] { "infrastructure" });
        }
        else
        {
            throw new InvalidOperationException("Invalid PrometheusEndpoint URI.");
        }

        if (!string.IsNullOrWhiteSpace(envOptions.Infrastructure.LokiUrl) &&
            Uri.TryCreate($"{envOptions.Infrastructure.LokiUrl}/ready", UriKind.Absolute, out var lokiUri))
        {
            healthChecks.AddUrlGroup(lokiUri, name: "loki", tags: new[] { "infrastructure" });
        }
        else
        {
            throw new InvalidOperationException("Invalid LokiUrl URI.");
        }

        if (!string.IsNullOrWhiteSpace(envOptions.Infrastructure.TempoEndpoint) &&
            Uri.TryCreate($"{envOptions.Infrastructure.TempoEndpoint}/ready", UriKind.Absolute, out var tempoUri))
        {
            healthChecks.AddUrlGroup(tempoUri, name: "tempo", tags: new[] { "infrastructure" });
        }
        else
        {
            throw new InvalidOperationException("Invalid TempoEndpoint URI.");
        }
    }

    private static string GetServiceVersion()
    {
        try
        {
            return typeof(ObservabilityExtensions).Assembly.GetName().Version?.ToString()
                   ?? "1.0.0";
        }
        catch
        {
            return "1.0.0";
        }
    }

    private static Dictionary<string, string> GetServiceEndpoints(ServiceEndpoints endpoints)
    {
        return new Dictionary<string, string>
        {
            { "ApiGateway", endpoints.ApiGateway },
            { "OrderService", endpoints.OrderService },
            { "InventoryService", endpoints.InventoryService }
        };
    }
}

