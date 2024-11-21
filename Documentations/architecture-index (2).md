# InsightOps Architecture

## System Overview

```mermaid
graph TB
    subgraph Frontend
        UI[User Interface]
        DM[Dashboard Manager]
        MM[Metrics Monitor]
    end

    subgraph Gateway
        AG[API Gateway]
        LB[Load Balancer]
    end

    subgraph Services
        OS[Order Service]
        IS[Inventory Service]
    end

    subgraph Monitoring
        PR[Prometheus]
        LK[Loki]
        TP[Tempo]
    end

    UI --> DM
    DM --> MM
    DM --> AG
    AG --> OS
    AG --> IS
    MM --> PR
    OS --> PR
    IS --> PR
```

## Core Components

### Frontend Service
- ASP.NET Core MVC application
- Real-time dashboard
- Docker management interface
- Service health monitoring

### API Gateway
- Request routing
- Load balancing
- Service aggregation
- Error handling

### Microservices
- Order Service
- Inventory Service
- Independent databases
- Domain-specific logic

### Monitoring Stack
- Prometheus (metrics)
- Loki (logging)
- Tempo (tracing)

## Data Flow

```mermaid
sequenceDiagram
    participant Browser
    participant Frontend
    participant Gateway
    participant Services
    participant DB

    Browser->>Frontend: Request Dashboard
    activate Frontend
    Frontend->>Gateway: Get Data
    activate Gateway
    par Orders
        Gateway->>Services: Get Orders
        Services->>DB: Query
        DB-->>Services: Data
        Services-->>Gateway: Response
    and Inventory
        Gateway->>Services: Get Inventory
        Services->>DB: Query
        DB-->>Services: Data
        Services-->>Gateway: Response
    end
    Gateway-->>Frontend: Aggregated Data
    deactivate Gateway
    Frontend-->>Browser: Update UI
    deactivate Frontend
```

## Technology Stack
- .NET 8
- Docker
- PostgreSQL
- EF Core
- OpenTelemetry
- SignalR (ready)

## Design Patterns
- Microservices Architecture
- Gateway Pattern
- Repository Pattern
- CQRS (for queries)
- Circuit Breaker
- Retry Pattern

[Continue to System Design Details](system-design.md)
