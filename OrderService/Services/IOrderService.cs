// OrderService/Services/IOrderService.cs
using OrderService.Models;
using OrderService.Models.Responses;

namespace OrderService.Services
{
    public interface IOrderService
    {
        Task<IEnumerable<Order>> GetAllOrdersAsync();
        Task<OrderResponse> PlaceOrderAsync(CreateOrderDto orderDto);
        Task<bool> CancelOrderAsync(int orderId);
        Task<OrderStatusResponse> GetOrderStatusAsync(int orderId);
    }
}