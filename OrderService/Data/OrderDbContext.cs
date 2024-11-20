// OrderService/Data/OrderDbContext.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using OrderService.Models;

namespace OrderService.Data
{
    public class OrderDbContext : DbContext
    {
        private readonly ILogger<OrderDbContext> _logger;

        public OrderDbContext(
            DbContextOptions<OrderDbContext> options,
            ILogger<OrderDbContext> logger) : base(options)
        {
            _logger = logger;
        }

        public DbSet<Order> Orders { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            try
            {
                modelBuilder.Entity<Order>(entity =>
                {
                    // Primary Key
                    entity.HasKey(e => e.Id);

                    // Properties
                    entity.Property(e => e.ItemName)
                        .IsRequired()
                        .HasMaxLength(100)
                        .HasComment("Name of the ordered item");

                    entity.Property(e => e.Quantity)
                        .IsRequired()
                        .HasComment("Quantity of items ordered");

                    entity.Property(e => e.TotalPrice)
                        .HasColumnType("decimal(18,2)")
                        .IsRequired()
                        .HasComment("Total price of the order");

                    entity.Property(e => e.Status)
                        .IsRequired()
                        .HasMaxLength(50)
                        .HasDefaultValue("Pending")
                        .HasComment("Current status of the order");

                    entity.Property(e => e.OrderDate)
                        .IsRequired()
                        .HasDefaultValueSql("CURRENT_TIMESTAMP")
                        .HasComment("Date and time when the order was created");

                    // Indexes for better query performance
                    entity.HasIndex(e => e.Status)
                        .HasDatabaseName("IX_Orders_Status");
                    entity.HasIndex(e => e.OrderDate)
                        .HasDatabaseName("IX_Orders_OrderDate");

                    // Table configuration
                    entity.ToTable("Orders", b => b.HasComment("Stores all order information"));
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during model creation");
                throw;
            }
        }

        public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        {
            try
            {
                return await base.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateException ex)
            {
                _logger.LogError(ex, "Error saving changes to database");
                throw new DbUpdateException("Failed to save changes to the database", ex);
            }
        }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            optionsBuilder.EnableSensitiveDataLogging(false);
            optionsBuilder.EnableDetailedErrors(false);
        }
    }
}