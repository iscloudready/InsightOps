// ApiGateway/Models/Requests/CreateOrderRequest.cs
namespace ApiGateway.Models.Requests
{
    public class CreateOrderRequest
    {
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; }
    }
}
