using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Serilog;
using Serilog.Events;

namespace Observability.Extensions
{
    public static class SerilogExtensions
    {
        public static IHostBuilder UseInsightOpsSerilog(
            this IHostBuilder hostBuilder,
            IConfiguration configuration,
            string serviceName)
        {
            return hostBuilder.UseSerilog((context, loggerConfig) =>
            {
                var lokiUrl = configuration["Observability:LokiUrl"];
                if (string.IsNullOrWhiteSpace(lokiUrl))
                {
                    throw new InvalidOperationException("LokiUrl is not configured in Observability options.");
                }

                loggerConfig.ReadFrom.Configuration(configuration)
                    .Enrich.FromLogContext()
                    .Enrich.WithProperty("ServiceName", serviceName)
                    .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
                    .WriteTo.Http(
                        requestUri: lokiUrl + "/loki/api/v1/push",
                        queueLimitBytes: 10_000_000, // Set a reasonable default
                        restrictedToMinimumLevel: LogEventLevel.Information);
            });
        }
    }
}
