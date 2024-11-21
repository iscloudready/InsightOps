# Docker Configuration Analysis

## 1. FrontendService Dockerfile
```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
ARG BUILD_CONFIGURATION=Release
USER root
WORKDIR /app
EXPOSE 80
EXPOSE 7144  # This port seems inconsistent with configuration

# Critical Issue: Missing environment configuration 
ENV ASPNETCORE_ENVIRONMENT=Docker
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

... 

# Build Phase
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./FrontendService.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# Final Phase
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
```

## 2. ApiGateway Dockerfile
```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
ARG BUILD_CONFIGURATION=Release
USER root
WORKDIR /app
EXPOSE 80
EXPOSE 7237  # Matches configuration port

# Critical Issue: Missing environment variable for service URLs
ENV ASPNETCORE_ENVIRONMENT=Docker

... rest of Dockerfile ...
```

## 3. PowerShell Script Analysis

### main.ps1 Issues:
```powershell
# Issue 1: Service URL Configuration
$script:CONFIG_PATH = Join-Path $BASE_PATH "Configurations"
# The configuration path might not be correctly set for Docker environment

# Issue 2: Docker Network Check Missing
function Test-Prerequisites {
    [CmdletBinding()]
    param()
    
    try {
        # Need to add Docker network verification
        $dockerPs = docker ps 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Docker is not running" -ForegroundColor Red
            return $false
        }
```

### Required Fixes:

1. **Docker Network Setup**
```powershell
function Initialize-DockerNetwork {
    [CmdletBinding()]
    param()
    
    try {
        # Check if network exists
        $networkName = "insightops-network"
        $network = docker network ls --filter name=$networkName -q
        
        if (-not $network) {
            Write-Host "Creating Docker network: $networkName" -ForegroundColor Yellow
            docker network create $networkName
        }
        
        # Verify network connectivity
        $services = @("frontend", "apigateway", "orderservice", "inventoryservice")
        foreach ($service in $services) {
            $containerName = "insightops_$service"
            if (Test-DockerContainer $containerName) {
                docker network connect $networkName $containerName
            }
        }
    }
    catch {
        Write-Error "Failed to initialize Docker network: $_"
        return $false
    }
}
```

2. **Environment Configuration Check**
```powershell
function Test-ServiceConfiguration {
    [CmdletBinding()]
    param()
    
    try {
        # Verify configuration files
        $configFiles = @(
            "appsettings.json",
            "appsettings.Development.json",
            "appsettings.Docker.json"
        )
        
        foreach ($file in $configFiles) {
            $path = Join-Path $script:CONFIG_PATH $file
            if (-not (Test-Path $path)) {
                Write-Warning "Missing configuration file: $file"
                return $false
            }
            
            # Validate configuration content
            $config = Get-Content $path | ConvertFrom-Json
            if (-not $config.ServiceUrls.ApiGateway) {
                Write-Warning "Missing ApiGateway URL in $file"
                return $false
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to validate service configuration: $_"
        return $false
    }
}
```

3. **Docker Volume Management**
```powershell
function Initialize-DockerVolumes {
    [CmdletBinding()]
    param()
    
    try {
        $volumes = @(
            "postgres_data",
            "grafana_data",
            "prometheus_data",
            "loki_data",
            "tempo_data"
        )
        
        foreach ($volume in $volumes) {
            $volumeName = "insightops_$volume"
            $exists = docker volume ls --filter name=$volumeName -q
            
            if (-not $exists) {
                Write-Host "Creating Docker volume: $volumeName" -ForegroundColor Yellow
                docker volume create $volumeName
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to initialize Docker volumes: $_"
        return $false
    }
}
```

4. **Service Health Check**
```powershell
function Test-ServiceHealth {
    [CmdletBinding()]
    param()
    
    try {
        $services = @{
            "frontend" = "http://localhost:5010/health"
            "apigateway" = "http://localhost:7237/health"
            "orderservice" = "http://localhost:5012/health"
            "inventoryservice" = "http://localhost:5013/health"
        }
        
        foreach ($service in $services.GetEnumerator()) {
            try {
                $response = Invoke-WebRequest -Uri $service.Value -Method GET -UseBasicParsing
                if ($response.StatusCode -eq 200) {
                    Write-Host "✓ $($service.Key) is healthy" -ForegroundColor Green
                } else {
                    Write-Host "⨯ $($service.Key) returned status code: $($response.StatusCode)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "⨯ $($service.Key) is not responding" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Error "Failed to check service health: $_"
    }
}
```

5. **Docker Compose Updates**
```yaml
version: '3.8'
services:
  frontend:
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ServiceUrls__ApiGateway=http://apigateway
      - ServiceUrls__OrderService=http://orderservice
      - ServiceUrls__InventoryService=http://inventoryservice
    networks:
      - insightops-network
    depends_on:
      apigateway:
        condition: service_healthy

  apigateway:
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ServiceUrls__OrderService=http://orderservice
      - ServiceUrls__InventoryService=http://inventoryservice
    networks:
      - insightops-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
      interval: 10s
      timeout: 5s
      retries: 3

networks:
  insightops-network:
    name: insightops-network
```

6. **Update Initialize-Environment Function**
```powershell
function Initialize-Environment {
    [CmdletBinding()]
    param(
        [string]$Environment = "Development",
        [switch]$Force
    )
    
    try {
        # 1. Check Docker
        if (-not (Test-DockerRunning)) {
            throw "Docker is not running"
        }
        
        # 2. Initialize Network
        if (-not (Initialize-DockerNetwork)) {
            throw "Failed to initialize Docker network"
        }
        
        # 3. Initialize Volumes
        if (-not (Initialize-DockerVolumes)) {
            throw "Failed to initialize Docker volumes"
        }
        
        # 4. Check Configuration
        if (-not (Test-ServiceConfiguration)) {
            throw "Invalid service configuration"
        }
        
        # 5. Build and Start Services
        Write-Host "Building and starting services..." -ForegroundColor Cyan
        docker-compose -f $script:DOCKER_COMPOSE_PATH up -d --build
        
        # 6. Verify Health
        Start-Sleep -Seconds 10  # Wait for services to initialize
        Test-ServiceHealth
        
        return $true
    }
    catch {
        Write-Error "Failed to initialize environment: $_"
        return $false
    }
}
```

The main issues appear to be:

1. Docker network connectivity and service discovery
2. Environment configuration not being properly passed to containers
3. Missing health checks in service containers
4. Volume permissions and persistence
5. Service dependency order

Would you like me to:
1. Create an updated version of the docker-compose.yml with all these fixes?
2. Provide a complete set of updated PowerShell scripts?
3. Create a new deployment verification script?
4. Update the Dockerfiles with proper configurations?