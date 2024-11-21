using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Diagnostics;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using Serilog.Events;
using System.Net.Http.Headers;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Serilog.Core;
using System.IO;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Diagnostics.HealthChecks;// Add this using at the top
using PrometheusOptions = OpenTelemetry.Exporter.PrometheusAspNetCoreOptions;

namespace InsightOps.Observability.Extensions
{
    // Location: InsightOps.Observability/Extensions/ObservabilityExtensions.cs

    public static class ObservabilityExtensions
    {
        public static IServiceCollection AddInsightOpsObservability(
            this IServiceCollection services,
            IConfiguration configuration,
            string serviceName)
        {
            // Configure Serilog using existing config structure
            Log.Logger = new LoggerConfiguration()
                .ReadFrom.Configuration(configuration)
                .Enrich.WithProperty("Service", serviceName)
                .Enrich.WithProperty("Environment", Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT"))
                .Enrich.WithProperty("TraceId", Activity.Current?.Id ?? "")
                .CreateLogger();

            // Configure OpenTelemetry using Telemetry section
            var tempoEndpoint = configuration.GetValue<string>("Telemetry:Tempo:OtlpEndpoint");

            services.AddOpenTelemetry()
                .WithTracing(builder =>
                {
                    builder
                        .AddSource(serviceName)
                        .AddAspNetCoreInstrumentation()
                        .AddHttpClientInstrumentation()
                        .AddOtlpExporter(options =>
                        {
                            options.Endpoint = new Uri(tempoEndpoint);
                        })
                        .SetResourceBuilder(
                            ResourceBuilder.CreateDefault()
                                .AddService(serviceName)
                                .AddTelemetrySdk()
                                .AddEnvironmentVariableDetector());
                })
                .WithMetrics(builder =>
                {
                    var metricsPath = configuration.GetValue<string>("Metrics:Prometheus:ScrapeEndpoint");

                    builder
                        .AddAspNetCoreInstrumentation()
                        .AddHttpClientInstrumentation()
                        .AddRuntimeInstrumentation()
                        .AddPrometheusExporter((PrometheusOptions opts) =>
                        {
                             opts.ScrapeEndpointPath = metricsPath;
                        });
                });

            // Configure health checks
            services.AddHealthChecks()
                .AddCheck("self", () => HealthCheckResult.Healthy());

            return services;
        }
    }
}
