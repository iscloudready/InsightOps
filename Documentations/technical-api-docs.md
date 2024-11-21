# API Reference Documentation

## Overview
This document details all API endpoints across the InsightOps platform services.

## Service Endpoints

### Frontend Service (Port 5010)
```yaml
Base URL: http://localhost:5010

Endpoints:
GET /api/dashboard
- Description: Get dashboard metrics and status
- Response: DashboardData

GET /api/health
- Description: Service health check
- Response: HealthStatus
```

### API Gateway (Port 7237)
```yaml
Base URL: http://localhost:7237

Endpoints:
GET /api/gateway/orders
- Description: Get all orders
- Parameters:
  - page (optional): Page number
  - pageSize (optional): Items per page
- Response: OrderList

GET /api/gateway/inventory
- Description: Get inventory items
- Parameters:
  - lowStock (optional): Filter low stock items
- Response: InventoryList
```

### Order Service (Port 5012)
```yaml
Base URL: http://localhost:5012

Endpoints:
GET /api/orders
POST /api/orders
GET /api/orders/{id}
PUT /api/orders/{id}/status

Schemas:
Order {
    id: integer
    itemName: string
    quantity: integer
    status: string
    orderDate: datetime
    totalPrice: decimal
}
```

### Inventory Service (Port 5013)
```yaml
Base URL: http://localhost:5013

Endpoints:
GET /api/inventory
POST /api/inventory
GET /api/inventory/{id}
PUT /api/inventory/{id}/stock

Schemas:
InventoryItem {
    id: integer
    name: string
    quantity: integer
    price: decimal
    minimumQuantity: integer
    lastRestocked: datetime
}
```

## Response Formats

### Success Response
```json
{
    "success": true,
    "data": {
        // Response data
    },
    "timestamp": "2024-11-18T10:24:32Z"
}
```

### Error Response
```json
{
    "success": false,
    "error": {
        "code": "ERROR_CODE",
        "message": "Error description",
        "details": "Additional error details"
    },
    "timestamp": "2024-11-18T10:24:32Z"
}
```

## Authentication
```http
Authorization: Bearer <token>
Content-Type: application/json
```

## API Examples

### Get Dashboard Data
```http
GET /api/dashboard
Response:
{
    "success": true,
    "data": {
        "activeOrders": 10,
        "inventoryCount": 100,
        "systemHealth": "Healthy",
        "responseTime": "120ms"
    }
}
```

### Create Order
```http
POST /api/gateway/orders
Content-Type: application/json

{
    "itemName": "Sample Item",
    "quantity": 5
}

Response:
{
    "success": true,
    "data": {
        "orderId": 123,
        "status": "Pending"
    }
}
```
