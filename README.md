
# InsightOps

**InsightOps** is an observability-driven project designed to showcase advanced monitoring and diagnostics in a microservices architecture. Leveraging OpenTelemetry, Prometheus, and Grafana, this project provides a robust demonstration of real-time metrics, distributed tracing, and health monitoring across services.

## Table of Contents
- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Setup and Prerequisites](#setup-and-prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Project](#running-the-project)
- [Prometheus and Grafana Setup](#prometheus-and-grafana-setup)
- [Endpoints and Observability](#endpoints-and-observability)
- [Contributing](#contributing)

---

## Project Overview

InsightOps provides real-time metrics, tracing, and logging in an ASP.NET Core-based microservices environment. The services, including `OrderService` and `InventoryService`, are instrumented with OpenTelemetry for observability, and data is stored in PostgreSQL. Prometheus scrapes metrics, and Grafana visualizes them, offering a powerful setup for monitoring and diagnostics.

## Architecture

![Architecture Diagram](./docs/architecture.png) <!-- Replace with actual architecture diagram path if available -->

### Quick Start
```powershell
# Clone and initialize
git clone https://github.com/yourusername/InsightOps.git
cd InsightOps
.\scripts\init-insightOps.ps1
# For development setup with detailed output
.\scripts\init-insightOps.ps1 -Development
# Force configuration recreation
.\scripts\init-insightOps.ps1 -ForceRecreate
```

### Prerequisites Check
```powershell
# Check all prerequisites
.\scripts\utils\check-prereqs.ps1
# Detailed check with versions
.\scripts\utils\check-prereqs.ps1 -Detailed
```

### Environment Management
```powershell
# Setup development environment
.\scripts\utils\setup-environment.ps1 -Environment Development
# Setup staging environment
.\scripts\utils\setup-environment.ps1 -Environment Staging
# Setup production environment
.\scripts\utils\setup-environment.ps1 -Environment Production
```
### Management Commands
```powershell
# Start all services
.\scripts\docker-commands.ps1
# Select option 1
# View service health
.\scripts\docker-commands.ps1
# Select option 15
# View logs with follow
.\scripts\docker-commands.ps1
# Select option 17
# Check service status
.\scripts\docker-commands.ps1
# Select option 3
```
### Cleanup Operations
```powershell
# Basic cleanup (keeps data and configs)
.\scripts\utils\cleanup.ps1
# Full cleanup including data
.\scripts\utils\cleanup.ps1 -RemoveData
# Complete cleanup including configurations
.\scripts\utils\cleanup.ps1 -RemoveData -RemoveConfigs -Force
```
### Environment-Specific URLs
|
 Service 
|
 Development 
|
 Staging 
|
 Production 
|
|
---------
|
------------
|
----------
|
------------
|
|
 Frontend 
|
 http://localhost:5010 
|
 https://staging-frontend:5010 
|
 https://frontend:443 
|
|
 API Gateway 
|
 http://localhost:5011 
|
 https://staging-gateway:5011 
|
 https://gateway:443 
|
|
 Order Service 
|
 http://localhost:5012 
|
 https://staging-orders:5012 
|
 https://orders:443 
|
|
 Inventory Service 
|
 http://localhost:5013 
|
 https://staging-inventory:5013 
|
 https://inventory:443 
|
|
 Grafana 
|
 http://localhost:3001 
|
 https://staging-grafana:3001 
|
 https://grafana:443 
|
|
 Prometheus 
|
 http://localhost:9091 
|
 https://staging-prometheus:9091 
|
 https://prometheus:443 
|

### Access Credentials
|
 Environment 
|
 Username 
|
 Password 
|
|
------------
|
----------
|
-----------
|
|
 Development 
|
 admin 
|
 InsightOps2024! 
|
|
 Staging 
|
 admin 
|
 StageOps2024! 
|
|
 Production 
|
 admin 
|
 [Contact Admin] 
|

## Setup and Prerequisites

Ensure you have the following tools installed:
- [.NET 6 SDK](https://dotnet.microsoft.com/download/dotnet/6.0)
- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Kubernetes (optional for deployment)](https://kubernetes.io/docs/setup/)
- [Prometheus](https://prometheus.io/download/)
- [Grafana](https://grafana.com/grafana/download)

## Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/InsightOps.git
cd InsightOps
```

### Step 2: Set up Solution and Projects

Run the following commands to create the solution, microservices, and structure the project:

```bash
dotnet new sln -o ObservabilityDemo
cd ObservabilityDemo

# Create projects
dotnet new mvc -n FrontendService
dotnet new webapi -n ApiGateway
dotnet new webapi -n OrderService
dotnet new webapi -n InventoryService

# Add projects to the solution
dotnet sln add FrontendService/FrontendService.csproj
dotnet sln add ApiGateway/ApiGateway.csproj
dotnet sln add OrderService/OrderService.csproj
dotnet sln add InventoryService/InventoryService.csproj
```

### Step 3: Configure Environment Variables

Update the `appsettings.json` files in both `OrderService` and `InventoryService` projects to include the PostgreSQL connection string:

```json
"ConnectionStrings": {
  "Postgres": "Host=postgres;Database=demo_db;Username=demo_user;Password=demo_password"
}
```

### Step 4: Install Dependencies

Navigate to each service directory (`OrderService` and `InventoryService`) and install required NuGet packages.

```bash
cd OrderService
dotnet restore
dotnet add package Microsoft.EntityFrameworkCore
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add package OpenTelemetry.Extensions.Hosting
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
dotnet add package OpenTelemetry.Exporter.Prometheus.AspNetCore --prerelease
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

Repeat the same commands for the `InventoryService` project.

### Step 5: Set Up Docker Containers

#### Docker Compose for PostgreSQL, Prometheus, and Grafana

In the project root, create a `docker-compose.yml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:13
    environment:
      POSTGRES_USER: demo_user
      POSTGRES_PASSWORD: demo_password
      POSTGRES_DB: demo_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

volumes:
  postgres_data:
```

### Step 6: Configure Prometheus

In `./prometheus/prometheus.yml`, configure Prometheus to scrape metrics from each service:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'OrderService'
    static_configs:
      - targets: ['host.docker.internal:5000']

  - job_name: 'InventoryService'
    static_configs:
      - targets: ['host.docker.internal:5001']
```

## Running the Project

### Step 1: Start Services with Docker Compose

```bash
docker-compose up -d
```

### Step 2: Run the .NET Microservices

In separate terminals, navigate to `OrderService` and `InventoryService` directories and run each:

```bash
cd OrderService
dotnet run

cd InventoryService
dotnet run
```

The services should now be running on `http://localhost:5000` for `OrderService` and `http://localhost:5001` for `InventoryService`.

### Step 3: Access Prometheus and Grafana

- **Prometheus**: [http://localhost:9090](http://localhost:9090)
- **Grafana**: [http://localhost:3000](http://localhost:3000)

Use default Grafana credentials (`admin/admin`) to log in, then add Prometheus as a data source.

## Endpoints and Observability

- **Metrics Endpoint**: Each service exposes Prometheus metrics at `/metrics`.
- **Tracing**: OpenTelemetry traces are exported to the OTLP endpoint.
- **Health Checks**: Verify each service’s health at `/health`.

## Contributing

Contributions are welcome! Please follow the standard GitHub fork and pull request process.

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/your-feature`).
3. Commit your changes.
4. Push to your fork and submit a pull request.

## Directory structure

InsightOps/
├── InsightOps.sln              # Solution file
├── README.md                   # Project readme with instructions
├── LICENSE                     # Project license
├── Configurations/             # For Docker and Prometheus configs
│   ├── docker-compose.yml
│   └── prometheus.yml
├── FrontendService/            # MVC project for front-end application
│   └── FrontendService.csproj
├── ApiGateway/                 # API Gateway project
│   └── ApiGateway.csproj
├── OrderService/               # Order Service microservice
│   └── OrderService.csproj
├── InventoryService/           # Inventory Service microservice
│   └── InventoryService.csproj
├── .git/                       # Git folder for version control
├── .vs/                        # Visual Studio-related files
└── docs/                       # Documentation and architecture diagrams
    └── architecture.png        # Architecture diagram (if available)

---

This guide should help you get InsightOps up and running with full observability.
