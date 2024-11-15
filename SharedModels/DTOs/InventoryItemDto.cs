// SharedModels/DTOs/InventoryItemDto.cs
namespace SharedModels.DTOs;

public class InventoryItemDto
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public int Quantity { get; set; }
    public decimal Price { get; set; }
    public bool IsAvailable => Quantity > 0;
}