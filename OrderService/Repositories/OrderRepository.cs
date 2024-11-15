// OrderService/Repositories/OrderRepository.cs
using Microsoft.EntityFrameworkCore;
using OrderService.Models;
using OrderService.Interfaces;
using OrderService.Data;

namespace OrderService.Repositories
{
    public class OrderRepository : IOrderRepository
    {
        private readonly OrderDbContext _context;
        private readonly ILogger<OrderRepository> _logger;

        public OrderRepository(OrderDbContext context, ILogger<OrderRepository> logger)
        {
            _context = context ?? throw new ArgumentNullException(nameof(context));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task<IEnumerable<Order>> GetAllOrdersAsync()
        {
            try
            {
                return await _context.Orders
                    .OrderByDescending(o => o.OrderDate)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving all orders");
                throw;
            }
        }

        public async Task<Order?> GetOrderByIdAsync(int id)
        {
            try
            {
                return await _context.Orders
                    .FirstOrDefaultAsync(o => o.Id == id);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving order with ID: {OrderId}", id);
                throw;
            }
        }

        public async Task<Order> CreateOrderAsync(Order order)
        {
            if (order == null)
                throw new ArgumentNullException(nameof(order));

            try
            {
                order.OrderDate = DateTime.UtcNow;
                order.Status = "Pending";

                _context.Orders.Add(order);
                await _context.SaveChangesAsync();

                _logger.LogInformation("Created new order with ID: {OrderId}", order.Id);
                return order;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while creating new order");
                throw;
            }
        }

        public async Task<Order> UpdateOrderAsync(Order order)
        {
            if (order == null)
                throw new ArgumentNullException(nameof(order));

            try
            {
                var existingOrder = await _context.Orders.FindAsync(order.Id);
                if (existingOrder == null)
                    throw new KeyNotFoundException($"Order with ID {order.Id} not found");

                // Update only modifiable properties
                existingOrder.ItemName = order.ItemName;
                existingOrder.Quantity = order.Quantity;
                existingOrder.TotalPrice = order.TotalPrice;
                existingOrder.Status = order.Status;

                await _context.SaveChangesAsync();

                _logger.LogInformation("Updated order with ID: {OrderId}", order.Id);
                return existingOrder;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while updating order with ID: {OrderId}", order.Id);
                throw;
            }
        }

        public async Task<bool> DeleteOrderAsync(int id)
        {
            try
            {
                var order = await _context.Orders.FindAsync(id);
                if (order == null)
                    return false;

                _context.Orders.Remove(order);
                await _context.SaveChangesAsync();

                _logger.LogInformation("Deleted order with ID: {OrderId}", id);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while deleting order with ID: {OrderId}", id);
                throw;
            }
        }

        public async Task<IEnumerable<Order>> GetOrdersByStatusAsync(string status)
        {
            try
            {
                return await _context.Orders
                    .Where(o => o.Status == status)
                    .OrderByDescending(o => o.OrderDate)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving orders with status: {Status}", status);
                throw;
            }
        }

        public async Task<bool> UpdateOrderStatusAsync(int id, string status)
        {
            try
            {
                var order = await _context.Orders.FindAsync(id);
                if (order == null)
                    return false;

                order.Status = status;
                await _context.SaveChangesAsync();

                _logger.LogInformation("Updated status to {Status} for order with ID: {OrderId}", status, id);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while updating status for order with ID: {OrderId}", id);
                throw;
            }
        }

        public async Task<IEnumerable<Order>> GetOrdersByDateRangeAsync(DateTime startDate, DateTime endDate)
        {
            try
            {
                return await _context.Orders
                    .Where(o => o.OrderDate >= startDate && o.OrderDate <= endDate)
                    .OrderByDescending(o => o.OrderDate)
                    .ToListAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while retrieving orders between dates: {StartDate} and {EndDate}",
                    startDate, endDate);
                throw;
            }
        }

        public async Task<int> GetTotalOrdersCountAsync()
        {
            try
            {
                return await _context.Orders.CountAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while counting total orders");
                throw;
            }
        }

        public async Task<decimal> GetTotalOrdersValueAsync()
        {
            try
            {
                return await _context.Orders.SumAsync(o => o.TotalPrice);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while calculating total orders value");
                throw;
            }
        }

        public async Task<bool> OrderExistsAsync(int id)
        {
            try
            {
                return await _context.Orders.AnyAsync(o => o.Id == id);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred while checking existence of order with ID: {OrderId}", id);
                throw;
            }
        }
    }
}