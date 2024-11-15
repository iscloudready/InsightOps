// OrderService/Services/OrderService.cs
using OrderService.Models;
using OrderService.Models.Responses;
using OrderService.Interfaces;

namespace OrderService.Services
{
    public class OrderService : IOrderService
    {
        private readonly IOrderRepository _orderRepository;
        private readonly ILogger<OrderService> _logger;

        public OrderService(IOrderRepository orderRepository, ILogger<OrderService> logger)
        {
            _orderRepository = orderRepository ?? throw new ArgumentNullException(nameof(orderRepository));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task<IEnumerable<Order>> GetAllOrdersAsync()
        {
            try
            {
                _logger.LogInformation("Retrieving all orders");
                return await _orderRepository.GetAllOrdersAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving all orders");
                throw;
            }
        }

        public async Task<OrderResponse> PlaceOrderAsync(CreateOrderDto orderDto)
        {
            try
            {
                var order = new Order
                {
                    ItemName = orderDto.ItemName,
                    Quantity = orderDto.Quantity,
                    OrderDate = DateTime.UtcNow,
                    Status = "Pending",
                    TotalPrice = 0 // This should be calculated based on item price from inventory
                };

                var createdOrder = await _orderRepository.CreateOrderAsync(order);

                return new OrderResponse
                {
                    OrderId = createdOrder.Id,
                    ItemName = createdOrder.ItemName,
                    Quantity = createdOrder.Quantity,
                    TotalPrice = createdOrder.TotalPrice,
                    Status = createdOrder.Status,
                    OrderDate = createdOrder.OrderDate,
                    Success = true,
                    Message = "Order placed successfully"
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error placing order for item {ItemName}", orderDto.ItemName);
                return new OrderResponse
                {
                    Success = false,
                    Message = "Failed to place order: " + ex.Message
                };
            }
        }

        public async Task<bool> CancelOrderAsync(int orderId)
        {
            try
            {
                _logger.LogInformation("Cancelling order {OrderId}", orderId);
                return await _orderRepository.UpdateOrderStatusAsync(orderId, "Cancelled");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error cancelling order {OrderId}", orderId);
                throw;
            }
        }

        public async Task<OrderStatusResponse> GetOrderStatusAsync(int orderId)
        {
            try
            {
                var order = await _orderRepository.GetOrderByIdAsync(orderId);
                if (order == null)
                {
                    _logger.LogWarning("Order {OrderId} not found", orderId);
                    throw new KeyNotFoundException($"Order with ID {orderId} not found");
                }

                return new OrderStatusResponse
                {
                    OrderId = order.Id,
                    Status = order.Status,
                    ItemName = order.ItemName,
                    Quantity = order.Quantity,
                    LastUpdated = order.OrderDate,
                    TotalPrice = order.TotalPrice,
                    Notes = GetOrderNotes(order)
                };
            }
            catch (Exception ex) when (ex is not KeyNotFoundException)
            {
                _logger.LogError(ex, "Error retrieving status for order {OrderId}", orderId);
                throw;
            }
        }

        private string GetOrderNotes(Order order)
        {
            return order.Status switch
            {
                "Pending" => "Order is being processed",
                "Confirmed" => "Order has been confirmed and is being prepared",
                "Shipped" => "Order has been shipped",
                "Delivered" => "Order has been delivered",
                "Cancelled" => "Order has been cancelled",
                _ => string.Empty
            };
        }
    }
}