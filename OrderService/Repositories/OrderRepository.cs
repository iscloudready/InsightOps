// Updated OrderRepository
using OrderService.Models;
using Microsoft.EntityFrameworkCore;
using OrderService.Data;

namespace OrderService.Repositories
{
    public class OrderRepository
    {
        private readonly OrderDbContext _context;

        public OrderRepository(OrderDbContext context)
        {
            _context = context;
        }

        public async Task<IEnumerable<Order>> GetAllOrders()
            => await _context.Orders.ToListAsync();

        public async Task<Order> GetOrderById(int id)
            => await _context.Orders.FindAsync(id);

        public async Task<Order> AddOrder(Order order)
        {
            _context.Orders.Add(order);
            await _context.SaveChangesAsync();
            return order;
        }
    }
}
