# Database Schema Documentation

## Overview
InsightOps uses PostgreSQL databases for both Order and Inventory services.

## Order Service Schema

```sql
-- Orders Table
CREATE TABLE Orders (
    Id SERIAL PRIMARY KEY,
    ItemName VARCHAR(100) NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    TotalPrice DECIMAL(18,2) NOT NULL,
    Status VARCHAR(50) NOT NULL,
    OrderDate TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    LastModified TIMESTAMP NOT NULL,
    Version INT NOT NULL DEFAULT 1
);

-- Order History Table
CREATE TABLE OrderHistory (
    Id SERIAL PRIMARY KEY,
    OrderId INT REFERENCES Orders(Id),
    Status VARCHAR(50) NOT NULL,
    ChangeDate TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ChangedBy VARCHAR(100) NOT NULL,
    Notes TEXT
);

-- Indexes
CREATE INDEX idx_orders_status ON Orders(Status);
CREATE INDEX idx_orders_date ON Orders(OrderDate);
CREATE INDEX idx_orderhistory_orderid ON OrderHistory(OrderId);
```

## Inventory Service Schema

```sql
-- Inventory Items Table
CREATE TABLE InventoryItems (
    Id SERIAL PRIMARY KEY,
    Name VARCHAR(100) NOT NULL UNIQUE,
    Quantity INT NOT NULL DEFAULT 0,
    Price DECIMAL(18,2) NOT NULL,
    MinimumQuantity INT NOT NULL DEFAULT 10,
    LastRestocked TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Version INT NOT NULL DEFAULT 1
);

-- Stock Movement Table
CREATE TABLE StockMovements (
    Id SERIAL PRIMARY KEY,
    ItemId INT REFERENCES InventoryItems(Id),
    QuantityChanged INT NOT NULL,
    MovementType VARCHAR(50) NOT NULL,
    ReferenceNumber VARCHAR(100),
    MovementDate TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Notes TEXT
);

-- Indexes
CREATE INDEX idx_inventory_name ON InventoryItems(Name);
CREATE INDEX idx_inventory_quantity ON InventoryItems(Quantity);
CREATE INDEX idx_stockmovements_itemid ON StockMovements(ItemId);
```

## Entity Framework Configurations

### Order Service
```csharp
public class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.ToTable("Orders");
        
        builder.Property(o => o.ItemName)
            .IsRequired()
            .HasMaxLength(100);
            
        builder.Property(o => o.Status)
            .IsRequired()
            .HasConversion<string>();
            
        builder.HasMany(o => o.History)
            .WithOne()
            .HasForeignKey(h => h.OrderId);
    }
}
```

### Inventory Service
```csharp
public class InventoryItemConfiguration : IEntityTypeConfiguration<InventoryItem>
{
    public void Configure(EntityTypeBuilder<InventoryItem> builder)
    {
        builder.ToTable("InventoryItems");
        
        builder.Property(i => i.Name)
            .IsRequired()
            .HasMaxLength(100);
            
        builder.HasIndex(i => i.Name)
            .IsUnique();
            
        builder.HasMany(i => i.StockMovements)
            .WithOne()
            .HasForeignKey(s => s.ItemId);
    }
}
```

## Database Migrations
```bash
# Order Service
dotnet ef migrations add InitialCreate -c OrderDbContext
dotnet ef database update

# Inventory Service
dotnet ef migrations add InitialCreate -c InventoryDbContext
dotnet ef database update
```

## Backup and Restore
```bash
# Backup
pg_dump -U insightops_user -d insightops_db > backup.sql

# Restore
psql -U insightops_user -d insightops_db < backup.sql
```
