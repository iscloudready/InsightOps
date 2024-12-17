namespace FrontendService.Services
{
    public class ServiceUrlResolver
    {
        private readonly IConfiguration _configuration;
        private readonly ILogger<ServiceUrlResolver> _logger;

        public ServiceUrlResolver(IConfiguration configuration, ILogger<ServiceUrlResolver> logger)
        {
            _configuration = configuration;
            _logger = logger;
        }

        public string GetServiceUrl(string serviceName)
        {
            var url = _configuration[$"ServiceUrls:{serviceName}"];
            if (string.IsNullOrEmpty(url))
            {
                _logger.LogWarning("Service URL not found for {ServiceName}", serviceName);
                throw new InvalidOperationException($"Service URL not configured: {serviceName}");
            }
            return url;
        }
    }
}
