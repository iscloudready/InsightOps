// Frontend/Services/IOrderService.cs
// Add to both IOrderService.cs and OrderService.cs
using FrontendService.Models.DTOs;
using FrontendService.Models.Requests;
using FrontendService.Models.Responses;

// FrontendService/Services/IOrderService.cs
namespace FrontendService.Services
{
    public interface IOrderService
    {
        Task<IEnumerable<OrderDto>> GetAllOrdersAsync();
        Task<OrderDto> GetOrderByIdAsync(int id);
        Task<OrderResponse> CreateOrderAsync(CreateOrderDto order);
        Task<OrderStatusResponse> GetOrderStatusAsync(int orderId);
        Task<bool> UpdateOrderStatusAsync(int orderId, string status);
    }
}