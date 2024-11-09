// OrderService/Data/OrderDbContext.cs
using Microsoft.EntityFrameworkCore;
using OrderService.Models;

public class OrderDbContext : DbContext
{
    public OrderDbContext(DbContextOptions<OrderDbContext> options) : base(options) { }

    public DbSet<Order> Orders { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Order>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id)
                .UseIdentityColumn() // This makes the ID auto-increment
                .IsRequired();

            entity.Property(e => e.ItemName)
                .IsRequired()
                .HasMaxLength(100);

            entity.Property(e => e.OrderDate)
                .HasDefaultValueSql("CURRENT_TIMESTAMP");
        });
    }
}