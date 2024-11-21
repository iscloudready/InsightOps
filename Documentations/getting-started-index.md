# Getting Started with InsightOps

## Prerequisites
- [Docker](https://www.docker.com/) (version 20.10 or higher)
- [.NET 8 SDK](https://dotnet.microsoft.com/download)
- [Git](https://git-scm.com/)

## Quick Start Steps

1. **Clone the Repository**
```bash
git clone https://github.com/your-org/insightops.git
cd insightops
```

2. **Setup Environment**
```bash
# Initialize development environment
./scripts/Initialize-Environment.ps1 -Environment Development
```

3. **Start Services**
```bash
docker-compose up -d
```

4. **Access the Dashboard**
- Frontend: http://localhost:5010
- API Gateway: http://localhost:7237
- Swagger UI: http://localhost:5010/swagger

## Service URLs
| Service | Development | Docker |
|---------|-------------|--------|
| Frontend | http://localhost:5010 | http://frontend:80 |
| API Gateway | http://localhost:7237 | http://apigateway:80 |
| Order Service | http://localhost:5012 | http://orderservice:80 |
| Inventory Service | http://localhost:5013 | http://inventoryservice:80 |

## Next Steps
- [Complete Installation Guide](installation.md)
- [Configuration Guide](../technical/deployment/configuration.md)
- [Architecture Overview](../architecture/index.md)
