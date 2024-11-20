using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using System.Collections.Concurrent;
using System.Diagnostics.Metrics;

namespace FrontendService.Monitoring
{
    public class MonitoringOptions
    {
        public TimeSpan MetricsInterval { get; set; }
        public int RetentionDays { get; set; }
        public bool EnableDetailedMetrics { get; set; }
    }
}