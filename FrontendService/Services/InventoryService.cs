// Frontend/Services/InventoryService.cs
// Add to both IOrderService.cs and OrderService.cs
using FrontendService.Models.DTOs;
using FrontendService.Models.Requests;
using FrontendService.Models.Responses;

// Add to both IInventoryService.cs and InventoryService.cs
using FrontendService.Models.DTOs;

public class InventoryService : IInventoryService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<InventoryService> _logger;

    public InventoryService(IHttpClientFactory clientFactory, ILogger<InventoryService> logger)
    {
        _httpClient = clientFactory.CreateClient("ApiGateway");
        _logger = logger;
    }

    public async Task<IEnumerable<InventoryItemDto>> GetAllItemsAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync("/api/gateway/inventory");
            response.EnsureSuccessStatusCode();
            return await response.Content.ReadFromJsonAsync<IEnumerable<InventoryItemDto>>() ??
                   Enumerable.Empty<InventoryItemDto>();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving inventory items");
            throw;
        }
    }

    public async Task<IEnumerable<InventoryItemDto>> GetLowStockItemsAsync()
    {
        var response = await _httpClient.GetAsync("/api/gateway/inventory/low-stock");
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<IEnumerable<InventoryItemDto>>() ??
               Enumerable.Empty<InventoryItemDto>();
    }

    public async Task<InventoryItemDto> GetItemByIdAsync(int id)
    {
        var response = await _httpClient.GetAsync($"/api/gateway/inventory/{id}");
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<InventoryItemDto>();
    }
}