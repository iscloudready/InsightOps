namespace FrontendService.Extensions
{
    public class RouteDebugMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly ILogger _logger;

        public RouteDebugMiddleware(RequestDelegate next, ILogger<RouteDebugMiddleware> logger)
        {
            _next = next;
            _logger = logger;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            _logger.LogInformation(
                "Request Path: {Path}, Method: {Method}, RouteValues: {@RouteValues}",
                context.Request.Path,
                context.Request.Method,
                context.GetRouteData()?.Values);

            await _next(context);
        }
    }
}
