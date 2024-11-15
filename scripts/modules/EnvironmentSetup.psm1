# EnvironmentSetup.psm1
# Purpose: Handles environment setup and configuration for InsightOps

# Import required variables from Core module
if (-not (Get-Module Core)) {
    throw "Core module not loaded. Please ensure Core.psm1 is imported first."
}

# Import paths and settings from Core module
$script:CONFIG_PATH = (Get-Variable -Name CONFIG_PATH -Scope Global).Value
$script:REQUIRED_PATHS = (Get-Variable -Name REQUIRED_PATHS -Scope Global).Value
$script:REQUIRED_FILES = (Get-Variable -Name REQUIRED_FILES -Scope Global).Value
$script:NAMESPACE = (Get-Variable -Name NAMESPACE -Scope Global).Value

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

# Replace the entire Get-DockerComposeConfig function with this:
function Get-DockerComposeConfig {
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
      context: ./OrderService
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_orderservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker  # Set environment to Docker
      - ASPNETCORE_URLS=http://+:80;https://+:8081
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
    ports:
      - "${ORDERSERVICE_PORT:-7265}:80"
      - "7266:8081"  # HTTPS on 8080
    volumes:
      - ./certs:/app/certs:ro
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s
    networks:
      - default

  inventoryservice:
    build:
      context: ./InventoryService 
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_inventoryservice
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker  # Set environment to Docker
      - ASPNETCORE_URLS=http://+:80;https://+:8081
      - ConnectionStrings__Postgres=Host=postgres;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd
    ports:
      - "${INVENTORYSERVICE_PORT:-7070}:80"
      - "7071:8080"  # HTTPS on 8080
    volumes:
      - ./certs:/app/certs:ro
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s
    networks:
      - default

  apigateway:
    build:
      context: ./ApiGateway
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_apigateway
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker  # Set environment to Docker
      - ASPNETCORE_URLS=http://+:80;https://+:8081
    ports:
      - "${APIGATEWAY_PORT:-7237}:80" 
      - "7238:8080"  # HTTPS on 8080
    volumes:
      - ./certs:/app/certs:ro
    depends_on:
      - orderservice
      - inventoryservice
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s
    networks:
      - default

  frontend:
    build:
      context: ./Frontend
      dockerfile: Dockerfile
    container_name: ${NAMESPACE:-insightops}_frontend
    environment:
      - ASPNETCORE_ENVIRONMENT=Docker  # Set environment to Docker
      - ASPNETCORE_URLS=http://+:80;https://+:8081
    ports:
      - "${FRONTEND_PORT:-7144}:80"
      - "7145:8080"  # HTTPS on 8080
    volumes:
      - ./certs:/app/certs:ro
    depends_on:
      - apigateway
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:80/health || exit 1"]
      interval: 30s
      timeout: 30s
      retries: 3
      start_period: 40s
    networks:
      - default

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
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/etc/grafana/dashboards:ro
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
    external: true
  grafana_data:
    name: ${NAMESPACE:-insightops}_grafana_data
    external: true
  prometheus_data:
    name: ${NAMESPACE:-insightops}_prometheus_data
    external: true
  loki_data:
    name: ${NAMESPACE:-insightops}_loki_data
    external: true
  tempo_data:
    name: ${NAMESPACE:-insightops}_tempo_data
    external: true
  loki_wal:
    name: ${NAMESPACE:-insightops}_loki_wal
    external: true

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
            NAMESPACE = $script:NAMESPACE
            ENVIRONMENT = $Environment
            ASPNETCORE_ENVIRONMENT = $Environment
            DB_PORT = if ($Environment -eq "Development") { "5433" } else { "5432" }
            FRONTEND_PORT = if ($Environment -eq "Development") { "5010" } else { "80" }
            GATEWAY_PORT = if ($Environment -eq "Development") { "5011" } else { "8080" }
            ORDER_PORT = if ($Environment -eq "Development") { "5012" } else { "8081" }
            INVENTORY_PORT = if ($Environment -eq "Development") { "5013" } else { "8082" }
            GRAFANA_PORT = if ($Environment -eq "Development") { "3001" } else { "3000" }
            PROMETHEUS_PORT = if ($Environment -eq "Development") { "9091" } else { "9090" }
            LOKI_PORT = if ($Environment -eq "Development") { "3101" } else { "3100" }
            TEMPO_PORT = "4317"
            TEMPO_HTTP_PORT = "4318"
            TEMPO_QUERY_PORT = "3200"
            GRAFANA_USER = "admin"
            GRAFANA_PASSWORD = "InsightOps2024!"
            DB_USER = "insightops_user"
            DB_PASSWORD = "insightops_pwd"
            DB_NAME = "insightops_db"
            METRICS_RETENTION = "30d"
            LOGS_RETENTION = "7d"
            TRACES_RETENTION = "48h"
            OTEL_EXPORTER_OTLP_ENDPOINT = "http://tempo:4317"
            OTEL_SERVICE_NAME = "insightops"
            PROMETHEUS_URL = "http://prometheus:9090"
            LOKI_URL = "http://loki:3100"
            TEMPO_URL = "http://tempo:4317"
            GRAFANA_URL = "http://grafana:3000"
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

function Initialize-Environment {
    param(
        [string]$Environment = "Development",
        [switch]$Force
    )
    try {
        Write-Info "`nInitializing environment: $Environment"
        Write-Info "Using configuration path: $script:CONFIG_PATH"

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
        Write-Info "Ensuring host volume path for Tempo data..."
        Ensure-HostVolumePath -Path $hostVolumePath

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
        # Define configuration files with paths and ensure they're joined correctly
        $configs = @(
            @{Key = "tempo/tempo.yaml"; Value = Get-TempoConfig}
            @{Key = "loki/loki-config.yaml"; Value = Get-LokiConfig}
            @{Key = "prometheus/prometheus.yml"; Value = Get-PrometheusConfig}
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