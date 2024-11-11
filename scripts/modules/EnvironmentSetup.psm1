# EnvironmentSetup.psm1
# Purpose: Handles environment setup and configuration for InsightOps

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

function Initialize-Environment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Environment = $ENVIRONMENT,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        Write-InfoMessage "Initializing $Environment environment..."
        
        # Create required directories
        foreach ($dir in $REQUIRED_PATHS.Directories) {
            if (-not (Test-Path $dir) -or $Force) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-InfoMessage "Created directory: $dir"
            }
        }
        
        # Create configuration files
        Set-PrometheusConfig -Force:$Force
        Set-LokiConfig -Force:$Force
        Set-TempoConfig -Force:$Force
        Set-GrafanaConfig -Force:$Force
        
        # Set environment-specific variables
        Set-EnvironmentVariables -Environment $Environment
        
        Write-SuccessMessage "Environment initialization completed successfully"
        return $true
    }
    catch {
        Write-ErrorMessage ("Failed to initialize environment: {0}" -f $_)
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
        'Set-EnvironmentVariables',
        'Set-SSLCertificates',
        'Backup-Environment'
    )