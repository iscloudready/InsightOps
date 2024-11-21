# Database Schema Documentation

## Order Service Schema

### Tables
```sql
-- Orders Table
CREATE TABLE Orders (
    Id INT PRIMARY KEY,
    ItemName VARCHAR(100),
    Quantity INT,
    TotalPrice DECIMAL(18,2),
    Status VARCHAR(50),
    OrderDate DATETIME,
    LastUpdated DATETIME
);

-- Indexes
CREATE INDEX IX_Orders_Status ON Orders(Status);
CREATE INDEX IX_Orders_OrderDate ON Orders(OrderDate);
```

## Inventory Service Schema

### Tables
```sql
-- Inventory Items Table
CREATE TABLE InventoryItems (
    Id INT PRIMARY KEY,
    Name VARCHAR(100) UNIQUE,
    Quantity INT,
    Price DECIMAL(18,2),
    MinimumQuantity INT,
    LastRestocked DATETIME
);

-- Indexes
CREATE INDEX IX_InventoryItems_Name ON InventoryItems(Name);
CREATE INDEX IX_InventoryItems_Quantity ON InventoryItems(Quantity);
```

[View Complete Schema Documentation](complete-schema.md)
