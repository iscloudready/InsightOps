using Microsoft.AspNetCore.Mvc;
using OrderService.Models;
using OrderService.Repositories;

namespace OrderService.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class OrdersController : ControllerBase
    {
        private readonly OrderRepository _repository;

        public OrdersController(OrderRepository repository)
        {
            _repository = repository;
        }

        [HttpGet]
        public IActionResult GetAllOrders()
        {
            return Ok(_repository.GetAllOrders());
        }

        [HttpGet("{id}")]
        public IActionResult GetOrderById(int id)
        {
            var order = _repository.GetOrderById(id);
            if (order == null) return NotFound();
            return Ok(order);
        }

        [HttpPost]
        public IActionResult CreateOrder([FromBody] Order order)
        {
            order.Id = _repository.GetAllOrders().Count() + 1;
            order.OrderDate = DateTime.UtcNow;
            _repository.AddOrder(order);
            return CreatedAtAction(nameof(GetOrderById), new { id = order.Id }, order);
        }
    }
}
