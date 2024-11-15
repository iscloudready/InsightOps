// FrontendService/Services/BaseService.cs
public abstract class BaseService
{
    protected readonly HttpClient _client;
    protected readonly ILogger _logger;
    protected readonly string _apiGatewayUrl;

    protected BaseService(IHttpClientFactory clientFactory, IConfiguration config, ILogger logger)
    {
        _client = clientFactory.CreateClient("ApiGateway");
        _apiGatewayUrl = config["ServiceUrls:ApiGateway"] ?? "http://localhost:7237";
        _logger = logger;
    }
}