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

    // Add new options
    public DataProtectionOptions DataProtection { get; set; } = new();
    public HttpClientOptions HttpClient { get; set; } = new();
    public SignalROptions SignalR { get; set; } = new();
    public ApplicationOptions Application { get; set; } = new();

    //public InfrastructureOptions Infrastructure { get; set; } = new();

    //public ServiceEndpoints Service { get; set; } = new();

    // Remove these as they're duplicates of what's in CommonOptions and InfrastructureOptions
    // public string LokiUrl { get; set; }
    // public string TempoEndpoint { get; set; }
    // public string MetricsEndpoint { get; set; }
    // public bool EnableDetailedMetrics { get; set; }
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

public class DataProtectionOptions
{
    public string Keys { get; set; } = "/app/Keys";
    public int KeyLifetimeDays { get; set; } = 90;
}

public class HttpClientOptions
{
    public int RetryCount { get; set; } = 5;
    public int RetryDelayMs { get; set; } = 100;
    public int CircuitBreakerThreshold { get; set; } = 10;
    public int CircuitBreakerDelay { get; set; } = 5;
    public int TimeoutSeconds { get; set; } = 30;
    public ApiGatewayOptions ApiGateway { get; set; } = new();

    public class ApiGatewayOptions
    {
        public string Accept { get; set; } = "application/json";
    }
}

public class SignalROptions
{
    public int MaximumReceiveMessageSize { get; set; } = 102400;
    public bool DetailedErrors { get; set; } = true;
}

public class JsonSerializerOptions
{
    public bool PropertyNameCaseInsensitive { get; set; } = true;
    public bool UsePropertyNamingPolicy { get; set; } = false;
}

public class ApplicationOptions
{
    public JsonSerializerOptions JsonOptions { get; set; } = new();
}

