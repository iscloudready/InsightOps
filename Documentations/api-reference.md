# API Reference

## Service Endpoints

### Order Service API
- Base URL: `/api/orders`

#### Endpoints
```markdown
GET /api/orders
- Description: Retrieve all orders
- Query Parameters:
  - status: Filter by order status
  - page: Page number
  - pageSize: Items per page

POST /api/orders
- Description: Create new order
- Request Body: CreateOrderDto
- Response: OrderResponse

GET /api/orders/{id}
- Description: Get order by ID
- Response: OrderDto
```

### Inventory Service API
- Base URL: `/api/inventory`

#### Endpoints
```markdown
GET /api/inventory
- Description: Retrieve all inventory items
- Query Parameters:
  - lowStock: Filter low stock items
  - page: Page number
  - pageSize: Items per page

PUT /api/inventory/{id}/stock
- Description: Update stock level
- Request Body: UpdateStockDto
- Response: InventoryItemDto
```

[View Full API Documentation](complete-api-reference.md)
