// FrontendService/Services/InventoryService.cs
using System.Text.Json;
using FrontendService.Models.DTOs;

namespace FrontendService.Services
{
    public class InventoryService : IInventoryService
    {
        private readonly HttpClient _httpClient;
        private readonly ILogger<InventoryService> _logger;
        private readonly IConfiguration _configuration;

        public InventoryService(
            IHttpClientFactory clientFactory,
            IConfiguration configuration,
            ILogger<InventoryService> logger)
        {
            _httpClient = clientFactory.CreateClient("ApiGateway");
            _configuration = configuration;
            _logger = logger;

            var apiGatewayUrl = _configuration["ServiceUrls:ApiGateway"];
            _httpClient.BaseAddress = new Uri(apiGatewayUrl ?? "http://localhost:7237");
        }

        public string GetServiceUrl() => _httpClient.BaseAddress?.ToString() ?? "Not configured";

        public async Task<IEnumerable<InventoryItemDto>> GetAllItemsAsync()
        {
            try
            {
                _logger.LogInformation("Making request to: {BaseUrl}/api/gateway/inventory",
                    _httpClient.BaseAddress);

                var response = await _httpClient.GetAsync("/api/gateway/inventory");
                var content = await response.Content.ReadAsStringAsync();  // Move this up

                _logger.LogInformation("Response Status: {Status}, Content: {Content}",
                    response.StatusCode, content);

                response.EnsureSuccessStatusCode();

                var items = JsonSerializer.Deserialize<IEnumerable<InventoryItemDto>>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                    ?? Enumerable.Empty<InventoryItemDto>();

                _logger.LogInformation("Deserialized {Count} items", items.Count());
                return items;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error. Base URL: {BaseUrl}, Error: {Error}",
                    _httpClient.BaseAddress, ex.Message);
                throw;
            }
            catch (JsonException ex)
            {
                _logger.LogError(ex, "JSON deserialization error. Error: {Error}", ex.Message);
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error getting inventory items");
                throw;
            }
        }

        public async Task<IEnumerable<InventoryItemDto>> _GetAllItemsAsync()
        {
            try
            {
                var response = await _httpClient.GetAsync("/api/gateway/inventory");
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                var items = JsonSerializer.Deserialize<IEnumerable<InventoryItemDto>>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                    ?? Enumerable.Empty<InventoryItemDto>();

                _logger.LogInformation("Retrieved {Count} inventory items", items.Count());
                return items;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error retrieving inventory: {Message}", ex.Message);
                throw;
            }
        }

        public async Task<InventoryItemDto> GetItemByIdAsync(int id)
        {
            try
            {
                var response = await _httpClient.GetAsync($"/api/gateway/inventory/{id}");
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                var item = JsonSerializer.Deserialize<InventoryItemDto>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                if (item == null)
                    throw new KeyNotFoundException($"Inventory item {id} not found");

                return item;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error retrieving inventory item {ItemId}: {Message}", id, ex.Message);
                throw;
            }
        }

        public async Task<IEnumerable<InventoryItemDto>> GetLowStockItemsAsync()
        {
            try
            {
                var response = await _httpClient.GetAsync("/api/gateway/inventory/low-stock");
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                return JsonSerializer.Deserialize<IEnumerable<InventoryItemDto>>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                    ?? Enumerable.Empty<InventoryItemDto>();
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error retrieving low stock items: {Message}", ex.Message);
                throw;
            }
        }

        public async Task<InventoryItemDto> UpdateStockAsync(int id, int quantity)
        {
            try
            {
                var response = await _httpClient.PutAsJsonAsync($"/api/gateway/inventory/{id}/stock",
                    new { quantity = quantity });
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                var updatedItem = JsonSerializer.Deserialize<InventoryItemDto>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                if (updatedItem == null)
                    throw new InvalidOperationException($"Failed to update stock for item {id}");

                _logger.LogInformation("Updated stock for item {ItemId} to {Quantity}", id, quantity);
                return updatedItem;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error updating stock for item {ItemId}: {Message}", id, ex.Message);
                throw;
            }
        }

        public async Task<InventoryItemDto> CreateItemAsync(InventoryItemDto item)
        {
            try
            {
                var response = await _httpClient.PostAsJsonAsync("/api/gateway/inventory", item);
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                var createdItem = JsonSerializer.Deserialize<InventoryItemDto>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                if (createdItem == null)
                    throw new InvalidOperationException("Failed to create inventory item - null response");

                _logger.LogInformation("Created inventory item ID: {ItemId}", createdItem.Id);
                return createdItem;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error creating inventory item: {Message}", ex.Message);
                throw;
            }
        }
    }
}