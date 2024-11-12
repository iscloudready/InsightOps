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
    jaeger:
      protocols:
        thrift_http:
          endpoint: 0.0.0.0:14268
        grpc:
          endpoint: 0.0.0.0:14250
    otlp:
      protocols:
        http:
          endpoint: 0.0.0.0:4318
        grpc:
          endpoint: 0.0.0.0:4317

storage:
  trace:
    backend: local
    local:
      path: /tmp/tempo/blocks
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

function Get-PrometheusConfig {
    return $script:CONFIG_TEMPLATES.Prometheus
}

function Get-LokiConfig {
    return $script:CONFIG_TEMPLATES.Loki
}

function Get-TempoConfig {
    return $script:CONFIG_TEMPLATES.Tempo
}

function Get-DockerComposeConfig {
    return @'
# Remove version as it's now obsolete
# version: '3.8'  # This line is removed

name: insightops  # Add this for explicit naming

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
    command: [ "-config.file=/etc/tempo/tempo.yaml" ]
    volumes:
      - ./tempo/tempo.yaml:/etc/tempo/tempo.yaml
      - tempo_data:/tmp/tempo
    ports:
      - "${TEMPO_PORT:-4317}:4317"
      - "${TEMPO_PORT_HTTP:-4318}:4318"
      - "3200:3200"
      - "9411:9411"
    healthcheck:
      <<: *default-healthcheck
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3200/ready"]
      start_period: 45s
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
        $configs = @{
            "tempo/tempo.yaml" = Get-TempoConfig
            "docker-compose.yml" = Get-DockerComposeConfig
            "prometheus/prometheus.yml" = Get-PrometheusConfig
            "loki/loki-config.yaml" = Get-LokiConfig
        }

        foreach ($config in $configs.GetEnumerator()) {
            $filePath = Join-Path $script:CONFIG_PATH $config.Key
            if ((-not (Test-Path $filePath)) -or $Force) {
                # Ensure directory exists
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
        
        # Create Grafana directory structure
        $grafanaBasePath = Join-Path $script:CONFIG_PATH "grafana"
        $grafanaDashboardsPath = Join-Path $grafanaBasePath "provisioning\dashboards"
        $grafanaDatasourcesPath = Join-Path $grafanaBasePath "provisioning\datasources"

        # Ensure directories exist
        @($grafanaDashboardsPath, $grafanaDatasourcesPath) | ForEach-Object {
            if (-not (Test-Path $_)) {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
                Write-Host "  [Created] directory: $($_.Split('\')[-2..-1] -join '/')" -ForegroundColor Green
            }
        }

        # Create dashboard configuration
        $dashboardFile = Join-Path $grafanaDashboardsPath "dashboard.yml"
        if ((-not (Test-Path $dashboardFile)) -or $Force) {
            Set-Content -Path $dashboardFile -Value $script:CONFIG_TEMPLATES.GrafanaDashboard -Force
            Write-Host "  [Created] grafana/provisioning/dashboards/dashboard.yml" -ForegroundColor Green
        } else {
            Write-Host "  [Exists] grafana/provisioning/dashboards/dashboard.yml" -ForegroundColor Cyan
        }

        # Create datasource configuration
        $datasourceFile = Join-Path $grafanaDatasourcesPath "datasources.yaml"
        if ((-not (Test-Path $datasourceFile)) -or $Force) {
            Set-Content -Path $datasourceFile -Value $script:CONFIG_TEMPLATES.GrafanaDatasource -Force
            Write-Host "  [Created] grafana/provisioning/datasources/datasources.yaml" -ForegroundColor Green
        } else {
            Write-Host "  [Exists] grafana/provisioning/datasources/datasources.yaml" -ForegroundColor Cyan
        }

        # Create environment files
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

function __Initialize-Environment {
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

        # Create configuration files
        Write-Host "`nSetting up configuration files:" -ForegroundColor Yellow
        $templates = @{
            "prometheus.yml" = Get-PrometheusConfig
            "loki-config.yaml" = Get-LokiConfig
            "tempo.yaml" = Get-TempoConfig
            "docker-compose.yml" = Get-DockerComposeConfig
        }

        foreach ($template in $templates.GetEnumerator()) {
            $filePath = Join-Path $script:CONFIG_PATH $template.Key
            if ((-not (Test-Path $filePath)) -or $Force) {
                $template.Value | Set-Content -Path $filePath -Force
                Write-Host "  [Created] $($template.Key)" -ForegroundColor Green
            } else {
                Write-Host "  [Exists] $($template.Key)" -ForegroundColor Cyan
            }
        }

        # Create environment files
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
        [string]$Environment,
        [switch]$Force
    )
    
    try {
        $envFile = Join-Path $script:CONFIG_PATH ".env.$Environment"
        
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
            DB_PORT = if ($Environment -eq "Development") { "5433" } else { "5432" }
            FRONTEND_PORT = if ($Environment -eq "Development") { "5010" } else { "80" }
            GATEWAY_PORT = if ($Environment -eq "Development") { "5011" } else { "8080" }
            ORDER_PORT = if ($Environment -eq "Development") { "5012" } else { "8081" }
            INVENTORY_PORT = if ($Environment -eq "Development") { "5013" } else { "8082" }
            GRAFANA_PORT = if ($Environment -eq "Development") { "3001" } else { "3000" }
            PROMETHEUS_PORT = if ($Environment -eq "Development") { "9091" } else { "9090" }
            LOKI_PORT = if ($Environment -eq "Development") { "3101" } else { "3100" }
            TEMPO_PORT = "4317"
            METRICS_RETENTION = "30d"
        }

        # Create environment file content
        $envContent = $envVars.GetEnumerator() | ForEach-Object {
            "$($_.Key)=$($_.Value)"
        }

        # Write to file
        Set-Content -Path $envFile -Value $envContent -Force
        return $true
    }
    catch {
        Write-Host "Failed to set environment configuration: $_" -ForegroundColor Red
        return $false
    }
}

function Set-PrometheusConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    $configPath = Join-Path $CONFIG_PATH "prometheus/prometheus.yml"
    if (-not (Test-Path $configPath) -or $Force) {
        Set-Content -Path $configPath -Value $CONFIG_TEMPLATES.Prometheus -Force
        Write-InfoMessage "Created Prometheus configuration: $configPath"
    }
}

function Set-LokiConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    $configPath = Join-Path $CONFIG_PATH "loki/loki-config.yaml"
    if (-not (Test-Path $configPath) -or $Force) {
        Set-Content -Path $configPath -Value $CONFIG_TEMPLATES.Loki -Force
        Write-InfoMessage "Created Loki configuration: $configPath"
    }
}

function Set-TempoConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    $configPath = Join-Path $CONFIG_PATH "tempo/tempo.yaml"
    if (-not (Test-Path $configPath) -or $Force) {
        Set-Content -Path $configPath -Value $CONFIG_TEMPLATES.Tempo -Force
        Write-InfoMessage "Created Tempo configuration: $configPath"
    }
}

function Set-GrafanaConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Set up dashboard configuration
    $dashboardConfig = Join-Path $CONFIG_PATH "grafana/provisioning/dashboards/dashboard.yml"
    if (-not (Test-Path $dashboardConfig) -or $Force) {
        Set-Content -Path $dashboardConfig -Value $CONFIG_TEMPLATES.GrafanaDashboard -Force
        Write-InfoMessage "Created Grafana dashboard configuration: $dashboardConfig"
    }
    
    # Set up datasource configuration
    $datasourceConfig = Join-Path $CONFIG_PATH "grafana/provisioning/datasources/datasources.yaml"
    if (-not (Test-Path $datasourceConfig) -or $Force) {
        Set-Content -Path $datasourceConfig -Value $CONFIG_TEMPLATES.GrafanaDatasource -Force
        Write-InfoMessage "Created Grafana datasource configuration: $datasourceConfig"
    }
}

    function Set-EnvironmentVariables {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Environment
        )
        
        $envFile = Join-Path $CONFIG_PATH ".env.$Environment"
        $defaultEnvFile = Join-Path $CONFIG_PATH ".env"
        
        try {
            # Default environment variables
            $defaultEnvVars = @{
                NAMESPACE = $NAMESPACE
                ENVIRONMENT = $Environment
                GRAFANA_USER = "admin"
                GRAFANA_PASSWORD = "InsightOps2024!"
                DB_USER = "insightops_user"
                DB_PASSWORD = "insightops_pwd"
                DB_NAME = "insightops_db"
                METRICS_RETENTION = "30d"
                TEMPO_RETENTION = "24h"
            }

            # Environment-specific overrides
            $envSpecificVars = switch ($Environment.ToLower()) {
                "development" {
                    @{
                        ASPNETCORE_ENVIRONMENT = "Development"
                        FRONTEND_PORT = "5010"
                        GATEWAY_PORT = "5011"
                        ORDER_PORT = "5012"
                        INVENTORY_PORT = "5013"
                        GRAFANA_PORT = "3001"
                        PROMETHEUS_PORT = "9091"
                        LOKI_PORT = "3101"
                        TEMPO_PORT = "4317"
                        DB_PORT = "5433"
                    }
                }
                "production" {
                    @{
                        ASPNETCORE_ENVIRONMENT = "Production"
                        FRONTEND_PORT = "80"
                        GATEWAY_PORT = "8080"
                        ORDER_PORT = "8081"
                        INVENTORY_PORT = "8082"
                        GRAFANA_PORT = "3000"
                        PROMETHEUS_PORT = "9090"
                        LOKI_PORT = "3100"
                        TEMPO_PORT = "4317"
                        DB_PORT = "5432"
                    }
                }
                default {
                    Write-WarningMessage "Unknown environment: $Environment. Using development settings."
                    @{}
                }
            }

            # Combine default and environment-specific variables
            $allEnvVars = $defaultEnvVars + $envSpecificVars

            # Create environment-specific .env file
            $envContent = $allEnvVars.GetEnumerator() | ForEach-Object {
                "${0}=${1}" -f $_.Key, $_.Value
            }

            Set-Content -Path $envFile -Value $envContent -Force
            Write-InfoMessage "Created environment file: $envFile"

            # Create symlink for default .env file
            if (Test-Path $defaultEnvFile) {
                Remove-Item $defaultEnvFile -Force
            }
            New-Item -ItemType SymbolicLink -Path $defaultEnvFile -Target $envFile -Force
            Write-InfoMessage "Created symlink: $defaultEnvFile -> $envFile"
        }
        catch {
            Write-ErrorMessage ("Failed to set environment variables: {0}" -f $_)
            return $false
        }
    }

    function Set-SSLCertificates {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Environment
        )
        
        if ($Environment -eq "Development") {
            Write-InfoMessage "Skipping SSL certificate setup for Development environment"
            return $true
        }

        try {
            $certPath = Join-Path $CONFIG_PATH "certificates"
            if (-not (Test-Path $certPath)) {
                New-Item -ItemType Directory -Path $certPath -Force | Out-Null
            }

            # Generate self-signed certificate for testing
            $cert = New-SelfSignedCertificate `
                -DnsName "insightops.local" `
                -CertStoreLocation "Cert:\LocalMachine\My" `
                -NotAfter (Get-Date).AddYears(1) `
                -KeySpec KeyExchange

            # Export certificate
            $certPassword = ConvertTo-SecureString -String "InsightOps2024!" -Force -AsPlainText
            $certFile = Join-Path $certPath "insightops.pfx"
            Export-PfxCertificate -Cert $cert -FilePath $certFile -Password $certPassword -Force

            Write-SuccessMessage "SSL certificates generated successfully"
            return $true
        }
        catch {
            Write-ErrorMessage ("Failed to set up SSL certificates: {0}" -f $_)
            return $false
        }
    }

    function Backup-Environment {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $false)]
            [string]$BackupPath = (Join-Path $BACKUP_PATH (Get-Date -Format "yyyyMMdd_HHmmss"))
        )
        
        try {
            Write-InfoMessage "Creating environment backup..."

            # Create backup directory
            New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

            # Backup configuration files
            Copy-Item -Path $CONFIG_PATH -Destination $BackupPath -Recurse -Force
            
            # Backup environment variables
            Get-ChildItem -Path $CONFIG_PATH -Filter ".env*" | Copy-Item -Destination $BackupPath -Force

            Write-SuccessMessage "Environment backup created successfully at: $BackupPath"
            return $true
        }
        catch {
            Write-ErrorMessage ("Failed to backup environment: {0}" -f $_)
            return $false
        }
    }

# Export module members
Export-ModuleMember -Function @(
    'Initialize-Environment',
    'Set-EnvironmentConfig',
    'Set-SSLCertificates',
    'Backup-Environment',
    'Get-PrometheusConfig',
    'Get-LokiConfig',
    'Get-TempoConfig',
    'Get-DockerComposeConfig'
)