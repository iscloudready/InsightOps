// FrontendService/Services/OrderService.cs
using System.Text.Json;
using FrontendService.Models.DTOs;
using FrontendService.Models.Requests;
using FrontendService.Models.Responses;

namespace FrontendService.Services
{
    public class OrderService : IOrderService
    {
        private readonly HttpClient _httpClient;
        private readonly ILogger<OrderService> _logger;
        private readonly IConfiguration _configuration;

        public OrderService(IHttpClientFactory clientFactory, IConfiguration configuration, ILogger<OrderService> logger)
        {
            _httpClient = clientFactory.CreateClient("ApiGateway");
            _configuration = configuration;
            _logger = logger;

            var apiGatewayUrl = _configuration["ServiceUrls:ApiGateway"];
            _httpClient.BaseAddress = new Uri(apiGatewayUrl ?? "http://localhost:7237");
        }

        public async Task<IEnumerable<OrderDto>> GetAllOrdersAsync()
        {
            try
            {
                var response = await _httpClient.GetAsync("/api/gateway/orders");
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                var orders = JsonSerializer.Deserialize<IEnumerable<OrderDto>>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                    ?? Enumerable.Empty<OrderDto>();

                _logger.LogInformation("Retrieved {Count} orders", orders.Count());
                return orders;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error retrieving orders: {Message}", ex.Message);
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving orders");
                throw;
            }
        }

        public async Task<OrderDto> GetOrderByIdAsync(int id)
        {
            try
            {
                var response = await _httpClient.GetAsync($"/api/gateway/orders/{id}");
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                var order = JsonSerializer.Deserialize<OrderDto>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                if (order == null)
                    throw new KeyNotFoundException($"Order with ID {id} not found");

                return order;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error retrieving order {OrderId}: {Message}", id, ex.Message);
                throw;
            }
        }

        public async Task<OrderResponse> CreateOrderAsync(CreateOrderDto order)
        {
            try
            {
                var response = await _httpClient.PostAsJsonAsync("/api/gateway/orders", order);
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                var createdOrder = JsonSerializer.Deserialize<OrderResponse>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                if (createdOrder == null)
                    throw new InvalidOperationException("Failed to create order - null response");

                _logger.LogInformation("Created order ID: {OrderId}", createdOrder.OrderId);
                return createdOrder;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error creating order: {Message}", ex.Message);
                throw;
            }
        }

        public async Task<OrderStatusResponse> GetOrderStatusAsync(int orderId)
        {
            try
            {
                var response = await _httpClient.GetAsync($"/api/gateway/orders/{orderId}/status");
                response.EnsureSuccessStatusCode();

                var content = await response.Content.ReadAsStringAsync();
                var status = JsonSerializer.Deserialize<OrderStatusResponse>(content,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                if (status == null)
                    throw new KeyNotFoundException($"Status for order {orderId} not found");

                return status;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error getting order status {OrderId}: {Message}", orderId, ex.Message);
                throw;
            }
        }

        public async Task<bool> UpdateOrderStatusAsync(int orderId, string status)
        {
            try
            {
                var response = await _httpClient.PutAsJsonAsync($"/api/gateway/orders/{orderId}/status",
                    new { status = status });
                return response.IsSuccessStatusCode;
            }
            catch (HttpRequestException ex)
            {
                _logger.LogError(ex, "HTTP request error updating order status {OrderId}: {Message}", orderId, ex.Message);
                throw;
            }
        }
    }
}