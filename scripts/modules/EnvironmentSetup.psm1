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
  type: file
  disableDeletion: false
  editable: true
  options:
    path: /etc/grafana/dashboards
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

# Docker Compose Template Function
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
    volumes:
      - ./loki/loki-config.yaml:/etc/loki/local-config.yaml
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

networks:
  default:
    name: ${NAMESPACE:-insightops}_network
    driver: bridge
'@
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

        # Ensure host volume path for Tempo data is created with permissions
        Ensure-HostVolumePath -Path $hostVolumePath

        Write-Info "`nCreating required directories:"
        foreach ($path in $script:REQUIRED_PATHS) {
            if (-not (Test-Path $path) -or $Force) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Success "  [Created] $($path.Split('\')[-1])"
            }
            if ($path -like "*tempo_data*" -or $path -like "*prometheus_data*" -or $path -like "*loki_data*") {
                Set-VolumePermissions -VolumePath $path
            }
        }

        Write-Info "`nSetting up configuration files:"
        $configs = @{
            "tempo/tempo.yaml" = Get-TempoConfig
            "loki/loki-config.yaml" = Get-LokiConfig
            "prometheus/prometheus.yml" = Get-PrometheusConfig
            "docker-compose.yml" = Get-DockerComposeConfig
        }

        foreach ($config in $configs.GetEnumerator()) {
            $filePath = Join-Path $script:CONFIG_PATH $config.Key
            if (-not (Test-Path $filePath) -or $Force) {
                $directory = Split-Path $filePath -Parent
                Initialize-Directory -Path $directory
                
                # Write with UTF8 encoding without BOM
                $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($filePath, $config.Value, $utf8NoBomEncoding)
                
                Write-Success "  [Created] $($config.Key)"
            } else {
                Write-Info "  [Exists] $($config.Key)"
            }
        }

        if (Set-EnvironmentConfig -Environment $Environment -Force:$Force) {
            Write-Success "  [OK] Created .env.$Environment"
        }

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
            if (Test-Path $dir) {
                Write-Host "✓ Directory exists: $dir" -ForegroundColor Green
            } else {
                Write-Host "✗ Missing directory: $dir" -ForegroundColor Red
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