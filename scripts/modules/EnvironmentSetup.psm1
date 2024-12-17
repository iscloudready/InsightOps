# EnvironmentSetup.psm1
# Purpose: Handles environment setup and configuration for InsightOps

# Import required variables from Core module
if (-not (Get-Module Core)) {
    throw "Core module not loaded. Please ensure Core.psm1 is imported first."
}

# Add to existing EnvironmentSetup.psm1
#Import-Module (Join-Path $PSScriptRoot "Monitoring.psm1")

# Import paths and settings from Core module
$script:CONFIG_PATH = (Get-Variable -Name CONFIG_PATH -Scope Global).Value
$script:REQUIRED_PATHS = (Get-Variable -Name REQUIRED_PATHS -Scope Global).Value
$script:REQUIRED_FILES = (Get-Variable -Name REQUIRED_FILES -Scope Global).Value
$script:NAMESPACE = (Get-Variable -Name NAMESPACE -Scope Global).Value
$script:PROJECT_ROOT = $env:PROJECT_ROOT

# Define a path on your host with full permissions for Docker to use
# Define a path dynamically for Docker volumes using CONFIG_PATH
$hostVolumePath = Join-Path $script:CONFIG_PATH "tempo_data"

# Verify required variables
if (-not $script:CONFIG_PATH) {
    throw "CONFIG_PATH not available from Core module"
}

# Logging functions for consistency
function Write-Info { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host $Message -ForegroundColor Red }

# Ensure the directory exists and has the required permissions
function Ensure-HostVolumePath {
    param (
        [string]$Path
    )

    if (-Not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "Created host volume directory at $Path" -ForegroundColor Green
    } else {
        Write-Host "Host volume directory already exists at $Path" -ForegroundColor Cyan
    }

    # Set permissions to ensure Docker can write to this directory
    $acl = Get-Acl -Path $Path
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $Path -AclObject $acl
    Write-Host "Set full control permissions on $Path for Docker access" -ForegroundColor Green
}

# Directory Initialization with Permissions
function Initialize-Directory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$SetPermissions
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Success "Created directory: $Path"
            if ($SetPermissions) { Set-VolumePermissions -VolumePath $Path }
        }
        return $true
    }
    catch {
        Write-Error "Failed to initialize directory $Path : $_"
        return $false
    }
}

# Set volume permissions for Docker on Windows
function Set-VolumePermissions {
    param([string]$VolumePath)
    if (-not (Test-Path -Path $VolumePath)) {
        New-Item -ItemType Directory -Path $VolumePath | Out-Null
    }
    $directory = Get-Item -Path $VolumePath
    $acl = Get-Acl -Path $directory.FullName
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $directory.FullName -AclObject $acl
    Write-Info "Set full control permissions on $VolumePath for Docker access"
}

# Template Definitions
$script:CONFIG_TEMPLATES = @{
    Prometheus = @'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'dotnet'
    static_configs:
      - targets: ['gateway:80', 'orders:80', 'inventory:80', 'frontend:80']
'@

    Loki = @'
auth_enabled: false
server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
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

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
'@

    Tempo = @'
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

ingester:
  max_block_duration: "5m"
  trace_idle_period: "10s"

compactor:
  compaction:
    block_retention: 48h

storage:
  trace:
    backend: local
    local:
      path: /tmp/tempo/blocks
    wal:
      path: /tmp/tempo/wal

metrics_generator:
  storage:
    path: /tmp/tempo/generator/wal

usage_report:
  reporting_enabled: false
'@

    GrafanaDashboard = @'
apiVersion: 1
providers:
  - name: 'InsightOps'
    orgId: 1
    folder: 'InsightOps'
    folderUid: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
      foldersFromFilesStructure: true
'@

    GrafanaDatasource = @'
apiVersion: 1
datasources:
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://prometheus:9090
  isDefault: true

- name: Loki
  type: loki
  access: proxy
  url: http://loki:3100
  jsonData:
    maxLines: 1000

- name: Tempo
  type: tempo
  access: proxy
  url: http://tempo:3200
  jsonData:
    httpMethod: GET
    serviceMap:
      datasourceUid: prometheus
'@
}

function Get-InfrastructureDockerComposeConfig {
    return @'
version: '3'

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
  # Infrastructure Components
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
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-insightops_user} -d ${DB_NAME:-insightops_db}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging: *default-logging

  grafana:
    image: grafana/grafana:latest
    container_name: ${NAMESPACE:-insightops}_grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-InsightOps2024!}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/dashboards/overview.json
    volumes:
      - grafana_data:/var/lib/grafana
      - ${CONFIG_PATH}/grafana/provisioning:/etc/grafana/provisioning:ro
      - ${CONFIG_PATH}/grafana/dashboards:/etc/grafana/dashboards:ro
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
      - ${CONFIG_PATH}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9091}:9090"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
    logging: *default-logging

  loki:
    image: grafana/loki:2.9.3
    container_name: ${NAMESPACE:-insightops}_loki
    user: "root"
    volumes:
      - ${CONFIG_PATH}/loki/loki-config.yaml:/etc/loki/local-config.yaml
      - loki_data:/loki
      - ${CONFIG_PATH}/loki_wal:/loki/wal
    ports:
      - "${LOKI_PORT:-3101}:3100"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
    logging: *default-logging

  tempo:
    image: grafana/tempo:latest
    container_name: ${NAMESPACE:-insightops}_tempo
    user: root
    command: ["-config.file=/etc/tempo/tempo.yaml"]
    environment:
      - TEMPO_LOG_LEVEL=debug
    volumes:
      - ${CONFIG_PATH}/tempo/tempo.yaml:/etc/tempo/tempo.yaml:ro
      - tempo_data:/var/tempo
    ports:
      - "${TEMPO_PORT:-4317}:4317"
      - "${TEMPO_HTTP_PORT:-4318}:4318"
      - "3200:3200"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3200/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
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
  loki_wal:
    name: ${NAMESPACE:-insightops}_loki_wal

networks:
  default:
    name: ${NAMESPACE:-insightops}_infra_network
    driver: bridge
'@
}

function Get-ApplicationDockerComposeConfig {
    return @'
version: '3'

x-logging: &default-logging
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"

services:
  orderservice:
    build:
      context: ${PROJECT_ROOT}/OrderService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_orderservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
      - Observability__Tempo__Endpoint=http://tempo:4317
      - Observability__Loki__Endpoint=http://loki:3100
      - Observability__Prometheus__Endpoint=http://prometheus:9090
    networks:
      - default
      - infrastructure
    volumes:
      - ${PROJECT_ROOT:-..}/OrderService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${ORDERSERVICE_PORT:-7265}:80"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  inventoryservice:
    build:
      context: ${PROJECT_ROOT}/InventoryService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_inventoryservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
      - Observability__Tempo__Endpoint=http://tempo:4317
      - Observability__Loki__Endpoint=http://loki:3100
      - Observability__Prometheus__Endpoint=http://prometheus:9090
    networks:
      - default
      - infrastructure
    volumes:
      - ${PROJECT_ROOT:-..}/InventoryService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${INVENTORYSERVICE_PORT:-7070}:80"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  apigateway:
    build:
      context: ${PROJECT_ROOT}/ApiGateway
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_apigateway
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - Observability__Tempo__Endpoint=http://tempo:4317
      - Observability__Loki__Endpoint=http://loki:3100
      - Observability__Prometheus__Endpoint=http://prometheus:9090
    networks:
      - default
      - infrastructure
    volumes:
      - ${PROJECT_ROOT:-..}/ApiGateway/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${APIGATEWAY_PORT:-7237}:80"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  frontend:
    build:
      context: ${PROJECT_ROOT}/FrontendService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_frontend
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - DataProtection__Keys=/app/Keys
      - Observability__Tempo__Endpoint=http://tempo:4317
      - Observability__Loki__Endpoint=http://loki:3100
      - Observability__Prometheus__Endpoint=http://prometheus:9090
    user: "1001:1001"
    networks:
      - default
      - infrastructure
    volumes:
      - ${PROJECT_ROOT:-..}/FrontendService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
      - keys_data:/app/Keys
    ports:
      - "${FRONTEND_PORT:-5010}:80"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

volumes:
  keys_data:
    name: ${NAMESPACE:-insightops}_keys_data
    driver: local
    driver_opts:
      type: none
      device: ${CONFIG_PATH}/Keys
      o: bind

networks:
  default:
    name: ${NAMESPACE:-insightops}_app_network
    driver: bridge
  infrastructure:
    external:
      name: ${NAMESPACE:-insightops}_infra_network
'@
}

# Add this function to sanitize paths
function Get-SafePath {
    param (
        [string]$Path
    )
    
    # Normalize path separators
    $normalizedPath = $Path -replace '\\', '/'
    
    # Quote path if it contains spaces
    if ($normalizedPath -match '\s') {
        $normalizedPath = "`"$normalizedPath`""
    }
    
    return $normalizedPath
}

function Get-DockerComposeConfig {
    return @'
version: '3'

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
  # Infrastructure Components
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
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-insightops_user} -d ${DB_NAME:-insightops_db}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging: *default-logging

  grafana:
    image: grafana/grafana:latest
    container_name: ${NAMESPACE:-insightops}_grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-InsightOps2024!}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/dashboards/overview.json
    volumes:
      - grafana_data:/var/lib/grafana
      - ${CONFIG_PATH}/grafana/provisioning:/etc/grafana/provisioning:ro
      - ${CONFIG_PATH}/grafana/dashboards:/etc/grafana/dashboards:ro
    ports:
      - "${GRAFANA_PORT:-3001}:3000"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health"]
    logging: *default-logging
    depends_on:
      - postgres

  prometheus:
    image: prom/prometheus:latest
    container_name: ${NAMESPACE:-insightops}_prometheus
    volumes:
      - ${CONFIG_PATH}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9091}:9090"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
    logging: *default-logging
    depends_on:
      - postgres

  loki:
    image: grafana/loki:2.9.3
    container_name: ${NAMESPACE:-insightops}_loki
    user: "root"
    volumes:
      - ${CONFIG_PATH}/loki/loki-config.yaml:/etc/loki/local-config.yaml
      - loki_data:/loki
      - ${CONFIG_PATH}/loki_wal:/loki/wal
    ports:
      - "${LOKI_PORT:-3101}:3100"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
    logging: *default-logging
    depends_on:
      - postgres

  tempo:
    image: grafana/tempo:latest
    container_name: ${NAMESPACE:-insightops}_tempo
    user: root
    command: ["-config.file=/etc/tempo/tempo.yaml"]
    environment:
      - TEMPO_LOG_LEVEL=debug
    volumes:
      - ${CONFIG_PATH}/tempo/tempo.yaml:/etc/tempo/tempo.yaml:ro 
      - tempo_data:/var/tempo
    ports:
      - "${TEMPO_PORT:-4317}:4317"
      - "${TEMPO_HTTP_PORT:-4318}:4318"
      - "3200:3200"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3200/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging: *default-logging
    depends_on:
      - postgres

# Application Microservices
  orderservice:
    build:
      context: ${PROJECT_ROOT}
      dockerfile: OrderService/Dockerfile
    container_name: ${NAMESPACE:-insightops}_orderservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_HTTP_PORTS=80
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
      - Observability__Docker__Infrastructure__LokiUrl=http://loki:3100
      - Observability__Docker__Infrastructure__TempoEndpoint=http://tempo:4317
      - Observability__Docker__Infrastructure__PrometheusEndpoint=http://prometheus:9090
    volumes:
      - type: bind
        source: ${PROJECT_ROOT}/OrderService/appsettings.Docker.json
        target: /app/appsettings.Docker.json
        read_only: true
    ports:
      - "${ORDERSERVICE_PORT:-7265}:80"
    depends_on:
      postgres:
        condition: service_healthy
      loki:
        condition: service_healthy
      tempo:
        condition: service_healthy
      prometheus:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  inventoryservice:
    build:
      context: ${PROJECT_ROOT}
      dockerfile: InventoryService/Dockerfile
    container_name: ${NAMESPACE:-insightops}_inventoryservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
      - Observability__Docker__Infrastructure__LokiUrl=http://loki:3100
      - Observability__Docker__Infrastructure__TempoEndpoint=http://tempo:4317
      - Observability__Docker__Infrastructure__PrometheusEndpoint=http://prometheus:9090
    volumes:
      - type: bind
        source: ${PROJECT_ROOT}/InventoryService/appsettings.Docker.json
        target: /app/appsettings.Docker.json
        read_only: true
    ports:
      - "${INVENTORYSERVICE_PORT:-7070}:80"
    depends_on:
      postgres:
        condition: service_healthy
      loki:
        condition: service_healthy
      tempo:
        condition: service_healthy
      prometheus:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  apigateway:
    build:
      context: ${PROJECT_ROOT}
      dockerfile: ApiGateway/Dockerfile
    container_name: ${NAMESPACE:-insightops}_apigateway
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - Observability__Docker__Infrastructure__LokiUrl=http://loki:3100
      - Observability__Docker__Infrastructure__TempoEndpoint=http://tempo:4317
      - Observability__Docker__Infrastructure__PrometheusEndpoint=http://prometheus:9090
    volumes:
      - type: bind
        source: ${PROJECT_ROOT}/ApiGateway/appsettings.Docker.json
        target: /app/appsettings.Docker.json
        read_only: true
    ports:
      - "${APIGATEWAY_PORT:-7237}:80"
    depends_on:
      - orderservice
      - inventoryservice
      - loki
      - tempo
      - prometheus
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  frontend:
    build:
      context: ${PROJECT_ROOT}
      dockerfile: FrontendService/Dockerfile
    container_name: ${NAMESPACE:-insightops}_frontend
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - DataProtection__Keys=/app/Keys
      - Observability__Docker__Infrastructure__LokiUrl=http://loki:3100
      - Observability__Docker__Infrastructure__TempoEndpoint=http://tempo:4317
      - Observability__Docker__Infrastructure__PrometheusEndpoint=http://prometheus:9090
    user: "1001:1001"
    volumes:
      - type: bind
        source: ${PROJECT_ROOT}/FrontendService/appsettings.Docker.json
        target: /app/appsettings.Docker.json
        read_only: true
      - type: volume
        source: keys_data
        target: /app/Keys
        volume:
          nocopy: true
    ports:
      - "${FRONTEND_PORT:-5010}:80"
    depends_on:
      - apigateway
      - loki
      - tempo
      - prometheus
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

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
  loki_wal:
    name: ${NAMESPACE:-insightops}_loki_wal
  frontend_keys:
    name: ${NAMESPACE:-insightops}_frontend_keys
  keys_data:
    name: ${NAMESPACE:-insightops}_keys_data
    driver: local
    driver_opts:
      type: none
      device: ${CONFIG_PATH}/Keys
      o: bind

networks:
  default:
    name: ${NAMESPACE:-insightops}_network
    driver: bridge
'@
}

# The main Get-DockerComposeConfig function can now call both
function _Get-DockerComposeConfig {
    param(
        [ValidateSet("Infrastructure", "Application", "All")]
        [string]$Type = "All"
    )
    
    # Verify environment variables
    if (-not $env:PROJECT_ROOT) { throw "PROJECT_ROOT environment variable not set" }
    if (-not $env:CONFIG_PATH) { throw "CONFIG_PATH environment variable not set" }

    # Add configuration validation
    if (-not (Test-ComposeConfiguration)) {
        throw "Docker compose configuration validation failed"
    }

    switch ($Type) {
        "Infrastructure" { 
            Write-Host "Generating infrastructure compose with config path: $env:CONFIG_PATH" -ForegroundColor Yellow
            return Get-InfrastructureDockerComposeConfig 
        }
        "Application" { 
            Write-Host "Generating application compose with project root: $env:PROJECT_ROOT" -ForegroundColor Yellow
            return Get-ApplicationDockerComposeConfig 
        }
        "All" {
            Write-Host "Generating combined compose configuration..." -ForegroundColor Yellow
            
            # Get individual configs
            $infra = Get-InfrastructureDockerComposeConfig
            $app = Get-ApplicationDockerComposeConfig

            # Parse the YAML to combine properly
            $infraYaml = $infra | ConvertFrom-Yaml
            $appYaml = $app | ConvertFrom-Yaml

            # Combine services, volumes, and networks
            $combined = @{
                version = '3'
                services = @{}
                volumes = @{}
                networks = @{}
            }

            # Merge services
            $infraYaml.services.Keys | ForEach-Object {
                $combined.services[$_] = $infraYaml.services[$_]
            }
            $appYaml.services.Keys | ForEach-Object {
                $combined.services[$_] = $appYaml.services[$_]
            }

            # Merge volumes
            $infraYaml.volumes.Keys | ForEach-Object {
                $combined.volumes[$_] = $infraYaml.volumes[$_]
            }
            $appYaml.volumes.Keys | ForEach-Object {
                $combined.volumes[$_] = $appYaml.volumes[$_]
            }

            # Merge networks
            $infraYaml.networks.Keys | ForEach-Object {
                $combined.networks[$_] = $infraYaml.networks[$_]
            }
            $appYaml.networks.Keys | ForEach-Object {
                $combined.networks[$_] = $appYaml.networks[$_]
            }

            # Convert back to YAML
            return $combined | ConvertTo-Yaml
        }
    }
}

function Get-DockerComposeConfigs {
    param(
        [ValidateSet("Infrastructure", "Application", "All")]
        [string]$Type = "All"
    )
    
    # Verify environment variables
    if (-not $env:PROJECT_ROOT) { throw "PROJECT_ROOT environment variable not set" }
    if (-not $env:CONFIG_PATH) { throw "CONFIG_PATH environment variable not set" }

    # Add configuration validation
    if (-not (Test-ComposeConfiguration)) {
        throw "Docker compose configuration validation failed"
    }

    switch ($Type) {
        "Infrastructure" { 
            Write-Host "Generating infrastructure compose with config path: $env:CONFIG_PATH" -ForegroundColor Yellow
            return Get-InfrastructureDockerComposeConfig 
        }
        "Application" { 
            Write-Host "Generating application compose with project root: $env:PROJECT_ROOT" -ForegroundColor Yellow
            return Get-ApplicationDockerComposeConfig 
        }
        "All" {
            Write-Host "Generating combined compose configuration..." -ForegroundColor Yellow
            
            return @'
version: '3'

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
  # Infrastructure Services
'@ + "`n" + (Get-InfrastructureDockerComposeConfig) + "`n" + @'
  # Application Services
'@ + "`n" + (Get-ApplicationDockerComposeConfig)
        }
    }
}

function Test-ComposeConfiguration {
    [CmdletBinding()]
    param()
    
    $errors = @()
    
    # Check environment variables
    if (-not $env:PROJECT_ROOT) { $errors += "PROJECT_ROOT environment variable not set" }
    if (-not $env:CONFIG_PATH) { $errors += "CONFIG_PATH environment variable not set" }

    # Check infrastructure paths
    $infraPaths = @(
        (Join-Path $env:CONFIG_PATH "prometheus/prometheus.yml"),
        (Join-Path $env:CONFIG_PATH "loki/loki-config.yaml"),
        (Join-Path $env:CONFIG_PATH "tempo/tempo.yaml")
    )

    foreach ($path in $infraPaths) {
        if (-not (Test-Path $path)) {
            $errors += "Missing infrastructure config: $path"
        }
    }

    # Check application paths
    $servicePaths = @(
        (Join-Path $env:PROJECT_ROOT "FrontendService/Dockerfile"),
        (Join-Path $env:PROJECT_ROOT "ApiGateway/Dockerfile"),
        (Join-Path $env:PROJECT_ROOT "OrderService/Dockerfile"),
        (Join-Path $env:PROJECT_ROOT "InventoryService/Dockerfile")
    )

    foreach ($path in $servicePaths) {
        if (-not (Test-Path $path)) {
            $errors += "Missing service file: $path"
        }
    }

    if ($errors.Count -gt 0) {
        Write-Host "Configuration validation errors:" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
        return $false
    }

    Write-Host "Configuration validation passed" -ForegroundColor Green
    return $true
}

function GGGet-DockerComposeConfig {
    return @'
version: '3'

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
  # Infrastructure Components
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
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-insightops_user} -d ${DB_NAME:-insightops_db}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging: *default-logging

  grafana:
    image: grafana/grafana:latest
    container_name: ${NAMESPACE:-insightops}_grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-InsightOps2024!}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/dashboards/overview.json
    volumes:
      - grafana_data:/var/lib/grafana
      - ${CONFIG_PATH}/grafana/provisioning:/etc/grafana/provisioning:ro
      - ${CONFIG_PATH}/grafana/dashboards:/etc/grafana/dashboards:ro
    ports:
      - "${GRAFANA_PORT:-3001}:3000"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health"]
    logging: *default-logging
    depends_on:
      - postgres

  prometheus:
    image: prom/prometheus:latest
    container_name: ${NAMESPACE:-insightops}_prometheus
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9091}:9090"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
    logging: *default-logging
    depends_on:
      - postgres

  loki:
    image: grafana/loki:2.9.3
    container_name: ${NAMESPACE:-insightops}_loki
    user: "root"
    volumes:
      - ./loki/loki-config.yaml:/etc/loki/local-config.yaml
      - loki_data:/loki
      - ${CONFIG_PATH}/loki_wal:/loki/wal
    ports:
      - "${LOKI_PORT:-3101}:3100"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
    logging: *default-logging
    depends_on:
      - postgres

  tempo:
    image: grafana/tempo:latest
    container_name: ${NAMESPACE:-insightops}_tempo
    user: root
    command: ["-config.file=/etc/tempo/tempo.yaml"]
    environment:
      - TEMPO_LOG_LEVEL=debug
    volumes:
      - ./tempo/tempo.yaml:/etc/tempo/tempo.yaml:ro
      - tempo_data:/var/tempo
    ports:
      - "${TEMPO_PORT:-4317}:4317"
      - "${TEMPO_HTTP_PORT:-4318}:4318"
      - "3200:3200"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3200/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging: *default-logging
    depends_on:
      - postgres

  # Application Microservices
  orderservice:
    build:
      context: ../OrderService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_orderservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_HTTP_PORTS=80
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
    volumes:
      - ${PROJECT_ROOT:-..}/OrderService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${ORDERSERVICE_PORT:-7265}:80"
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  inventoryservice:
    build:
      context: ../InventoryService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_inventoryservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
    volumes:
      - ${PROJECT_ROOT:-..}/InventoryService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${INVENTORYSERVICE_PORT:-7070}:80"
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  apigateway:
    build:
      context: ../ApiGateway
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_apigateway
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
    volumes:
      - ${PROJECT_ROOT:-..}/ApiGateway/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${APIGATEWAY_PORT:-7237}:80"
    depends_on:
      - orderservice
      - inventoryservice
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  frontend:
    build:
      context: ../FrontendService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_frontend
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - DataProtection__Keys=/app/Keys
    user: "1001:1001"
    volumes:
      - ${PROJECT_ROOT:-..}/FrontendService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
      - keys_data:/app/Keys
    ports:
      - "${FRONTEND_PORT:-5010}:80"
    depends_on:
      - apigateway
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

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
  loki_wal:
    name: ${NAMESPACE:-insightops}_loki_wal
  frontend_keys:
    name: ${NAMESPACE:-insightops}_frontend_keys
  keys_data:
    name: ${NAMESPACE:-insightops}_keys_data
    driver: local
    driver_opts:
      type: none
      device: ${CONFIG_PATH}/Keys
      o: bind

networks:
  default:
    name: ${NAMESPACE:-insightops}_network
    driver: bridge
'@
}

function _Get-DockerComposeConfig {
    return @'
name: insightops

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
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-insightops_user} -d ${DB_NAME:-insightops_db}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    logging: *default-logging

  orderservice:
    build:
      context: ../OrderService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_orderservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_HTTP_PORTS=80
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
    volumes:
      - ${PROJECT_ROOT:-..}/OrderService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${ORDERSERVICE_PORT:-7265}:80"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  inventoryservice:
    build:
      context: ../InventoryService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_inventoryservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
    volumes:
      - ${PROJECT_ROOT:-..}/InventoryService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${INVENTORYSERVICE_PORT:-7070}:80"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  apigateway:
    build:
      context: ../ApiGateway
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_apigateway
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
    volumes:
      - ${PROJECT_ROOT:-..}/ApiGateway/appsettings.Docker.json:/app/appsettings.Docker.json:ro
    ports:
      - "${APIGATEWAY_PORT:-7237}:80"
    depends_on:
      orderservice:
        condition: service_healthy
      inventoryservice:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  frontend:
    build:
      context: ../FrontendService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_frontend
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker
      - ASPNETCORE_URLS=http://+:80
      - DataProtection__Keys=/app/Keys
    user: "1001:1001" 
    volumes:
      - ${PROJECT_ROOT:-..}/FrontendService/appsettings.Docker.json:/app/appsettings.Docker.json:ro
      - keys_data:/app/Keys
    ports:
      - "${FRONTEND_PORT:-5010}:80"
    depends_on:
      apigateway:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s

  grafana:
    image: grafana/grafana:latest
    container_name: ${NAMESPACE:-insightops}_grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-InsightOps2024!}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
      - GF_PATHS_PROVISIONING=/etc/grafana/provisioning
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/dashboards/overview.json
    volumes:
      - grafana_data:/var/lib/grafana
      - ${CONFIG_PATH}/grafana/provisioning:/etc/grafana/provisioning:ro
      - ${CONFIG_PATH}/grafana/dashboards:/etc/grafana/dashboards:ro
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
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "${PROMETHEUS_PORT:-9091}:9090"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
    logging: *default-logging

  loki:
    image: grafana/loki:2.9.3
    container_name: ${NAMESPACE:-insightops}_loki
    user: "root"
    volumes:
      - ./loki/loki-config.yaml:/etc/loki/local-config.yaml
      - loki_data:/loki
      - ${CONFIG_PATH}/loki_wal:/loki/wal
    ports:
      - "${LOKI_PORT:-3101}:3100"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3100/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
    logging: *default-logging

  tempo:
    image: grafana/tempo:latest
    container_name: ${NAMESPACE:-insightops}_tempo
    user: root
    command: ["-config.file=/etc/tempo/tempo.yaml"]
    environment:
      - TEMPO_LOG_LEVEL=debug
    volumes:
      - ./tempo/tempo.yaml:/etc/tempo/tempo.yaml:ro
      - tempo_data:/var/tempo
    ports:
      - "${TEMPO_PORT:-4317}:4317"
      - "${TEMPO_HTTP_PORT:-4318}:4318"
      - "3200:3200"
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3200/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

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
  loki_wal:
    name: ${NAMESPACE:-insightops}_loki_wal
  frontend_keys:
    name: ${NAMESPACE:-insightops}_frontend_keys
  keys_data:
    name: ${NAMESPACE:-insightops}_keys_data
    driver: local
    driver_opts:
      type: none
      device: ${CONFIG_PATH}/Keys
      o: bind

networks:
  default:
    name: ${NAMESPACE:-insightops}_network
    driver: bridge
'@
}

# Ensures full control permissions for Docker volumes
function Ensure-DockerPermissions {
    param ([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        $acl = Get-Acl -Path $path
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($accessRule)
        Set-Acl -Path $path -AclObject $acl
        Write-Host "Set full control permissions on $path for Docker access" -ForegroundColor Green
    }
}

function Write-ConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [string]$Description = "configuration file"
    )
    
    try {
        # Create directory if it doesn't exist
        $directory = Split-Path -Parent $Path
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Write-Verbose "Created directory: $directory"
        }

        # Write content with UTF8 encoding without BOM
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBomEncoding)
        
        Write-Verbose "Successfully wrote $Description to: $Path"
        return $true
    }
    catch {
        Write-Error "Failed to write $Description to $Path : $_"
        return $false
    }
}

function Get-PrometheusConfig {
    return $script:CONFIG_TEMPLATES.Prometheus
}

function Get-LokiConfig {
    return $script:CONFIG_TEMPLATES.Loki
}

function Get-TempoConfig {
    return $script:CONFIG_TEMPLATES.Tempo
}

function Set-EnvironmentConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [switch]$Force
    )
    try {
        $envFile = Join-Path $script:CONFIG_PATH ".env.$Environment"
        Write-Info "Setting environment configuration for: $Environment"
        $envVars = @{
            # Project Configuration
            NAMESPACE = $script:NAMESPACE
            ENVIRONMENT = $Environment
            PROJECT_ROOT = $script:PROJECT_ROOT
            CONFIG_PATH = $script:CONFIG_PATH
            ASPNETCORE_ENVIRONMENT = $Environment

            # Database Configuration
            DB_PORT = if ($Environment -eq "Development") { "5433" } else { "5432" }
            DB_USER = "insightops_user"
            DB_PASSWORD = "insightops_pwd"
            DB_NAME = "insightops_db"

            # Service Ports
            FRONTEND_PORT = if ($Environment -eq "Development") { "5010" } else { "80" }
            APIGATEWAY_PORT = if ($Environment -eq "Development") { "7237" } else { "80" }
            ORDERSERVICE_PORT = if ($Environment -eq "Development") { "7265" } else { "80" }
            INVENTORYSERVICE_PORT = if ($Environment -eq "Development") { "7070" } else { "80" }

            # Observability Stack Ports
            GRAFANA_PORT = if ($Environment -eq "Development") { "3001" } else { "3000" }
            PROMETHEUS_PORT = if ($Environment -eq "Development") { "9091" } else { "9090" }
            LOKI_PORT = if ($Environment -eq "Development") { "3101" } else { "3100" }
            TEMPO_PORT = "4317"
            TEMPO_HTTP_PORT = "4318"
            TEMPO_QUERY_PORT = "3200"

            # Observability Stack Credentials
            GRAFANA_USER = "admin"
            GRAFANA_PASSWORD = "InsightOps2024!"

            # Retention Settings
            METRICS_RETENTION = "30d"
            LOGS_RETENTION = "7d"
            TRACES_RETENTION = "48h"

            # OpenTelemetry Configuration
            OTEL_EXPORTER_OTLP_ENDPOINT = "http://tempo:4317"
            OTEL_SERVICE_NAME = "insightops"

            # Service URLs
            PROMETHEUS_URL = "http://prometheus:9090"
            LOKI_URL = "http://loki:3100"
            TEMPO_URL = "http://tempo:4317"
            GRAFANA_URL = "http://grafana:3000"

            # Observability Infrastructure
            OBSERVABILITY_LOKI_URL = "http://loki:3100"
            OBSERVABILITY_TEMPO_ENDPOINT = "http://tempo:4317"
            OBSERVABILITY_PROMETHEUS_ENDPOINT = "http://prometheus:9090"
            
            # Service Dependencies
            SERVICE_APIGATEWAY_URL = if ($Environment -eq "Development") { "http://localhost:7237" } else { "http://apigateway" }
            SERVICE_ORDERSERVICE_URL = if ($Environment -eq "Development") { "http://localhost:7265" } else { "http://orderservice" }
            SERVICE_INVENTORYSERVICE_URL = if ($Environment -eq "Development") { "http://localhost:7070" } else { "http://inventoryservice" }
            SERVICE_FRONTEND_URL = if ($Environment -eq "Development") { "http://localhost:5010" } else { "http://frontend" }
        }

        # Add Docker specific variables if not in Development
        if ($Environment -ne "Development") {
            $envVars["DOCKER_NETWORK"] = "${script:NAMESPACE}_network"
            $envVars["COMPOSE_PROJECT_NAME"] = $script:NAMESPACE
        }

        $envContent = $envVars.GetEnumerator() | Sort-Object Key | ForEach-Object {
            "$($_.Key)=$($_.Value)"
        }

        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($envFile, ($envContent -join "`n"), $utf8NoBomEncoding)
        Write-Success "Updated environment configuration: $envFile"
        return $true
    }
    catch {
        Write-Error "Failed to set environment configuration: $_"
        return $false
    }
}

$dashboardProvisionConfig = @'
apiVersion: 1
providers:
  - name: 'InsightOps'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
'@

$datasourceConfig = @'
apiVersion: 1
deleteDatasources:
  - name: Prometheus
    orgId: 1
  - name: Loki
    orgId: 1
  - name: Tempo
    orgId: 1

datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    version: 1
    editable: true
    jsonData:
      httpMethod: POST
      timeInterval: "5s"
      
  - name: Loki
    type: loki
    uid: loki
    access: proxy
    url: http://loki:3100
    version: 1
    editable: true
    jsonData:
      maxLines: 1000
      
  - name: Tempo
    type: tempo
    uid: tempo
    access: proxy
    url: http://tempo:3200
    version: 1
    editable: true
    jsonData:
      httpMethod: GET
      serviceMap:
        datasourceUid: prometheus
'@

$sampleDashboard = @'
{
  "annotations": {
    "list": []
  },
  "editable": true,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "red",
                "value": null
              },
              {
                "color": "green",
                "value": 1
              }
            ]
          }
        }
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 1,
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "prometheus"
          },
          "expr": "up",
          "refId": "A"
        }
      ],
      "title": "Service Status",
      "type": "stat"
    }
  ],
  "refresh": "5s",
  "schemaVersion": 38,
  "style": "dark",
  "tags": ["insightops"],
  "title": "InsightOps Overview",
  "uid": "insightops-status",
  "version": 1
}
'@

function Initialize-Environment {
    param(
        [string]$Environment = "Development",
        [switch]$Force
    )
    try {
        # Set up logging
        $outputFile = Join-Path $env:CONFIG_PATH "environment_init.log"
        Write-Host "Logging detailed output to: $outputFile" -ForegroundColor Cyan
        
        # Start logging
        Start-Transcript -Path $outputFile -Append

        Write-Info "`nInitializing environment: $Environment"
        Write-Info "Using configuration path: $script:CONFIG_PATH"

        Write-Host "BASE_PATH:    $env:BASE_PATH" -ForegroundColor Yellow
        Write-Host "PROJECT_ROOT: $env:PROJECT_ROOT" -ForegroundColor Yellow
        Write-Host "MODULE_PATH:  $env:MODULE_PATH" -ForegroundColor Yellow
        Write-Host "CONFIG_PATH:  $env:CONFIG_PATH" -ForegroundColor Yellow

        # Create all necessary monitoring directories
        Write-Info "Creating monitoring directories..." | Tee-Object -Append -FilePath $outputFile
        $monitoringDirs = @(
            "src/FrontendService/Monitoring",
            "Configurations/grafana/dashboards",
            "Configurations/prometheus/rules"
        )

        foreach ($dir in $monitoringDirs) {
            $fullPath = Join-Path $script:PROJECT_ROOT $dir
            if (-not (Test-Path $fullPath)) {
                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                Write-Success "  [Created] $dir" | Tee-Object -Append -FilePath $outputFile
            } else {
                Write-Info "  [Exists] $dir" | Tee-Object -Append -FilePath $outputFile
            }
        }

        Write-Info "Monitoring directories created successfully."
        Write-Info "Proceeding with environment initialization..."

        # Copy Monitoring module
        #$modulesPath = Join-Path $script:PROJECT_ROOT "InsightOps\scripts\modules"
        $monitoringModulePath = Join-Path $env:MODULE_PATH "Monitoring.psm1"
        Write-Info "Monitoring Module Path: $monitoringModulePath"
        if (-not (Test-Path $monitoringModulePath)) {
            Copy-Item (Join-Path $env:BASE_PATH "Monitoring.psm1") $monitoringModulePath -Force
            Write-Success "  [Created] Monitoring.psm1 module"
        }

        # Check if loki_wal directory exists and create it if missing
        Write-Info "Ensuring loki_wal directory exists and has correct permissions..."
        if (-not (Test-Path -Path "$script:CONFIG_PATH\loki_wal")) {
            New-Item -ItemType Directory -Path "$script:CONFIG_PATH\loki_wal" | Out-Null
            Write-Success "  [Created] loki_wal directory"
        }

        # Set Docker permissions for loki_wal
        Set-VolumePermissions -VolumePath "$script:CONFIG_PATH\loki_wal"
        Write-Info "Permissions set for loki_wal directory"

        # Ensure host volume path for Tempo data is created with permissions
        Write-Host "Ensuring host volume path for Tempo data..." -ForegroundColor Cyan
        $hostVolumePath = Join-Path -Path $script:CONFIG_PATH -ChildPath "tempo_data"
        Ensure-HostVolumePath -Path $hostVolumePath

        # Add monitoring initialization
        Write-Info "Initializing monitoring components..."
        Import-Module $monitoringModulePath -Force
        Initialize-Monitoring -ConfigPath $script:CONFIG_PATH

        # Manually create paths for Docker permissions
        Write-Info "Setting Docker permissions for data directories..."
        $dockerPaths = @(
            Join-Path -Path $script:CONFIG_PATH -ChildPath "postgres_data"
            Join-Path -Path $script:CONFIG_PATH -ChildPath "grafana_data"
            Join-Path -Path $script:CONFIG_PATH -ChildPath "prometheus_data"
            Join-Path -Path $script:CONFIG_PATH -ChildPath "loki_data"
            Join-Path -Path $script:CONFIG_PATH -ChildPath "tempo_data"
        )
        Ensure-DockerPermissions -Paths $dockerPaths

        Write-Info "`nCreating required directories:"
        foreach ($path in $script:REQUIRED_PATHS) {
            # Replace any incorrect path references
            $correctedPath = $path -replace "scripts\\Configurations", "Configurations"
            Write-Info "Processing path: $correctedPath"

            if (-not (Test-Path -Path $correctedPath) -or $Force) {
                New-Item -ItemType Directory -Path $correctedPath -Force | Out-Null
                Write-Success "  [Created] $($correctedPath.Split('\')[-1])"
            } else {
                Write-Info "  [Exists] $($correctedPath.Split('\')[-1])"
            }

            # Set permissions on specific data paths
            if ($correctedPath -like "*tempo_data*" -or $correctedPath -like "*prometheus_data*" -or $correctedPath -like "*loki_data*") {
                Set-VolumePermissions -VolumePath $correctedPath
            }
        }

        Write-Info "`nSetting up configuration files:"
        #$script:CONFIG_PATH = Join-Path $script:PROJECT_ROOT "InsightOps\Configurations"

        # Define configuration files with paths and ensure they're joined correctly
        $configs = @(
            @{Key = "tempo/tempo.yaml"; Value = Get-TempoConfig}
            @{Key = "loki/loki-config.yaml"; Value = Get-LokiConfig}
            @{Key = "prometheus/prometheus.yml"; Value = Get-PrometheusConfig}
            #@{Key = "docker-compose.infrastructure.yml"; Value = Get-DockerComposeConfig -Type Infrastructure}
            #@{Key = "docker-compose.application.yml"; Value = Get-DockerComposeConfig -Type Application}
            @{Key = "docker-compose.yml"; Value = Get-DockerComposeConfig}
        )

        foreach ($config in $configs) {
            # Use single Join-Path call for each file path
            $filePath = Join-Path -Path $script:CONFIG_PATH -ChildPath $config.Key
            Write-Info "Setting up config file: $filePath"

            if (-not (Test-Path -Path $filePath) -or $Force) {
                $directory = Split-Path -Path $filePath -Parent
                Initialize-Directory -Path $directory

                # Write with UTF8 encoding without BOM
                $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($filePath, $config.Value, $utf8NoBomEncoding)

                Write-Success "  [Created] $($config.Key)"
            } else {
                Write-Info "  [Exists] $($config.Key)"
            }
        }

        try {
            Write-Host "Updating prometheus config with windows exporter settings..." -ForegroundColor Yellow
            $exporterPort = 9182
            Write-Host "Exporter port: $exporterPort"

            # Set the system IP and exporter port
            $systemIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq 'Dhcp' -or $_.PrefixOrigin -eq 'Manual' }).IPAddress | Select-Object -First 1
            Write-Host "System IP address: $systemIp"

            $exporterUrl = "http://${systemIp}:${exporterPort}/metrics"
            Write-Host "Exporter URL: $exporterUrl"

            $prometheusUrlCheck = "http://${systemIp}:9090/metrics"
            Write-Host "Prometheus URL check: $prometheusUrlCheck"

            # Update the Prometheus configuration file
            Update-PrometheusConfigFile -systemIp $systemIp -exporterPort $exporterPort
            Write-Host "Prometheus configuration file updated successfully."
        } catch {
            Write-Host "An error occurred: $($Error[0].Message)"
            Write-Host "Error details: $($Error[0].Exception.ToString())"
        }

        Write-Info "Setting environment configuration..."
        if (Set-EnvironmentConfig -Environment $Environment -Force:$Force) {
            Write-Success "  [OK] Created .env.$Environment"
        }

        Write-Info "`nInitializing Grafana configurations..."

        # Create Grafana directory structure
        $grafanaPath = Join-Path $script:CONFIG_PATH "grafana"
        $grafanaDirs = @(
            "$grafanaPath\provisioning\dashboards"
            "$grafanaPath\provisioning\datasources"
            "$grafanaPath\dashboards"
        )

        # Create directories if they don't exist
        foreach ($dir in $grafanaDirs) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Success "  [Created] Grafana directory: $($dir.Split('\')[-1])"
            } else {
                Write-Info "  [Exists] Grafana directory: $($dir.Split('\')[-1])"
            }
        }

        # Clean and create directories
        $grafanaPath = Join-Path $script:CONFIG_PATH "grafana"

        # Clean existing Grafana configuration
        if (Test-Path $grafanaPath) {
            Get-ChildItem -Path $grafanaPath -Recurse -File | Remove-Item -Force
        }

        # Create directory structure
        $grafanaDirs = @(
            "$grafanaPath\provisioning\dashboards",
            "$grafanaPath\provisioning\datasources",
            "$grafanaPath\provisioning\plugins",
            "$grafanaPath\provisioning\alerting",
            "$grafanaPath\dashboards"
        )

        foreach ($dir in $grafanaDirs) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Success "  [Created] Grafana directory: $($dir.Split('\')[-1])"
            }
        }

        # Write configurations
        $configs = @{
            "$grafanaPath\provisioning\dashboards\dashboards.yaml" = $dashboardProvisionConfig
            "$grafanaPath\provisioning\datasources\datasources.yaml" = $datasourceConfig
            "$grafanaPath\dashboards\overview.json" = $sampleDashboard
        }

        foreach ($config in $configs.GetEnumerator()) {
            try {
                $directory = Split-Path -Parent $config.Key
                if (-not (Test-Path $directory)) {
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                }

                $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($config.Key, $config.Value, $utf8NoBomEncoding)
                Write-Success "  [Created] $($config.Key.Split('\')[-1])"
            }
            catch {
                Write-Warning "Failed to create $($config.Key): $_"
            }
        }

        Write-Success "`nGrafana initialization completed successfully"
        Write-Success "`nEnvironment initialization completed successfully"
        return $true
            }
            catch {
                Write-Error "`nEnvironment initialization failed: $($_.Exception.Message)"
                return $false
            }
        }


function Test-Configuration {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Checking configurations..." -ForegroundColor Cyan
        $configurationValid = $true
        foreach ($dir in $script:REQUIRED_PATHS) {
            $correctedDir = $dir -replace "scripts\\Configurations", "Configurations"
            if (Test-Path $correctedDir) {
                Write-Host "✓ Directory exists: $correctedDir" -ForegroundColor Green
            } else {
                Write-Host "✗ Missing directory: $correctedDir" -ForegroundColor Red
                $configurationValid = $false
            }
        }
        
        if ($configurationValid) {
            Write-Host "All configurations verified successfully" -ForegroundColor Green
        } else {
            Write-Host "Configuration check failed - some items are missing" -ForegroundColor Red
        }
        
        return $configurationValid
    }
    catch {
        Write-Host "Configuration check failed: $_" -ForegroundColor Red
        return $false
    }
}

# Add this function to EnvironmentSetup.psm1
function Initialize-GrafanaDashboards {
    param (
        [string]$ConfigPath
    )

    # Generate Overview Dashboard
    $overviewDashboard = Get-ServiceOverviewDashboard
    $dashboardPath = Join-Path $ConfigPath "grafana/dashboards/overview.json"
    Write-ConfigFile -Path $dashboardPath -Content $overviewDashboard
    
    # Generate Service-Specific Dashboards
    foreach ($service in @("Order", "Inventory", "Gateway")) {
        $dashboard = Get-ServiceDashboard -ServiceName $service
        $path = Join-Path $ConfigPath "grafana/dashboards/$($service.ToLower()).json"
        Write-ConfigFile -Path $path -Content $dashboard
    }
}

function Get-ServiceDashboard {
    param ([string]$ServiceName)
    
    return @"
{
  "title": "$ServiceName Dashboard",
  "panels": [
    {
      "title": "Request Rate",
      "type": "graph",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(http_requests_total{service=\"$($ServiceName.ToLower())\"}[5m])"
        }
      ]
    },
    {
      "title": "Error Rate",
      "type": "graph",
      "datasource": "Prometheus",
      "targets": [
        {
          "expr": "rate(http_requests_errors_total{service=\"$($ServiceName.ToLower())\"}[5m])"
        }
      ]
    }
  ]
}
"@
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-Environment',
    'Initialize-DefaultConfigurations',
    'Test-Configuration',
    'Set-EnvironmentConfig',
    'Write-TempoConfig',
    'Write-ConfigFile',
    'Get-DockerComposeConfig',
    'Get-PrometheusConfig',
    'Get-LokiConfig',
    'Get-TempoConfig'
)