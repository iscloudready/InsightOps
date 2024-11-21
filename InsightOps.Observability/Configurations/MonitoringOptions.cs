namespace InsightOps.Observability.Configurations
{
    public class MonitoringOptions
    {
        public TimeSpan MetricsInterval { get; set; } = TimeSpan.FromSeconds(10);
        public int RetentionDays { get; set; } = 7;
        public bool EnableDetailedMetrics { get; set; } = true;
    }
}
