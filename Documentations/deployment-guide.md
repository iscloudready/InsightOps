# Deployment Guide

## Docker Deployment

### Prerequisites
- Docker Engine v20.10+
- Docker Compose v2.0+
- 4GB RAM minimum
- 20GB storage

### Configuration Files
```yaml
# docker-compose.yml
version: '3.8'
services:
  frontend:
    build: ./FrontendService
    ports:
      - "5010:80"
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      
  apigateway:
    build: ./ApiGateway
    ports:
      - "7237:80"

  orderservice:
    build: ./OrderService
    environment:
      - ConnectionStrings__OrderDb=...

  inventoryservice:
    build: ./InventoryService
    environment:
      - ConnectionStrings__InventoryDb=...
```

[View Complete Deployment Guide](docker-deployment.md)
