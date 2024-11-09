using System.ComponentModel.DataAnnotations;

namespace FrontendService.Models
{
    public class CreateOrderViewModel
    {
        [Required]
        public string ItemName { get; set; }

        [Required]
        [Range(1, int.MaxValue)]
        public int Quantity { get; set; }
    }
}
