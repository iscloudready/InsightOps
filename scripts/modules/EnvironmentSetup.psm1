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

# Verify required variables
if (-not $script:CONFIG_PATH) {
    throw "CONFIG_PATH not available from Core module"
}

function Write-Info { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host $Message -ForegroundColor Red }

# Default configuration templates
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

storage:
  trace:
    backend: local
    wal:
      path: /tmp/tempo/wal
    local:
      path: /tmp/tempo/blocks

ingester:
  max_block_duration: "5m"
  trace_idle_period: "10s"

compactor:
  compaction:
    block_retention: 48h

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

# Configuration writing functions
function Write-TempoConfig {
    [CmdletBinding()]
    param (
        [string]$Path
    )
    
    try {
        $tempoConfig = $script:CONFIG_TEMPLATES.Tempo.Trim()
        
        # Ensure proper line endings
        $tempoConfig = $tempoConfig -replace "`r`n", "`n" -replace "`r", "`n" -replace "`n", [Environment]::NewLine
        
        # Create directory if it doesn't exist
        $directory = Split-Path -Parent $Path
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Write the file with UTF8 encoding without BOM
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($Path, $tempoConfig, $utf8NoBomEncoding)
        
        Write-Verbose "Tempo configuration written to: $Path"
        return $true
    }
    catch {
        Write-Error "Failed to write Tempo configuration: $_"
        return $false
    }
}

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
    command: ["-config.file=/etc/tempo/tempo.yaml"]
    environment:
      - TEMPO_LOG_LEVEL=debug
    volumes:
      - ./tempo/tempo.yaml:/etc/tempo/tempo.yaml:ro
      - tempo_data:/tmp/tempo
    ports:
      - "4317:4317"
      - "4318:4318"
      - "3200:3200"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3200/ready"]
      start_period: 45s
    logging: *default-logging
    restart: unless-stopped

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

function Initialize-Environment {
    [CmdletBinding()]
    param(
        [string]$Environment = "Development",
        [switch]$Force
    )
    
    try {
        Write-Host "`nInitializing environment: $Environment" -ForegroundColor Cyan
        Write-Host "Using configuration path: $script:CONFIG_PATH" -ForegroundColor Yellow

        # Create required directories
        Write-Host "`nCreating required directories:" -ForegroundColor Yellow
        foreach ($path in $script:REQUIRED_PATHS) {
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Host "  [Created] $($path.Split('\')[-1])" -ForegroundColor Green
            } else {
                Write-Host "  [Exists] $($path.Split('\')[-1])" -ForegroundColor Cyan
            }
        }

        # Set up main configuration files
        Write-Host "`nSetting up configuration files:" -ForegroundColor Yellow
        
        # Write Tempo configuration using dedicated function
        $tempoPath = Join-Path $script:CONFIG_PATH "tempo/tempo.yaml"
        if (Write-TempoConfig -Path $tempoPath) {
            Write-Host "  [Created] tempo/tempo.yaml" -ForegroundColor Green
        }

        # Write other configurations
        $configs = @{
            "docker-compose.yml" = Get-DockerComposeConfig
            "prometheus/prometheus.yml" = $script:CONFIG_TEMPLATES.Prometheus
            "loki/loki-config.yaml" = $script:CONFIG_TEMPLATES.Loki
        }

        foreach ($config in $configs.GetEnumerator()) {
            $filePath = Join-Path $script:CONFIG_PATH $config.Key
            if ((-not (Test-Path $filePath)) -or $Force) {
                $directory = Split-Path $filePath -Parent
                if (-not (Test-Path $directory)) {
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                }
                Set-Content -Path $filePath -Value $config.Value -Force
                Write-Host "  [Created] $($config.Key)" -ForegroundColor Green
            } else {
                Write-Host "  [Exists] $($config.Key)" -ForegroundColor Cyan
            }
        }

        # Set up Grafana configurations
        Write-Host "`nSetting up Grafana configurations:" -ForegroundColor Yellow
        $grafanaBasePath = Join-Path $script:CONFIG_PATH "grafana"
        $grafanaDashboardsPath = Join-Path $grafanaBasePath "provisioning\dashboards"
        $grafanaDatasourcesPath = Join-Path $grafanaBasePath "provisioning\datasources"

        @($grafanaDashboardsPath, $grafanaDatasourcesPath) | ForEach-Object {
            if (-not (Test-Path $_)) {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
                Write-Host "  [Created] directory: $($_.Split('\')[-2..-1] -join '/')" -ForegroundColor Green
            }
        }

        # Create Grafana configurations
        $dashboardFile = Join-Path $grafanaDashboardsPath "dashboard.yml"
        $datasourceFile = Join-Path $grafanaDatasourcesPath "datasources.yaml"

        if ((-not (Test-Path $dashboardFile)) -or $Force) {
            Set-Content -Path $dashboardFile -Value $script:CONFIG_TEMPLATES.GrafanaDashboard -Force
            Write-Host "  [Created] grafana/provisioning/dashboards/dashboard.yml" -ForegroundColor Green
        }
        if ((-not (Test-Path $datasourceFile)) -or $Force) {
            Set-Content -Path $datasourceFile -Value $script:CONFIG_TEMPLATES.GrafanaDatasource -Force
            Write-Host "  [Created] grafana/provisioning/datasources/datasources.yaml" -ForegroundColor Green
        }

        # Set up environment files
        Write-Host "`nSetting up environment files:" -ForegroundColor Yellow
        if (Set-EnvironmentConfig -Environment $Environment -Force:$Force) {
            Write-Host "  [OK] Created .env.$Environment" -ForegroundColor Green
        }

        Write-Host "`nEnvironment initialization completed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "`nEnvironment initialization failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $false
    }
}

function Set-EnvironmentConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [switch]$Force
    )
    
    try {
        $envFile = Join-Path $script:CONFIG_PATH ".env.$Environment"
        
        # Base URLs for different environments
        $baseUrls = @{
            Development = "http://localhost"
            Production = "http://api.insightops.com"  # Change as needed
        }

        # Basic environment variables
        $envVars = @{
            # Environment settings
            NAMESPACE = $script:NAMESPACE
            ENVIRONMENT = $Environment
            ASPNETCORE_ENVIRONMENT = $Environment
            
            # Security settings
            GRAFANA_USER = "admin"
            GRAFANA_PASSWORD = "InsightOps2024!"
            DB_USER = "insightops_user"
            DB_PASSWORD = "insightops_pwd"
            DB_NAME = "insightops_db"
            
            # Service URLs
            BASE_URL = $baseUrls[$Environment]
            
            # Development ports
            DB_PORT = if ($Environment -eq "Development") { "5433" } else { "5432" }
            FRONTEND_PORT = if ($Environment -eq "Development") { "5010" } else { "80" }
            GATEWAY_PORT = if ($Environment -eq "Development") { "5011" } else { "8080" }
            ORDER_PORT = if ($Environment -eq "Development") { "5012" } else { "8081" }
            INVENTORY_PORT = if ($Environment -eq "Development") { "5013" } else { "8082" }
            
            # Observability stack ports
            GRAFANA_PORT = if ($Environment -eq "Development") { "3001" } else { "3000" }
            PROMETHEUS_PORT = if ($Environment -eq "Development") { "9091" } else { "9090" }
            LOKI_PORT = if ($Environment -eq "Development") { "3101" } else { "3100" }
            TEMPO_PORT = "4317"
            TEMPO_HTTP_PORT = "4318"
            TEMPO_QUERY_PORT = "3200"
            
            # Retention settings
            METRICS_RETENTION = "30d"
            LOGS_RETENTION = "7d"
            TRACES_RETENTION = "48h"

            # OpenTelemetry settings
            OTEL_EXPORTER_OTLP_ENDPOINT = "http://tempo:4317"
            OTEL_SERVICE_NAME = "insightops"
            OTEL_RESOURCE_ATTRIBUTES = "service.namespace=insightops"
            
            # Feature flags
            ENABLE_TRACING = "true"
            ENABLE_METRICS = "true"
            ENABLE_LOGGING = "true"
            
            # Database connection string template
            DB_CONNECTION_STRING = "Host=localhost;Port=${DB_PORT};Database=${DB_NAME};Username=${DB_USER};Password=${DB_PASSWORD}"
            
            # Service dependencies
            PROMETHEUS_URL = "http://prometheus:9090"
            LOKI_URL = "http://loki:3100"
            TEMPO_URL = "http://tempo:4317"
            GRAFANA_URL = "http://grafana:3000"
        }
        
        # Environment-specific overrides
        if ($Environment -eq "Development") {
            $envVars["LOG_LEVEL"] = "Debug"
            $envVars["ASPNETCORE_URLS"] = "http://+:80"
        } else {
            $envVars["LOG_LEVEL"] = "Information"
            $envVars["ASPNETCORE_URLS"] = "http://+:80;https://+:443"
        }

        # Create environment file content with proper formatting
        $envContent = $envVars.GetEnumerator() | Sort-Object Key | ForEach-Object {
            "$($_.Key)=$($_.Value)"
        }

        # Ensure directory exists
        $directory = Split-Path $envFile -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        # Write to file using UTF8 without BOM
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($envFile, ($envContent -join "`n"), $utf8NoBomEncoding)

        Write-Host "Updated environment configuration: $envFile" -ForegroundColor Green
        
        # Create symlink for default .env file if in Development
        if ($Environment -eq "Development") {
            $defaultEnvFile = Join-Path $script:CONFIG_PATH ".env"
            if (Test-Path $defaultEnvFile) {
                Remove-Item $defaultEnvFile -Force
            }
            
            # Create symbolic link on Windows
            if ($IsWindows) {
                New-Item -ItemType SymbolicLink -Path $defaultEnvFile -Target $envFile -Force | Out-Null
            } else {
                # For non-Windows systems
                ln -sf $envFile $defaultEnvFile
            }
            
            Write-Host "Created symlink: $defaultEnvFile -> $envFile" -ForegroundColor Green
        }

        return $true
    }
    catch {
        Write-Host "Failed to set environment configuration: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
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

# Helper Functions for Configuration
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

# Export module members
Export-ModuleMember -Function @(
    'Initialize-Environment',
    'Set-EnvironmentConfig',
    'Get-PrometheusConfig',
    'Get-LokiConfig',
    'Get-TempoConfig',
    'Get-DockerComposeConfig',
    'Write-ConfigFile'
)