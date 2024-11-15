namespace FrontendService.Models
{
    public class ServiceStatus
    {
        public string Name { get; set; }
        public string Status { get; set; }
        public DateTime LastUpdated { get; set; }
        public string Uptime { get; set; }
        public Dictionary<string, string> Metrics { get; set; } = new();
        public List<string> RecentErrors { get; set; } = new();
        public string HealthCheckDetails { get; set; }
        public Dictionary<string, double> ResourceUsage { get; set; } = new();
    }
}
