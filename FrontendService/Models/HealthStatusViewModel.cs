namespace FrontendService.Models
{
    public class HealthStatusViewModel
    {
        public class ServiceHealth
        {
            public string Name { get; set; }
            public string Status { get; set; }
            public DateTime LastChecked { get; set; }
            public string Details { get; set; }
            public Dictionary<string, string> Metrics { get; set; } = new();
        }

        public class ServiceGroup
        {
            public string Name { get; set; }
            public List<ServiceHealth> Services { get; set; } = new();
            public bool IsHealthy => Services.All(s => s.Status == "Healthy");
        }

        public List<ServiceGroup> ServiceGroups { get; set; } = new();
        public DateTime LastUpdated { get; set; }
        public bool OverallHealthy => ServiceGroups.All(g => g.IsHealthy);
    }
}
