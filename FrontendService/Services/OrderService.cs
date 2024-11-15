// Frontend/Services/OrderService.cs
// Add to both IOrderService.cs and OrderService.cs
using FrontendService.Models.DTOs;
using FrontendService.Models.Requests;
using FrontendService.Models.Responses;

// Add to both IInventoryService.cs and InventoryService.cs
using FrontendService.Models.DTOs;

public class OrderService : IOrderService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<OrderService> _logger;

    public OrderService(IHttpClientFactory clientFactory, ILogger<OrderService> logger)
    {
        _httpClient = clientFactory.CreateClient("ApiGateway");
        _logger = logger;
    }

    public async Task<IEnumerable<OrderDto>> GetAllOrdersAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync("/api/gateway/orders");
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<IEnumerable<OrderDto>>() ?? Enumerable.Empty<OrderDto>();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving orders");
            throw;
        }
    }

    public async Task<OrderDto> GetOrderByIdAsync(int id)
    {
        var response = await _httpClient.GetAsync($"/api/gateway/orders/{id}");
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<OrderDto>();
    }

    public async Task<OrderResponse> CreateOrderAsync(CreateOrderDto order)
    {
        var response = await _httpClient.PostAsJsonAsync("/api/gateway/orders", order);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<OrderResponse>();
    }

    public async Task<OrderStatusResponse> GetOrderStatusAsync(int orderId)
    {
        var response = await _httpClient.GetAsync($"/api/gateway/orders/{orderId}/status");
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<OrderStatusResponse>();
    }
}