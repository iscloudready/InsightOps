using Microsoft.AspNetCore.Mvc;

namespace ApiGateway.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class GatewayController : ControllerBase
    {
        private readonly IHttpClientFactory _clientFactory;

        public GatewayController(IHttpClientFactory clientFactory)
        {
            _clientFactory = clientFactory;
        }

        [HttpGet("orders")]
        public async Task<IActionResult> GetOrders()
        {
            var client = _clientFactory.CreateClient("OrderService");
            var response = await client.GetAsync("/api/orders");
            return StatusCode((int)response.StatusCode, await response.Content.ReadAsStringAsync());
        }

        [HttpGet("inventory")]
        public async Task<IActionResult> GetInventory()
        {
            var client = _clientFactory.CreateClient("InventoryService");
            var response = await client.GetAsync("/api/inventory");
            return StatusCode((int)response.StatusCode, await response.Content.ReadAsStringAsync());
        }
    }
}
