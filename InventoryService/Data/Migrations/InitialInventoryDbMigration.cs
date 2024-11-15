// InventoryService/Data/Migrations/YYYYMMDDHHMMSSInitialInventoryDbMigration.cs
using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

namespace InventoryService.Data.Migrations
{
    public partial class InitialInventoryDbMigration : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Create InventoryItems table
            migrationBuilder.CreateTable(
                name: "InventoryItems",
                columns: table => new
                {
                    // Primary key with auto-increment
                    Id = table.Column<int>(
                        type: "integer",
                        nullable: false
                    ).Annotation("Npgsql:ValueGenerationStrategy",
                        NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),

                    // Item name with max length and uniqueness
                    Name = table.Column<string>(
                        type: "character varying(100)",
                        maxLength: 100,
                        nullable: false),

                    // Current quantity in stock
                    Quantity = table.Column<int>(
                        type: "integer",
                        nullable: false),

                    // Price with decimal precision
                    Price = table.Column<decimal>(
                        type: "numeric(18,2)",
                        precision: 18,
                        scale: 2,
                        nullable: false),

                    // Last restocked timestamp
                    LastRestocked = table.Column<DateTime>(
                        type: "timestamp with time zone",
                        nullable: false,
                        defaultValueSql: "CURRENT_TIMESTAMP"),

                    // Minimum quantity threshold for low stock alerts
                    MinimumQuantity = table.Column<int>(
                        type: "integer",
                        nullable: false,
                        defaultValue: 10)
                },
                constraints: table =>
                {
                    // Set primary key constraint
                    table.PrimaryKey("PK_InventoryItems", x => x.Id);
                });

            // Create unique index on Name
            migrationBuilder.CreateIndex(
                name: "IX_InventoryItems_Name",
                table: "InventoryItems",
                column: "Name",
                unique: true);

            // Create index on Quantity for low stock queries
            migrationBuilder.CreateIndex(
                name: "IX_InventoryItems_Quantity",
                table: "InventoryItems",
                column: "Quantity");

            // Add check constraint for non-negative quantity
            migrationBuilder.Sql(
                "ALTER TABLE \"InventoryItems\" ADD CONSTRAINT \"CK_InventoryItems_Quantity_NonNegative\" CHECK (\"Quantity\" >= 0)");

            // Add check constraint for non-negative price
            migrationBuilder.Sql(
                "ALTER TABLE \"InventoryItems\" ADD CONSTRAINT \"CK_InventoryItems_Price_NonNegative\" CHECK (\"Price\" >= 0)");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Drop check constraints first
            migrationBuilder.Sql(
                "ALTER TABLE \"InventoryItems\" DROP CONSTRAINT IF EXISTS \"CK_InventoryItems_Quantity_NonNegative\"");
            migrationBuilder.Sql(
                "ALTER TABLE \"InventoryItems\" DROP CONSTRAINT IF EXISTS \"CK_InventoryItems_Price_NonNegative\"");

            // Drop the InventoryItems table and all related indexes
            migrationBuilder.DropTable(
                name: "InventoryItems");
        }
    }
}