// FrontendService/Extensions/ServiceCollectionExtensions.cs
using System;
using System.Net.Http.Headers;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Polly;
using Polly.Extensions.Http;
using Polly.Timeout;
using FrontendService.Services;
using System.Net.Http;
using Polly.Retry;
using Polly.CircuitBreaker;

namespace FrontendService.Extensions
{
    public static class ServiceCollectionExtensions
    {
        public static IServiceCollection AddApplicationServices(this IServiceCollection services, IConfiguration configuration)
        {
            services.AddHttpClient("ApiGateway", client =>
            {
                var apiGatewayUrl = configuration["ServiceUrls:ApiGateway"]
                    ?? throw new InvalidOperationException("ApiGateway URL not configured");

                client.BaseAddress = new Uri(apiGatewayUrl);
                client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            })
            .AddPolicyHandler(GetRetryPolicy())
            .AddPolicyHandler(GetCircuitBreakerPolicy());

            services.AddMemoryCache();
            services.AddScoped<IOrderService, OrderService>();
            services.AddScoped<IInventoryService, InventoryService>();

            return services;
        }

        private static IAsyncPolicy<HttpResponseMessage> GetRetryPolicy()
        {
            return HttpPolicyExtensions
                .HandleTransientHttpError()
                .Or<TimeoutRejectedException>()
                .WaitAndRetryAsync(3, retryAttempt =>
                    TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)),
                    onRetry: (exception, timeSpan, retryCount, context) =>
                    {
                        var logger = context.GetService<ILogger>();
                        logger?.LogWarning("Retry {RetryCount} after {TimeSpan}s delay due to {ExceptionType}",
                            retryCount, timeSpan.TotalSeconds, exception.Exception?.GetType().Name);
                    });
        }

        private static IAsyncPolicy<HttpResponseMessage> GetCircuitBreakerPolicy()
        {
            return HttpPolicyExtensions
                .HandleTransientHttpError()
                .CircuitBreakerAsync(5, TimeSpan.FromSeconds(30),
                    onBreak: (exception, duration) =>
                    {
                        // Log circuit breaker opening
                        Console.WriteLine($"Circuit breaker opened for {duration.TotalSeconds}s due to {exception.Exception?.Message}");
                    },
                    onReset: () =>
                    {
                        // Log circuit breaker reset
                        Console.WriteLine("Circuit breaker reset");
                    });
        }
    }
}