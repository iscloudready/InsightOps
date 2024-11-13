# Core.psm1
# Purpose: Core configuration and utility functions for InsightOps

# Base paths - corrected path resolution
$script:PROJECT_ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:CONFIG_PATH = Join-Path -Path $script:PROJECT_ROOT -ChildPath "Configurations"

# Output path information for debugging
Write-Verbose "PSScriptRoot: $PSScriptRoot"
Write-Verbose "Project Root: $script:PROJECT_ROOT"
Write-Verbose "Config Path: $script:CONFIG_PATH"

# Environment Settings
$script:NAMESPACE = "insightops"
$script:DEFAULT_ENVIRONMENT = "Development"

# Required paths - with explicit path joining
$script:REQUIRED_PATHS = @(
    $script:CONFIG_PATH,
    (Join-Path -Path $script:CONFIG_PATH -ChildPath "grafana"),
    (Join-Path -Path $script:CONFIG_PATH -ChildPath "init-scripts"),
    (Join-Path -Path $script:CONFIG_PATH -ChildPath "tempo"),
    (Join-Path -Path $script:CONFIG_PATH -ChildPath "loki"),
    (Join-Path -Path $script:CONFIG_PATH -ChildPath "prometheus")
)

# Required configuration files
$script:REQUIRED_FILES = @{
    "docker-compose.yml" = Join-Path -Path $script:CONFIG_PATH -ChildPath "docker-compose.yml"
    "tempo.yaml" = Join-Path -Path $script:CONFIG_PATH -ChildPath "tempo/tempo.yaml"
    "loki-config.yaml" = Join-Path -Path $script:CONFIG_PATH -ChildPath "loki/loki-config.yaml"
    "prometheus.yml" = Join-Path -Path $script:CONFIG_PATH -ChildPath "prometheus/prometheus.yml"
    ".env.development" = Join-Path -Path $script:CONFIG_PATH -ChildPath ".env.development"
    ".env.production" = Join-Path -Path $script:CONFIG_PATH -ChildPath ".env.production"
}

# Initialize function to ensure paths exist
function Initialize-CorePaths {
    if (-not (Test-Path $script:CONFIG_PATH)) {
        New-Item -ItemType Directory -Path $script:CONFIG_PATH -Force | Out-Null
        Write-Verbose "Created configuration directory: $script:CONFIG_PATH"
    }

    foreach ($path in $script:REQUIRED_PATHS) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Verbose "Created directory: $path"
        }
    }
}

# Call initialization
Initialize-CorePaths

# Service Configuration with health checks
$script:SERVICES = @{
    Database = @{
        Name = "postgres"
        Container = "${script:NAMESPACE}_db"
        Port = "5433:5432"
        HealthCheck = "pg_isready -U insightops_user -d insightops_db"
    }
    Frontend = @{
        Name = "frontend"
        Container = "${script:NAMESPACE}_frontend"
        Port = "5010:80"
        HealthCheck = "curl -f http://localhost:80/health"
    }
    ApiGateway = @{
        Name = "api_gateway"
        Container = "${script:NAMESPACE}_gateway"
        Port = "5011:80"
        HealthCheck = "curl -f http://localhost:80/health"
    }
    OrderService = @{
        Name = "order_service"
        Container = "${script:NAMESPACE}_orders"
        Port = "5012:80"
        HealthCheck = "curl -f http://localhost:80/health"
    }
    InventoryService = @{
        Name = "inventory_service"
        Container = "${script:NAMESPACE}_inventory"
        Port = "5013:80"
        HealthCheck = "curl -f http://localhost:80/health"
    }
    Grafana = @{
        Name = "grafana"
        Container = "${script:NAMESPACE}_grafana"
        Port = "3001:3000"
        HealthCheck = "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health"
    }
    Prometheus = @{
        Name = "prometheus"
        Container = "${script:NAMESPACE}_prometheus"
        Port = "9091:9090"
        HealthCheck = "wget --no-verbose --tries=1 --spider http://localhost:9090/-/healthy"
    }
    Loki = @{
        Name = "loki"
        Container = "${script:NAMESPACE}_loki"
        Port = "3101:3100"
        HealthCheck = "wget --no-verbose --tries=1 --spider http://localhost:3100/ready"
    }
    Tempo = @{
        Name = "tempo"
        Container = "${script:NAMESPACE}_tempo"
        Ports = @{
            OTLP = "4317:4317"
            HTTP = "4318:4318"
            Query = "3200:3200"
        }
        HealthCheck = "wget --no-verbose --tries=1 --spider http://localhost:3200/ready"
    }
}

function Test-Configuration {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nChecking configurations..." -ForegroundColor Cyan

        $configurationValid = $true
        
        # Check base directory
        Write-Host "`nChecking Directories:" -ForegroundColor Cyan
        foreach ($dir in $script:REQUIRED_PATHS) {
            $dirName = Split-Path $dir -Leaf
            if (Test-Path $dir) {
                Write-Host "  [OK] $dirName" -ForegroundColor Green
            } else {
                Write-Host "  [MISSING] $dirName" -ForegroundColor Red
                $configurationValid = $false
            }
        }

        # Check files
        Write-Host "`nChecking Files:" -ForegroundColor Cyan
        foreach ($file in $script:REQUIRED_FILES.GetEnumerator()) {
            if (Test-Path $file.Value) {
                Write-Host "  [OK] $($file.Key)" -ForegroundColor Green
            } else {
                Write-Host "  [MISSING] $($file.Key)" -ForegroundColor Red
                $configurationValid = $false
            }
        }

        if (-not $configurationValid) {
            Write-Host "`nSome configurations are missing. Running initialization..." -ForegroundColor Yellow
            Initialize-DefaultConfigurations
            return $false
        }

        Write-Host "`nAll configurations verified successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Configuration check failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Debug $_.ScriptStackTrace
        return $false
    }
}

function Initialize-DefaultConfigurations {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nInitializing configurations in: $script:CONFIG_PATH" -ForegroundColor Cyan

        # Create directories
        foreach ($dir in $script:REQUIRED_PATHS) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Host "  Created directory: $(Split-Path $dir -Leaf)" -ForegroundColor Green
            }
        }

        # Create files
        foreach ($file in $script:REQUIRED_FILES.GetEnumerator()) {
            if (-not (Test-Path $file.Value)) {
                $content = switch ($file.Key) {
                    "prometheus.yml" { Get-PrometheusConfig }
                    "loki-config.yaml" { Get-LokiConfig }
                    "tempo.yaml" { Get-TempoConfig }
                    "docker-compose.yml" { Get-DockerComposeConfig }
                    default { "" }
                }
                if ($content) {
                    Set-Content -Path $file.Value -Value $content -Force
                    Write-Host "  Created file: $($file.Key)" -ForegroundColor Green
                }
            }
        }

        # Create environment files
        Set-EnvironmentConfig -Environment "Development" -Force
        Set-EnvironmentConfig -Environment "Production" -Force

        Write-Host "`nConfiguration initialization completed." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "`nFailed to initialize configurations: $($_.Exception.Message)" -ForegroundColor Red
        Write-Debug $_.ScriptStackTrace
        return $false
    }
}

function _Test-Configuration {
    [CmdletBinding()]
    param()
    
    try {
        # Initialize result
        $configurationValid = $true
        
        Write-Host "Checking configuration files..." -ForegroundColor Cyan

        # First check if base config directory exists
        Write-Host "`nChecking required directories:" -ForegroundColor Cyan
        
        if (-not (Test-Path $script:CONFIG_PATH)) {
            Write-Host "  ✗ Missing base configuration directory" -ForegroundColor Red
            Initialize-DefaultConfigurations
            return $false
        }

        # Check each required directory
        $script:REQUIRED_PATHS | ForEach-Object {
            $dir = $_
            $dirName = Split-Path $dir -Leaf
            if (Test-Path $dir) {
                Write-Host "  ✓ Found directory: $dirName" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Missing directory: $dirName" -ForegroundColor Red
                $configurationValid = $false
            }
        }

        # Check each required file
        Write-Host "`nChecking configuration files:" -ForegroundColor Cyan
        $script:REQUIRED_FILES.GetEnumerator() | ForEach-Object {
            if (Test-Path $_.Value) {
                Write-Host "  ✓ Found file: $($_.Key)" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Missing file: $($_.Key)" -ForegroundColor Red
                $configurationValid = $false
            }
        }

        if (-not $configurationValid) {
            Write-Host "`nMissing configurations detected. Initializing..." -ForegroundColor Yellow
            Initialize-DefaultConfigurations
            return $false
        }

        Write-Host "`nAll configurations verified successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Configuration check failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Verbose "Stack Trace: $($_.ScriptStackTrace)"
        return $false
    }
}

function Initialize-DefaultConfigurations {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nInitializing configurations..." -ForegroundColor Cyan

        # Create directories first
        foreach ($dir in $script:REQUIRED_PATHS) {
            if (-not (Test-Path $dir)) {
                $dirName = Split-Path $dir -Leaf
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Host "  Created directory: $dirName" -ForegroundColor Green
            }
        }

        # Create configuration files if they don't exist
        foreach ($file in $script:REQUIRED_FILES.GetEnumerator()) {
            if (-not (Test-Path $file.Value)) {
                $content = switch ($file.Key) {
                    "prometheus.yml" { Get-PrometheusConfig }
                    "loki-config.yaml" { Get-LokiConfig }
                    "tempo.yaml" { Get-TempoConfig }
                    "docker-compose.yml" { Get-DockerComposeConfig }
                    default { "" }
                }

                if ($content) {
                    Set-Content -Path $file.Value -Value $content -Force
                    Write-Host "  Created file: $($file.Key)" -ForegroundColor Green
                }
            }
        }

        # Set up environment files
        Write-Host "`nSetting up environment configurations..." -ForegroundColor Cyan
        Set-EnvironmentConfig -Environment "Development" -Force
        Set-EnvironmentConfig -Environment "Production" -Force

        Write-Host "`nConfiguration initialization completed." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Failed to initialize configurations: $($_.Exception.Message)" -ForegroundColor Red
        Write-Verbose "Stack Trace: $($_.ScriptStackTrace)"
        return $false
    }
}

function Set-EnvironmentConfig {
    [CmdletBinding()]
    param(
        [string]$Environment,
        [switch]$Force
    )
    
    $envFile = Join-Path $script:CONFIG_PATH ".env.$Environment"
    
    try {
        # Basic environment variables
        $envVars = @{
            NAMESPACE = $script:NAMESPACE
            ENVIRONMENT = $Environment
            ASPNETCORE_ENVIRONMENT = $Environment
            GRAFANA_USER = "admin"
            GRAFANA_PASSWORD = "InsightOps2024!"
            DB_USER = "insightops_user"
            DB_PASSWORD = "insightops_pwd"
            DB_NAME = "insightops_db"
        }

        # Add port mappings from service configuration
        foreach ($service in $script:SERVICES.GetEnumerator()) {
            if ($service.Value.Port) {
                $port = $service.Value.Port.Split(':')[0]
                $envVars["$($service.Key.ToUpper())_PORT"] = $port
            }
        }

        # Create environment file content
        $envContent = $envVars.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$($_.Value)"
        }

        # Write to file
        Set-Content -Path $envFile -Value $envContent -Force
        Write-Host "Updated environment configuration: $envFile" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Host "Failed to set environment configuration: $_" -ForegroundColor Red
        return $false
    }
}

function Get-PrometheusConfig {
    return @'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'order_service'
    static_configs:
      - targets: ['${NAMESPACE:-insightops}_orders:80']
    metrics_path: '/metrics'
    scrape_interval: 5s
    honor_labels: true

  - job_name: 'inventory_service'
    static_configs:
      - targets: ['${NAMESPACE:-insightops}_inventory:80']
    metrics_path: '/metrics'
    scrape_interval: 5s
    honor_labels: true

  - job_name: 'frontend'
    static_configs:
      - targets: ['${NAMESPACE:-insightops}_frontend:80']
    metrics_path: '/metrics'
    scrape_interval: 5s
    honor_labels: true

  - job_name: 'api_gateway'
    static_configs:
      - targets: ['${NAMESPACE:-insightops}_gateway:80']
    metrics_path: '/metrics'
    scrape_interval: 5s
    honor_labels: true

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
'@
}

function Get-LokiConfig {
    return @'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-05-15
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb:
    directory: /tmp/loki/index

  filesystem:
    directory: /tmp/loki/chunks
'@
}

function Get-TempoConfig {
    return @'
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: "0.0.0.0:4317"
        http:
          endpoint: "0.0.0.0:4318"

storage:
  trace:
    backend: local
    wal:
      path: /tmp/tempo/wal    # Required WAL path
    local:
      path: /tmp/tempo/blocks # Required blocks path

compactor:
  compaction:
    block_retention: 48h

ingester:
  max_block_duration: "5m"
  trace_idle_period: "10s"

metrics_generator:
  storage:
    path: /tmp/tempo/generator/wal

usage_report:
  reporting_enabled: false
'@
}

function Get-DockerComposeConfig {
    return @'
version: '3.8'

x-logging: &default-logging
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"

x-healthcheck: &default-healthcheck
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s

services:
  postgres:
    image: postgres:13
    container_name: ${NAMESPACE:-insightops}_db
    environment:
      POSTGRES_USER: ${DB_USER:-insightops_user}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-insightops_pwd}
      POSTGRES_DB: ${DB_NAME:-insightops_db}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "${DB_PORT:-5433}:5432"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-insightops_user} -d ${DB_NAME:-insightops_db}"]
    logging: *default-logging

  grafana:
    image: grafana/grafana:latest
    container_name: ${NAMESPACE:-insightops}_grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-InsightOps2024!}
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "${GRAFANA_PORT:-3001}:3000"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health"]
    logging: *default-logging

  prometheus:
    image: prom/prometheus:latest
    container_name: ${NAMESPACE:-insightops}_prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9091}:9090"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
    logging: *default-logging

  loki:
    container_name: ${NAMESPACE:-insightops}_loki
    volumes:
      - ./loki-config.yaml:/etc/loki/local-config.yaml
      - loki_data:/loki
    ports:
      - "${LOKI_PORT:-3101}:3100"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready"]
    logging: *default-logging

  tempo:
    image: grafana/tempo:latest
    container_name: ${NAMESPACE:-insightops}_tempo
    command: ["-config.file=/etc/tempo/tempo.yaml"]
    environment:
      - JAEGER_AGENT_HOST=tempo
      - JAEGER_ENDPOINT=http://tempo:14268/api/traces
      - TEMPO_PROMETHEUS_ENDPOINT=http://prometheus:9090
    volumes:
      - ./tempo/tempo.yaml:/etc/tempo/tempo.yaml:ro
      - tempo_data:/tmp/tempo
    ports:
      - "${TEMPO_PORT:-4317}:4317"  # OTLP gRPC
      - "${TEMPO_HTTP_PORT:-4318}:4318"  # OTLP HTTP
      - "3200:3200"  # Query endpoint
      - "9096:9096"  # gRPC
      - "14250:14250"  # Jaeger gRPC
      - "14268:14268"  # Jaeger HTTP
    depends_on:
      - prometheus
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3200/ready"]
      start_period: 45s
    logging: *default-logging
    restart: unless-stopped

  frontend:
    build: 
      context: ${BUILD_CONTEXT:-..}/FrontendService
      dockerfile: ${DOCKERFILE:-Dockerfile}
    container_name: ${NAMESPACE:-insightops}_frontend
    environment:
      - ASPNETCORE_ENVIRONMENT=${ENVIRONMENT:-Production}
      - ApiGateway__Url=http://${NAMESPACE:-insightops}_gateway
      - OpenTelemetry__Enabled=true
      - OpenTelemetry__ServiceName=frontend-service
      - OpenTelemetry__OtlpEndpoint=http://${NAMESPACE:-insightops}_tempo:4317
    ports:
      - "${FRONTEND_PORT:-5010}:80"
    depends_on:
      api_gateway:
        condition: service_healthy
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
    logging: *default-logging

  api_gateway:
    build: 
      context: ${BUILD_CONTEXT:-..}/ApiGateway
      dockerfile: ${DOCKERFILE:-Dockerfile}
    container_name: ${NAMESPACE:-insightops}_gateway
    environment:
      - ASPNETCORE_ENVIRONMENT=${ENVIRONMENT:-Production}
      - Services__OrderService=http://${NAMESPACE:-insightops}_orders
      - Services__InventoryService=http://${NAMESPACE:-insightops}_inventory
      - OpenTelemetry__Enabled=true
      - OpenTelemetry__ServiceName=api-gateway
      - OpenTelemetry__OtlpEndpoint=http://${NAMESPACE:-insightops}_tempo:4317
    ports:
      - "${GATEWAY_PORT:-5011}:80"
    depends_on:
      order_service:
        condition: service_healthy
      inventory_service:
        condition: service_healthy
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
    logging: *default-logging

  order_service:
    build: 
      context: ${BUILD_CONTEXT:-..}/OrderService
      dockerfile: ${DOCKERFILE:-Dockerfile}
    container_name: ${NAMESPACE:-insightops}_orders
    environment:
      - ASPNETCORE_ENVIRONMENT=${ENVIRONMENT:-Production}
      - ConnectionStrings__Postgres=Host=${NAMESPACE:-insightops}_db;Database=${DB_NAME:-insightops_db};Username=${DB_USER:-insightops_user};Password=${DB_PASSWORD:-insightops_pwd}
      - OpenTelemetry__Enabled=true
      - OpenTelemetry__ServiceName=order-service
      - OpenTelemetry__OtlpEndpoint=http://${NAMESPACE:-insightops}_tempo:4317
    ports:
      - "${ORDER_PORT:-5012}:80"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
    logging: *default-logging

  inventory_service:
    build: 
      context: ${BUILD_CONTEXT:-..}/InventoryService
      dockerfile: ${DOCKERFILE:-Dockerfile}
    container_name: ${NAMESPACE:-insightops}_inventory
    environment:
      - ASPNETCORE_ENVIRONMENT=${ENVIRONMENT:-Production}
      - ConnectionStrings__Postgres=Host=${NAMESPACE:-insightops}_db;Database=${DB_NAME:-insightops_db};Username=${DB_USER:-insightops_user};Password=${DB_PASSWORD:-insightops_pwd}
      - OpenTelemetry__Enabled=true
      - OpenTelemetry__ServiceName=inventory-service
      - OpenTelemetry__OtlpEndpoint=http://${NAMESPACE:-insightops}_tempo:4317
    ports:
      - "${INVENTORY_PORT:-5013}:80"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
    logging: *default-logging

volumes:
  postgres_data:
    name: ${NAMESPACE:-insightops}_postgres_data
  grafana_data:
    name: ${NAMESPACE:-insightops}_grafana_data
  prometheus_data:
    name: ${NAMESPACE:-insightops}_prometheus_data
  loki_data:
    name: ${NAMESPACE:-insightops}_loki_data
  tempo_data:
    name: ${NAMESPACE:-insightops}_tempo_data

networks:
  default:
    name: ${NAMESPACE:-insightops}_network
    driver: bridge
'@
}

Export-ModuleMember -Function @(
    # Configuration management
    'Test-Configuration',
    'Initialize-DefaultConfigurations',
    'Initialize-CorePaths',
    
    # Environment configuration
    'Set-EnvironmentConfig',
    
    # Configuration generators
    'Get-PrometheusConfig',
    'Get-LokiConfig',
    'Get-TempoConfig',
    'Get-DockerComposeConfig'
) -Variable @(
    # Paths
    'PROJECT_ROOT',
    'CONFIG_PATH',
    
    # Environment settings
    'NAMESPACE',
    'DEFAULT_ENVIRONMENT',
    
    # Configuration structures
    'REQUIRED_PATHS',
    'REQUIRED_FILES',
    
    # Service configurations
    'SERVICES'
)