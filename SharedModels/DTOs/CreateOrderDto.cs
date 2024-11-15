// SharedModels/DTOs/CreateOrderDto.cs
namespace SharedModels.DTOs;

public class CreateOrderDto
{
    public string ItemName { get; set; } = string.Empty;
    public int Quantity { get; set; }
}