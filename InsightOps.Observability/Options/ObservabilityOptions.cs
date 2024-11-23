// InsightOps.Observability/Options/ObservabilityOptions.cs
namespace InsightOps.Observability.Options;

public class MetricsOptions
{
    public TimeSpan Interval { get; set; } = TimeSpan.FromSeconds(30); // Default to 30 seconds
    public int RetentionDays { get; set; } = 7; // Default to 7 days
    public bool EnableDetailedMetrics { get; set; } = true; // Enable detailed metrics by default
}

public class ObservabilityOptions
{
    public CommonOptions Common { get; set; } = new();
    public EnvironmentOptions Development { get; set; } = new();
    public EnvironmentOptions Docker { get; set; } = new();
    public GrafanaOptions Grafana { get; set; } = new();
}

public class GrafanaOptions
{
    public string DashboardsPath { get; set; } = "/etc/grafana/dashboards";
    public bool AutoProvision { get; set; } = true;
    public List<GrafanaDashboard> Dashboards { get; set; } = new();
}

public enum AppEnvironment
{
    Development,
    Docker,
    Production
}

public class CommonOptions
{
    public string ServiceName { get; set; } = string.Empty;
    public AppEnvironment Environment { get; set; } = AppEnvironment.Development;
    public string MetricsEndpoint { get; set; } = "/metrics";
    public string HealthCheckEndpoint { get; set; } = "/health";
    public int RetentionDays { get; set; } = 7;
    public bool EnableDetailedMetrics { get; set; } = true;
    public int MetricsInterval { get; set; } = 10;
}

public class EnvironmentOptions
{
    public InfrastructureOptions Infrastructure { get; set; } = new();
    public ServiceEndpoints Services { get; set; } = new();
}

public class InfrastructureOptions
{
    public string LokiUrl { get; set; } = string.Empty;
    public string TempoEndpoint { get; set; } = string.Empty;
    public string PrometheusEndpoint { get; set; } = string.Empty;
    public string GrafanaEndpoint { get; set; } = string.Empty;
}

public class ServiceEndpoints
{
    public string ApiGateway { get; set; } = string.Empty;
    public string OrderService { get; set; } = string.Empty;
    public string InventoryService { get; set; } = string.Empty;
}