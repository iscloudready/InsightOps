// ApiGateway/Controllers/GatewayController.cs
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using ApiGateway.Models.DTOs;
using ApiGateway.Models.Requests;

namespace ApiGateway.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class GatewayController : ControllerBase
    {
        private readonly IHttpClientFactory _clientFactory;
        private readonly ILogger<GatewayController> _logger;
        private readonly JsonSerializerOptions _jsonOptions;

        public GatewayController(IHttpClientFactory clientFactory, ILogger<GatewayController> logger)
        {
            _clientFactory = clientFactory ?? throw new ArgumentNullException(nameof(clientFactory));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _jsonOptions = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            };
        }

        [HttpGet("orders")]
        public async Task<IActionResult> GetOrders()
        {
            try
            {
                var client = _clientFactory.CreateClient("OrderService");
                var response = await client.GetAsync("/api/orders");

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var orders = JsonSerializer.Deserialize<IEnumerable<OrderDTO>>(content, _jsonOptions);
                    return Ok(orders);
                }

                _logger.LogWarning("Failed to get orders. Status code: {StatusCode}", response.StatusCode);
                return StatusCode((int)response.StatusCode, "Failed to retrieve orders");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving orders");
                return StatusCode(500, "Internal server error occurred while retrieving orders");
            }
        }

        [HttpGet("orders/{id}")]
        public async Task<IActionResult> GetOrderById(int id)
        {
            try
            {
                var client = _clientFactory.CreateClient("OrderService");
                var response = await client.GetAsync($"/api/orders/{id}");

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var order = JsonSerializer.Deserialize<OrderDTO>(content, _jsonOptions);
                    return Ok(order);
                }

                if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
                    return NotFound($"Order with ID {id} not found");

                return StatusCode((int)response.StatusCode, "Failed to retrieve order");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving order {OrderId}", id);
                return StatusCode(500, "Internal server error occurred while retrieving order");
            }
        }

        [HttpPost("orders")]
        public async Task<IActionResult> CreateOrder([FromBody] CreateOrderRequest request)
        {
            try
            {
                // First check inventory
                var inventoryClient = _clientFactory.CreateClient("InventoryService");
                var inventoryResponse = await inventoryClient.GetAsync($"/api/inventory/item/name/{request.ItemName}");

                if (!inventoryResponse.IsSuccessStatusCode)
                {
                    return BadRequest($"Item {request.ItemName} not found in inventory");
                }

                var inventoryContent = await inventoryResponse.Content.ReadAsStringAsync();
                var inventoryItem = JsonSerializer.Deserialize<InventoryItemDTO>(inventoryContent, _jsonOptions);

                if (inventoryItem.Quantity < request.Quantity)
                {
                    return BadRequest($"Insufficient stock. Available: {inventoryItem.Quantity}");
                }

                // Create order
                var orderClient = _clientFactory.CreateClient("OrderService");
                var orderResponse = await orderClient.PostAsJsonAsync("/api/orders", request);

                if (!orderResponse.IsSuccessStatusCode)
                {
                    return StatusCode((int)orderResponse.StatusCode, "Failed to create order");
                }

                // Update inventory
                var updateStockResponse = await inventoryClient.PutAsJsonAsync(
                    $"/api/inventory/{inventoryItem.Id}/stock",
                    inventoryItem.Quantity - request.Quantity);

                if (!updateStockResponse.IsSuccessStatusCode)
                {
                    _logger.LogWarning("Failed to update inventory stock after order creation");
                }

                var orderContent = await orderResponse.Content.ReadAsStringAsync();
                var createdOrder = JsonSerializer.Deserialize<OrderDTO>(orderContent, _jsonOptions);
                return CreatedAtAction(nameof(GetOrderById), new { id = createdOrder.Id }, createdOrder);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while creating order");
                return StatusCode(500, "Internal server error occurred while creating order");
            }
        }

        [HttpGet("inventory")]
        public async Task<IActionResult> GetInventory()
        {
            try
            {
                var client = _clientFactory.CreateClient("InventoryService");
                var response = await client.GetAsync("/api/inventory");

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var inventory = JsonSerializer.Deserialize<IEnumerable<InventoryItemDTO>>(content, _jsonOptions);
                    return Ok(inventory);
                }

                return StatusCode((int)response.StatusCode, "Failed to retrieve inventory");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving inventory");
                return StatusCode(500, "Internal server error occurred while retrieving inventory");
            }
        }

        [HttpGet("inventory/low-stock")]
        public async Task<IActionResult> GetLowStockItems()
        {
            try
            {
                var client = _clientFactory.CreateClient("InventoryService");
                var response = await client.GetAsync("/api/inventory/lowstock");

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var lowStockItems = JsonSerializer.Deserialize<IEnumerable<InventoryItemDTO>>(content, _jsonOptions);
                    return Ok(lowStockItems);
                }

                return StatusCode((int)response.StatusCode, "Failed to retrieve low stock items");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving low stock items");
                return StatusCode(500, "Internal server error occurred while retrieving low stock items");
            }
        }

        [HttpGet("health")]
        public async Task<IActionResult> GetHealthStatus()
        {
            var healthStatus = new Dictionary<string, string>();

            try
            {
                var orderClient = _clientFactory.CreateClient("OrderService");
                var inventoryClient = _clientFactory.CreateClient("InventoryService");

                var orderHealth = await orderClient.GetAsync("/health");
                var inventoryHealth = await inventoryClient.GetAsync("/health");

                healthStatus.Add("OrderService", orderHealth.IsSuccessStatusCode ? "Healthy" : "Unhealthy");
                healthStatus.Add("InventoryService", inventoryHealth.IsSuccessStatusCode ? "Healthy" : "Unhealthy");

                return Ok(healthStatus);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while checking services health");
                return StatusCode(500, healthStatus);
            }
        }
    }
}