namespace InsightOps.Observability.Middleware
{
    using InsightOps.Observability.Metrics;
    using Microsoft.AspNetCore.Http;
    using System.Diagnostics;

    public class MetricsMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly RealTimeMetricsCollector _metricsCollector;

        public MetricsMiddleware(RequestDelegate next, RealTimeMetricsCollector metricsCollector)
        {
            _next = next;
            _metricsCollector = metricsCollector;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var stopwatch = Stopwatch.StartNew();
            try
            {
                _metricsCollector.RecordApiRequest(context.Request.Path, context.Request.Method);
                await _next(context);
            }
            finally
            {
                stopwatch.Stop();
                _metricsCollector.RecordApiResponse(context.Request.Path, stopwatch.Elapsed.TotalSeconds);
            }
        }
    }
}
