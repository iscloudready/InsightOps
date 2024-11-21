using InsightOps.Observability.Configurations;
using InsightOps.Observability.HealthChecks;
using InsightOps.Observability.Metrics;
using InsightOps.Observability.Middleware;
using InsightOps.Observability.SignalR;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using Serilog.Events;
using System.Diagnostics;
using System.Text.Json;

namespace InsightOps.Observability.Extensions
{
    /// <summary>
    /// Provides extension methods for setting up observability in an application.
    /// </summary>
    public static class ObservabilityExtensions
    {
        /// <summary>
        /// Registers all InsightOps observability components: logging, OpenTelemetry, health checks, and metrics.
        /// </summary>
        /// <param name="services">The service collection to configure.</param>
        /// <param name="configuration">The application configuration.</param>
        /// <param name="serviceName">The name of the service being configured.</param>
        /// <param name="configureOptions">Optional action to configure additional observability options.</param>
        public static IServiceCollection AddInsightOpsObservability(
            this IServiceCollection services,
            IConfiguration configuration,
            string serviceName,
            Action<ObservabilityOptions>? configureOptions = null)
        {
            var options = new ObservabilityOptions();
            configureOptions?.Invoke(options);

            // Configure logging, tracing, and health checks
            AddLogging(services, configuration, serviceName, options);
            AddOpenTelemetry(services, configuration, serviceName, options);
            AddHealthChecks(services, options);

            return services;
        }

        /// <summary>
        /// Configures Serilog for structured logging with Loki and console output.
        /// </summary>
        private static void AddLogging(
            IServiceCollection services,
            IConfiguration configuration,
            string serviceName,
            ObservabilityOptions options)
        {
            // Get Loki URL from options or configuration
            var lokiUrl = options.LokiUrl ?? configuration["Observability:LokiUrl"] ?? "http://loki:3100";

            // Validate the Loki URL
            if (!Uri.IsWellFormedUriString(lokiUrl, UriKind.Absolute))
            {
                throw new ArgumentException($"Invalid Loki URL: {lokiUrl}");
            }

            // Configure Serilog for structured logging
            var loggerConfig = new LoggerConfiguration()
                .ReadFrom.Configuration(configuration)
                .MinimumLevel.Information()
                .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
                .MinimumLevel.Override("System", LogEventLevel.Warning)
                .Enrich.FromLogContext()
                .Enrich.WithProperty("Service", serviceName)
                .Enrich.WithProperty("Environment", Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT"))
                .Enrich.WithProperty("TraceId", Activity.Current?.Id ?? "")
                .WriteTo.Console(
                    outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties}{NewLine}{Exception}")
                .WriteTo.Http($"{lokiUrl}/loki/api/v1/push", queueLimitBytes: null);

            // Enable debug logging if configured
            if (options.EnableDebugLogging)
            {
                loggerConfig.MinimumLevel.Debug();
            }

            Log.Logger = loggerConfig.CreateLogger();

            services.AddLogging(loggingBuilder =>
            {
                loggingBuilder.ClearProviders();
                loggingBuilder.AddSerilog(dispose: true);
            });
        }

        /// <summary>
        /// Configures OpenTelemetry for tracing and metrics instrumentation.
        /// </summary>
        private static void AddOpenTelemetry(
            IServiceCollection services,
            IConfiguration configuration,
            string serviceName,
            ObservabilityOptions options)
        {
            var tempoEndpoint = options.TempoEndpoint ?? configuration["Observability:Tempo:OtlpEndpoint"] ?? "http://tempo:4317";

            // Validate the Tempo endpoint
            if (!Uri.IsWellFormedUriString(tempoEndpoint, UriKind.Absolute))
            {
                throw new ArgumentException($"Invalid Tempo Endpoint: {tempoEndpoint}");
            }

            // Configure tracing and metrics
            services.AddOpenTelemetry()
                .WithTracing(builder =>
                {
                    builder
                        .AddSource(serviceName)
                        .AddAspNetCoreInstrumentation(opts =>
                        {
                            opts.RecordException = true;
                            opts.EnrichWithHttpRequest = (activity, request) =>
                            {
                                activity.SetTag("http.request.headers", string.Join(",", request.Headers.Select(h => $"{h.Key}={h.Value}")));
                            };
                        })
                        .AddHttpClientInstrumentation(opts =>
                        {
                            opts.RecordException = true;
                        })
                        .AddOtlpExporter(opts =>
                        {
                            opts.Endpoint = new Uri(tempoEndpoint);
                        })
                        .SetResourceBuilder(
                            ResourceBuilder.CreateDefault()
                                .AddService(serviceName)
                                .AddTelemetrySdk()
                                .AddEnvironmentVariableDetector());
                })
                .WithMetrics(builder =>
                {
                    builder
                        .AddAspNetCoreInstrumentation()
                        .AddHttpClientInstrumentation()
                        .AddRuntimeInstrumentation()
                        .AddPrometheusExporter(opts =>
                        {
                            opts.ScrapeEndpointPath = options.MetricsEndpoint ?? "/metrics";
                        });
                });
        }

        /// <summary>
        /// Registers dynamic health checks based on service endpoints.
        /// </summary>
        public static void AddDynamicHealthChecks(this IServiceCollection services, IEnumerable<string> serviceEndpoints)
        {
            services.AddHealthChecks().AddCheck<DynamicHealthCheck>("dynamic_health_check", tags: serviceEndpoints.ToList());
        }

        /// <summary>
        /// Registers the RealTimeMetricsCollector for API metrics tracking.
        /// </summary>
        public static IServiceCollection AddMetricsCollector(this IServiceCollection services)
        {
            services.AddSingleton<RealTimeMetricsCollector>();
            return services;
        }

        /// <summary>
        /// Configures SignalR for real-time metrics broadcasting.
        /// </summary>
        public static IServiceCollection AddMetricsHub(this IServiceCollection services)
        {
            services.AddSignalR(options =>
            {
                options.EnableDetailedErrors = true;
                options.MaximumReceiveMessageSize = 102400;
            });
            services.AddSingleton<MetricsHub>();
            return services;
        }

        /// <summary>
        /// Configures default monitoring options from configuration.
        /// </summary>
        public static IServiceCollection AddMonitoringOptions(this IServiceCollection services, IConfiguration configuration)
        {
            services.Configure<MonitoringOptions>(options =>
            {
                options.MetricsInterval = TimeSpan.FromSeconds(int.Parse(configuration["Monitoring:MetricsInterval"] ?? "10"));
                options.RetentionDays = int.Parse(configuration["Monitoring:RetentionDays"] ?? "7");
                options.EnableDetailedMetrics = bool.Parse(configuration["Monitoring:EnableDetailedMetrics"] ?? "true");
            });

            return services;
        }

        /// <summary>
        /// Adds custom middleware for tracking API request and response metrics.
        /// </summary>
        public static IApplicationBuilder UseMetricsMiddleware(this IApplicationBuilder app)
        {
            app.UseMiddleware<MetricsMiddleware>();
            return app;
        }

        /// <summary>
        /// Configures health checks and adds any additional health check registrations.
        /// </summary>
        private static void AddHealthChecks(IServiceCollection services, ObservabilityOptions options)
        {
            var healthChecks = services.AddHealthChecks();

            // Default "self" health check
            healthChecks.AddCheck("self", () => HealthCheckResult.Healthy());

            // Add additional health checks if specified
            foreach (var check in options.AdditionalHealthChecks)
            {
                healthChecks.Add(check);
            }
        }

        /// <summary>
        /// Configures middleware and endpoints for InsightOps observability.
        /// </summary>
        public static IApplicationBuilder UseInsightOpsObservability(this IApplicationBuilder app)
        {
            app.UseSerilogRequestLogging(opts =>
            {
                opts.MessageTemplate = "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed:0.0000} ms";
            });

            app.UseHealthChecks("/health", new HealthCheckOptions
            {
                ResponseWriter = async (context, report) =>
                {
                    context.Response.ContentType = "application/json";
                    await JsonSerializer.SerializeAsync(
                        context.Response.Body,
                        new
                        {
                            status = report.Status.ToString(),
                            checks = report.Entries.Select(e => new
                            {
                                name = e.Key,
                                status = e.Value.Status.ToString(),
                                description = e.Value.Description
                            })
                        });
                }
            });

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapPrometheusScrapingEndpoint("/metrics");
            });

            return app;
        }
    }

    /// <summary>
    /// Configuration options for InsightOps observability.
    /// </summary>
    public class ObservabilityOptions
    {
        public string? LokiUrl { get; set; }
        public string? TempoEndpoint { get; set; }
        public string? MetricsEndpoint { get; set; }
        public bool EnableDebugLogging { get; set; }
        public List<HealthCheckRegistration> AdditionalHealthChecks { get; set; } = new();
    }
}
