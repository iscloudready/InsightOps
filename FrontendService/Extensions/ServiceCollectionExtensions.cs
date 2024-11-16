using System;
using System.Net.Http.Headers;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Polly;
using Polly.Extensions.Http;
using Polly.Timeout;
using FrontendService.Services;
using FrontendService.Services.Monitoring;
using System.Net.Http;
using Polly.Retry;
using Polly.CircuitBreaker;

namespace FrontendService.Extensions
{
    public static class ServiceCollectionExtensions
    {
        //private static readonly ILogger<Program> _logger;

        public static IServiceCollection AddApplicationServices(this IServiceCollection services, IConfiguration configuration)
        {
            // First register MetricsCollector
            services.AddSingleton<MetricsCollector>();

            // Then register SystemMetricsCollector which depends on it
            services.AddSingleton<SystemMetricsCollector>();

            // Rest of your service registrations...
            services.AddHttpClient("ApiGateway", client =>
            {
                var apiGatewayUrl = configuration["ServiceUrls:ApiGateway"]
                    ?? throw new InvalidOperationException("ApiGateway URL not configured");
                client.BaseAddress = new Uri(apiGatewayUrl);
                client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
                client.Timeout = TimeSpan.FromSeconds(10);
            })
            .AddPolicyHandler(GetRetryPolicy())
            .AddPolicyHandler(GetCircuitBreakerPolicy());

            services.AddMemoryCache();
            services.AddScoped<IOrderService, OrderService>();
            services.AddScoped<IInventoryService, InventoryService>();

            // Health checks
            services.AddHealthChecks()
                .AddUrlGroup(new Uri($"{configuration["ServiceUrls:ApiGateway"]}/health"), "api-gateway")
                .AddUrlGroup(new Uri($"{configuration["ServiceUrls:OrderService"]}/health"), "orders-api")
                .AddUrlGroup(new Uri($"{configuration["ServiceUrls:InventoryService"]}/health"), "inventory-api");

            return services;
        }

        private static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
        {
            return HttpPolicyExtensions
                .HandleTransientHttpError()
                .Or<TimeoutRejectedException>()
                .WaitAndRetryAsync(
                    retryCount: 3,
                    sleepDurationProvider: retryAttempt =>
                        TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
                    onRetry: (exception, timeSpan, retryCount, context) =>
                    {
                        Console.WriteLine($"Retry {retryCount} after {timeSpan.TotalSeconds}s delay due to {exception.Exception?.GetType().Name}");
                    });
        }

        private static IAsyncPolicy<HttpResponseMessage> GetCircuitBreakerPolicy()
        {
            return HttpPolicyExtensions
                .HandleTransientHttpError()
                .CircuitBreakerAsync(
                    handledEventsAllowedBeforeBreaking: 5,
                    durationOfBreak: TimeSpan.FromSeconds(30),
                    onBreak: (exception, duration) =>
                    {
                        Console.WriteLine($"Circuit breaker opened for {duration.TotalSeconds}s due to {exception.Exception?.Message}");
                    },
                    onReset: () =>
                    {
                        Console.WriteLine("Circuit breaker reset");
                    });
        }
    }
}