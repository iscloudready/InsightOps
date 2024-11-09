namespace FrontendService.Models
{
    // Frontend/Models/DTOs.cs
    public class OrderDto
    {
        public int Id { get; set; }
        public string ItemName { get; set; }
        public int Quantity { get; set; }
        public DateTime OrderDate { get; set; }
    }
}
