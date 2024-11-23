public static class DefaultDashboards
{
    public static GrafanaDashboard ServiceOverview => new()
    {
        Title = "Service Overview",
        Content = ""// JSON content
    };

    public static GrafanaDashboard SystemMetrics => new()
    {
        Title = "System Metrics",
        Content = ""// JSON content
    };

    public static GrafanaDashboard ExecutiveOverview => new()
    {
        Title = "Executive Overview",
        Uid = "executive-overview",
        Type = DashboardType.Overview,
        Content = GetDashboardContent("ExecutiveOverview")
    };

    private static string GetDashboardContent(string v)
    {
        throw new NotImplementedException();
    }

    public static GrafanaDashboard TechnicalOverview => new()
    {
        Title = "Technical Overview",
        Uid = "technical-overview",
        Type = DashboardType.ServiceMetrics
    };
}