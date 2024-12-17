// InventoryService/Data/InventoryDbContext.cs
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using InventoryService.Models;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace InventoryService.Data
{
    public class InventoryDbContext : DbContext
    {
        private readonly ILogger<InventoryDbContext> _logger;

        public InventoryDbContext(
            DbContextOptions<InventoryDbContext> options,
            ILogger<InventoryDbContext> logger) : base(options)
        {
            _logger = logger;
        }

        public DbSet<InventoryItem> InventoryItems { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            try
            {
                // Set default schema for all tables
                modelBuilder.HasDefaultSchema("inventory");

                modelBuilder.Entity<InventoryItem>(entity =>
                {
                    // Primary Key
                    entity.HasKey(e => e.Id);

                    // Properties
                    entity.Property(e => e.Name)
                        .IsRequired()
                        .HasMaxLength(100)
                        .HasComment("Name of the inventory item");

                    entity.Property(e => e.Quantity)
                        .IsRequired()
                        .HasComment("Current quantity in stock");

                    entity.Property(e => e.Price)
                        .HasColumnType("decimal(18,2)")
                        .IsRequired()
                        .HasComment("Price of the item");

                    entity.Property(e => e.LastRestocked)
                        .IsRequired()
                        .HasDefaultValueSql("CURRENT_TIMESTAMP")
                        .HasComment("Last restock date and time");

                    entity.Property(e => e.MinimumQuantity)
                        .IsRequired()
                        .HasDefaultValue(10)
                        .HasComment("Minimum quantity threshold for reordering");

                    // Indexes
                    entity.HasIndex(e => e.Name)
                        .IsUnique()
                        .HasDatabaseName("IX_InventoryItems_Name");

                    entity.HasIndex(e => e.Quantity)
                        .HasDatabaseName("IX_InventoryItems_Quantity");

                    // Table configuration
                    entity.ToTable("InventoryItems", schema: "inventory", tb =>
                    {
                        tb.HasComment("Stores inventory item information");
                    });
                });

                // Additional configuration logging
                _logger.LogInformation("Successfully configured InventoryItem entity");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during model creation for InventoryDbContext");
                throw;
            }
        }

        public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        {
            try
            {
                var result = await base.SaveChangesAsync(cancellationToken);
                _logger.LogInformation("Successfully saved changes to database");
                return result;
            }
            catch (DbUpdateException ex)
            {
                _logger.LogError(ex, "Error saving changes to database");
                throw;
            }
        }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            optionsBuilder.LogTo(
                message => _logger.LogDebug(message),
                LogLevel.Debug,
                DbContextLoggerOptions.DefaultWithUtcTime);

            base.OnConfiguring(optionsBuilder);
        }
    }
}