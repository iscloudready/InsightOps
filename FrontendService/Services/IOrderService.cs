// Frontend/Services/IOrderService.cs
// Add to both IOrderService.cs and OrderService.cs
using FrontendService.Models.DTOs;
using FrontendService.Models.Requests;
using FrontendService.Models.Responses;

// Add to both IInventoryService.cs and InventoryService.cs
using FrontendService.Models.DTOs;

public interface IOrderService
{
    Task<IEnumerable<OrderDto>> GetAllOrdersAsync();
    Task<OrderDto> GetOrderByIdAsync(int id);
    Task<OrderResponse> CreateOrderAsync(CreateOrderDto order);
    Task<OrderStatusResponse> GetOrderStatusAsync(int orderId);
}