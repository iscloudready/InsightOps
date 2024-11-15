// OrderService/Interfaces/IOrderRepository.cs
using OrderService.Models;

namespace OrderService.Interfaces
{
    public interface IOrderRepository
    {
        Task<IEnumerable<Order>> GetAllOrdersAsync();
        Task<Order?> GetOrderByIdAsync(int id);
        Task<Order> CreateOrderAsync(Order order);
        Task<Order> UpdateOrderAsync(Order order);
        Task<bool> DeleteOrderAsync(int id);
        Task<IEnumerable<Order>> GetOrdersByStatusAsync(string status);
        Task<bool> UpdateOrderStatusAsync(int id, string status);
        Task<IEnumerable<Order>> GetOrdersByDateRangeAsync(DateTime startDate, DateTime endDate);
        Task<int> GetTotalOrdersCountAsync();
        Task<decimal> GetTotalOrdersValueAsync();
        Task<bool> OrderExistsAsync(int id);
    }
}
