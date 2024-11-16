// FrontendService/Extensions/PollyContextExtensions.cs
using System;
using Microsoft.Extensions.Logging;
using Polly;

namespace FrontendService.Extensions
{
    public static class PollyContextExtensions
    {
        public static ILogger GetService<T>(this Context context)
        {
            if (context.TryGetValue("Logger", out object logger))
            {
                return logger as ILogger;
            }
            return null;
        }
    }
}