// FrontendService/Models/Requests/CreateOrderDto.cs
namespace FrontendService.Models.Requests
{
    public class CreateOrderDto
    {
        public string ItemName { get; set; } = string.Empty;
        public int Quantity { get; set; }
    }
}