using Microsoft.Extensions.Logging;
using System;
using Microsoft.AspNetCore.Http;

namespace ApiGateway.Helpers
{
    public static class LogHelper
    {
        public static IDisposable BeginRequestScope(HttpContext context)
        {
            var loggerFactory = context.RequestServices.GetService(typeof(ILoggerFactory)) as ILoggerFactory;
            var logger = loggerFactory.CreateLogger("RequestScope");

            var requestId = Guid.NewGuid().ToString();
            var path = context.Request.Path;
            var method = context.Request.Method;

            return logger.BeginScope(new
            {
                RequestId = requestId,
                Path = path,
                Method = method
            });
        }
    }
}
