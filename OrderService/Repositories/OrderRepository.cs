using System.Collections.Generic;
using System.Linq;
using OrderService.Models;

namespace OrderService.Repositories
{
    public class OrderRepository
    {
        private readonly List<Order> _orders = new List<Order>();

        public IEnumerable<Order> GetAllOrders() => _orders;

        public Order GetOrderById(int id) => _orders.FirstOrDefault(o => o.Id == id);

        public void AddOrder(Order order) => _orders.Add(order);
    }
}
