// InsightOps.Observability/Middleware/MetricsMiddleware.cs
using Microsoft.AspNetCore.Http;
using InsightOps.Observability.Metrics;
using System.Diagnostics;

namespace InsightOps.Observability.Middleware;

public class MetricsMiddleware
{
    private readonly RequestDelegate _next;
    private readonly RealTimeMetricsCollector _metricsCollector;

    public MetricsMiddleware(
        RequestDelegate next,
        RealTimeMetricsCollector metricsCollector)
    {
        _next = next;
        _metricsCollector = metricsCollector;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var sw = Stopwatch.StartNew();
        var path = context.Request.Path.Value?.ToLowerInvariant() ?? "";

        try
        {
            _metricsCollector.RecordRequestStarted(path);
            await _next(context);
        }
        finally
        {
            sw.Stop();
            _metricsCollector.RecordRequestCompleted(
                path,
                context.Response.StatusCode,
                sw.Elapsed.TotalSeconds);
        }
    }
}
