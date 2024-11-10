# InsightOps

**InsightOps** is an observability-driven project showcasing advanced monitoring and diagnostics in a microservices architecture. Built with .NET 8, this solution leverages OpenTelemetry, Prometheus, and Grafana for comprehensive observability.

## Table of Contents
- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Project](#running-the-project)
- [Monitoring Setup](#monitoring-setup)
- [Useful Commands](#useful-commands)
- [Directory Structure](#directory-structure)

## Project Overview

InsightOps demonstrates real-time metrics, tracing, and logging in an ASP.NET Core-based microservices environment. The services include:
- Frontend Service (MVC)
- API Gateway
- Order Service
- Inventory Service
- Monitoring Stack (Prometheus, Grafana, Loki, Tempo)

## Prerequisites

- .NET 8 SDK
- Docker Desktop
- Visual Studio 2022
- PowerShell 7+ (recommended)

## Installation

1. Clone the repository:
```powershell
git clone https://github.com/yourusername/InsightOps.git
cd InsightOps
```

2. Create required directories:
```powershell
# Create Grafana provisioning directories
New-Item -ItemType Directory -Force -Path "./Configurations/grafana/provisioning/datasources"
New-Item -ItemType Directory -Force -Path "./Configurations/grafana/provisioning/dashboards"
```

3. Set up Grafana dashboards:
```powershell
# Copy dashboard configurations
Set-Content -Path "./Configurations/grafana/provisioning/dashboards/dashboard.yml" -Value $dashboardConfig
Set-Content -Path "./Configurations/grafana/provisioning/dashboards/service-overview.json" -Value $serviceOverviewDashboard
Set-Content -Path "./Configurations/grafana/provisioning/dashboards/order-service.json" -Value $orderServiceDashboard
Set-Content -Path "./Configurations/grafana/provisioning/dashboards/logs-overview.json" -Value $logsOverviewDashboard
Set-Content -Path "./Configurations/grafana/provisioning/dashboards/system-metrics.json" -Value $systemMetricsDashboard
```

## Running the Project

1. Start all services:
```powershell
cd Configurations
docker-compose up -d --build
```

2. Check service status:
```powershell
docker-compose ps
```

3. Monitor service logs:
```powershell
# View logs for specific services
docker logs insightops_frontend
docker logs insightops_gateway
docker logs insightops_orders
docker logs insightops_inventory
docker logs insightops_db

# Follow logs in real-time
docker logs -f insightops_frontend
```

## Access Points

Launch these services in your browser:
```powershell
# Frontend Application
Start-Process "http://localhost:5010"

# API Gateway
Start-Process "http://localhost:5011"

# Order Service
Start-Process "http://localhost:5012"

# Inventory Service
Start-Process "http://localhost:5013"

# Grafana (admin/InsightOps2024!)
Start-Process "http://localhost:3001"

# Prometheus
Start-Process "http://localhost:9091"

# Loki
Start-Process "http://localhost:3101"
```

## Monitoring Stack

### Grafana Dashboards
1. Service Overview
   - CPU and Memory usage
   - Request rates and latencies
   - Service health status

2. Order Service Dashboard
   - Request durations
   - Error rates
   - Order processing metrics

3. Logs Overview
   - Centralized logging
   - Error tracking
   - Service-specific filtering

4. System Metrics
   - Infrastructure metrics
   - Resource utilization
   - System health

## Useful Commands

### Docker Management
```powershell
# Stop all services
docker-compose down

# Stop and remove everything (including volumes)
docker-compose down -v

# Rebuild specific service
docker-compose up -d --build service_name

# View container stats
docker stats

# Enter container shell
docker exec -it container_name sh

# Clean up Docker system
docker system prune -f
```

### Service Management
```powershell
# Restart specific service
docker-compose restart service_name

# View service logs
docker-compose logs service_name

# Scale service
docker-compose up -d --scale service_name=2
```

### Monitoring Commands
```powershell
# Check service health
curl http://localhost:5010/health
curl http://localhost:5011/health
curl http://localhost:5012/health
curl http://localhost:5013/health

# View Prometheus metrics
curl http://localhost:5012/metrics
```

## Directory Structure

```
InsightOps/
├── InsightOps.sln
├── Configurations/
│   ├── docker-compose.yml
│   ├── prometheus.yml
│   ├── tempo.yaml
│   ├── loki-config.yaml
│   └── grafana/
│       └── provisioning/
│           ├── dashboards/
│           │   ├── dashboard.yml
│           │   ├── service-overview.json
│           │   ├── order-service.json
│           │   ├── logs-overview.json
│           │   └── system-metrics.json
│           └── datasources/
│               └── datasources.yaml
├── FrontendService/
├── ApiGateway/
├── OrderService/
└── InventoryService/
```

## Database Connection

```
Host: localhost
Port: 5433
Database: insightops_db
Username: insightops_user
Password: insightops_pwd
```

## Monitoring URLs

| Service     | URL                     | Notes                    |
|------------|-------------------------|--------------------------|
| Frontend   | http://localhost:5010   | Main application        |
| API Gateway| http://localhost:5011   | API documentation       |
| Orders     | http://localhost:5012   | Order service          |
| Inventory  | http://localhost:5013   | Inventory service      |
| Grafana    | http://localhost:3001   | admin/InsightOps2024!  |
| Prometheus | http://localhost:9091   | Metrics storage        |
| Loki       | http://localhost:3101   | Log aggregation        |

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/name`)
3. Commit changes (`git commit -am 'Add feature'`)
4. Push branch (`git push origin feature/name`)
5. Create Pull Request

---

For more detailed information about specific components or configurations, please refer to the relevant documentation in the `docs` directory.
