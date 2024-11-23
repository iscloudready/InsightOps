// InsightOps.Observability/Extensions/ObservabilityMiddlewareExtensions.cs
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using System.Text.Json;
using InsightOps.Observability.Options;
using InsightOps.Observability.Middleware;
using OpenTelemetry.Extensions.Hosting;
using OpenTelemetry.Metrics;
namespace InsightOps.Observability.Extensions;
using OpenTelemetry.Extensions.Hosting;
using OpenTelemetry.Metrics;
using Prometheus;

public static class ObservabilityMiddlewareExtensions
{
    public static IApplicationBuilder UseInsightOpsObservability(
       this IApplicationBuilder app)
    {
        var options = app.ApplicationServices
            .GetRequiredService<IOptions<ObservabilityOptions>>()
            .Value;

        // Add request tracking middleware
        app.UseMiddleware<MetricsMiddleware>();

        // Configure health checks
        app.UseHealthChecks(options.Common.HealthCheckEndpoint, new HealthCheckOptions
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
                        description = x.Value.Description,
                        duration = x.Value.Duration.TotalMilliseconds,
                        tags = x.Value.Tags
                    }),
                    totalDuration = report.TotalDuration.TotalMilliseconds
                };
                await JsonSerializer.SerializeAsync(context.Response.Body, response);
            }
        });

        // Configure metrics endpoint
        app.UseEndpoints(endpoints =>
        {
            endpoints.MapMetrics(); // Expose Prometheus metrics
        });

        return app;
    }
}