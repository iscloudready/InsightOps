# Core.psm1
# Purpose: Core configuration and utility functions for InsightOps

# Module dependencies are handled in main.ps1, remove direct module imports
# to avoid circular dependencies

# Define paths relative to module location
$script:MODULE_ROOT = $PSScriptRoot
$script:PROJECT_ROOT = Split-Path -Parent $script:MODULE_ROOT
$script:CONFIG_PATH = Join-Path $script:PROJECT_ROOT "Configurations"
$script:LOGS_PATH = Join-Path $script:PROJECT_ROOT "logs"
$script:BACKUP_PATH = Join-Path $script:PROJECT_ROOT "backups"

$script:CONFIG_ROOT = Join-Path (Split-Path -Parent $PSScriptRoot) "Configurations"
$script:DOCKER_COMPOSE_FILE = Join-Path $script:CONFIG_ROOT "docker-compose.yml"

# Environment and Project Settings
$script:NAMESPACE = "insightops"
$script:PROJECT_NAME = "insightops"
$script:ENVIRONMENT = if ($env:ASPNETCORE_ENVIRONMENT) { 
    $env:ASPNETCORE_ENVIRONMENT 
} else { 
    "Development" 
}

# Service Configuration
$script:SERVICES = @{
    Frontend = @{
        Url = "http://localhost:5010"
        HealthEndpoint = "/health"
        Container = "${script:NAMESPACE}_frontend"
        Required = $true
        Resources = @{
            MinMemory = "256M"
            MaxMemory = "512M"
            MinCPU = "0.1"
            MaxCPU = "0.5"
        }
    }
    ApiGateway = @{
        Url = "http://localhost:5011"
        HealthEndpoint = "/health"
        Container = "${script:NAMESPACE}_gateway"
        Required = $true
        Resources = @{
            MinMemory = "256M"
            MaxMemory = "512M"
            MinCPU = "0.1"
            MaxCPU = "0.5"
        }
    }
    OrderService = @{
        Url = "http://localhost:5012"
        HealthEndpoint = "/health"
        Container = "${script:NAMESPACE}_orders"
        Required = $true
        Resources = @{
            MinMemory = "256M"
            MaxMemory = "512M"
            MinCPU = "0.1"
            MaxCPU = "0.5"
        }
    }
    InventoryService = @{
        Url = "http://localhost:5013"
        HealthEndpoint = "/health"
        Container = "${script:NAMESPACE}_inventory"
        Required = $true
        Resources = @{
            MinMemory = "256M"
            MaxMemory = "512M"
            MinCPU = "0.1"
            MaxCPU = "0.5"
        }
    }
    Grafana = @{
        Url = "http://localhost:3001"
        HealthEndpoint = "/api/health"
        Container = "${script:NAMESPACE}_grafana"
        Required = $true
        Credentials = @{
            Username = "admin"
            Password = "InsightOps2024!"
        }
        Resources = @{
            MinMemory = "512M"
            MaxMemory = "1G"
            MinCPU = "0.2"
            MaxCPU = "0.7"
        }
    }
    Prometheus = @{
        Url = "http://localhost:9091"
        HealthEndpoint = "/-/healthy"
        Container = "${script:NAMESPACE}_prometheus"
        Required = $true
        Resources = @{
            MinMemory = "512M"
            MaxMemory = "1G"
            MinCPU = "0.2"
            MaxCPU = "0.7"
        }
        RetentionTime = "30d"
    }
    Loki = @{
        Url = "http://localhost:3101"
        HealthEndpoint = "/ready"
        Container = "${script:NAMESPACE}_loki"
        Required = $true
        Resources = @{
            MinMemory = "512M"
            MaxMemory = "1G"
            MinCPU = "0.2"
            MaxCPU = "0.7"
        }
    }
    Tempo = @{
        Url = "http://localhost:4319"
        HealthEndpoint = "/ready"
        Container = "${script:NAMESPACE}_tempo"
        Required = $true
        Resources = @{
            MinMemory = "512M"
            MaxMemory = "1G"
            MinCPU = "0.2"
            MaxCPU = "0.7"
        }
        Ports = @{
            OTLP_GRPC = "4317"
            OTLP_HTTP = "4318"
            Tempo_Query = "3200"
            Zipkin = "9411"
        }
    }
    PostgreSQL = @{
        Container = "${script:NAMESPACE}_db"
        HealthEndpoint = ""  # Uses native PostgreSQL health check
        Required = $true
        Resources = @{
            MinMemory = "512M"
            MaxMemory = "1G"
            MinCPU = "0.2"
            MaxCPU = "0.7"
        }
        Credentials = @{
            Username = "insightops_user"
            Password = "insightops_pwd"
            Database = "insightops_db"
            Port = "5433"
        }
        ConnectionString = "Host=${script:NAMESPACE}_db;Port=5432;Database=insightops_db;Username=insightops_user;Password=insightops_pwd;Maximum Pool Size=100;Connection Idle Lifetime=60;Pooling=true;MinPoolSize=10"
    }
}

# Service groupings for dependencies and startup order
$script:SERVICE_GROUPS = @{
    Infrastructure = @(
        "PostgreSQL"
        "Prometheus"
        "Loki"
        "Tempo"
        "Grafana"
    )
    Applications = @(
        "OrderService"
        "InventoryService"
        "ApiGateway"
        "Frontend"
    )
}

# Service dependencies
$script:SERVICE_DEPENDENCIES = @{
    Frontend = @("ApiGateway")
    ApiGateway = @("OrderService", "InventoryService")
    OrderService = @("PostgreSQL", "Tempo")
    InventoryService = @("PostgreSQL", "Tempo")
    Grafana = @("Prometheus", "Loki", "Tempo")
}

# Required paths and files structure
$script:REQUIRED_PATHS = @{
    Directories = @(
        (Join-Path $script:CONFIG_PATH "grafana/provisioning/datasources"),
        (Join-Path $script:CONFIG_PATH "grafana/provisioning/dashboards"),
        (Join-Path $script:CONFIG_PATH "prometheus/rules"),
        (Join-Path $script:CONFIG_PATH "loki/rules"),
        (Join-Path $script:CONFIG_PATH "tempo/rules"),
        $script:LOGS_PATH,
        $script:BACKUP_PATH
    )
    Files = @(
        (Join-Path $script:CONFIG_PATH "docker-compose.yml"),
        (Join-Path $script:CONFIG_PATH "prometheus.yml"),
        (Join-Path $script:CONFIG_PATH "loki-config.yaml"),
        (Join-Path $script:CONFIG_PATH "tempo.yaml"),
        (Join-Path $script:CONFIG_PATH ".env")
    )
}

# Health check configurations
$script:HEALTH_CHECK_CONFIG = @{
    Interval = "10s"
    Timeout = "5s"
    Retries = 3
    StartPeriod = "30s"
}

# Core Functions
function Initialize-Environment {
    [CmdletBinding()]
    param()
    
    Write-InfoMessage "Initializing InsightOps environment..."

    try {
        # Create required directories
        foreach ($dir in $script:REQUIRED_PATHS.Directories) {
            if (-not (Test-Path -Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-InfoMessage "Created directory: $dir"
            }
        }

        # Create placeholder files if they don't exist
        foreach ($file in $script:REQUIRED_PATHS.Files) {
            if (-not (Test-Path -Path $file)) {
                New-Item -ItemType File -Path $file -Force | Out-Null
                Write-InfoMessage "Created placeholder file: $file"
            }
        }

        Write-SuccessMessage "Environment initialization completed successfully"
        return $true
    }
    catch {
        Write-ErrorMessage "Failed to initialize environment: $_"
        return $false
    }
}

function Get-ServiceConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )
    
    if ($script:SERVICES.ContainsKey($ServiceName)) {
        return $script:SERVICES[$ServiceName]
    }
    
    Write-ErrorMessage "Service configuration not found for: $ServiceName"
    return $null
}

function Get-ServiceDependencies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )
    
    if ($script:SERVICE_DEPENDENCIES.ContainsKey($ServiceName)) {
        return $script:SERVICE_DEPENDENCIES[$ServiceName]
    }
    
    return @()
}

function Test-NetworkConnectivity {
    [CmdletBinding()]
    param()
    
    try {
        Write-Information "Testing network connectivity..."
        
        $services = $script:SERVICES

        foreach ($service in $services.GetEnumerator()) {
            $serviceConfig = $service.Value
            if (-not $serviceConfig.Url) { continue }

            try {
                $uri = [System.Uri]$serviceConfig.Url
                $hostName = $uri.Host
                $port = $uri.Port

                $testResult = Test-NetConnection -ComputerName $hostName `
                                               -Port $port `
                                               -WarningAction SilentlyContinue `
                                               -ErrorAction SilentlyContinue

                if ($testResult.TcpTestSucceeded) {
                    Write-Success "✓ $($service.Key) is accessible at $($serviceConfig.Url)"
                }
                else {
                    Write-Warning "✗ $($service.Key) is not accessible at $($serviceConfig.Url)"
                }
            }
            catch {
                Write-Error "Failed to test $($service.Key): $_"
            }
        }
        return $true
    }
    catch {
        Write-Error "Network connectivity test failed: $_"
        return $false
    }
}

function Test-ServiceHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServiceName
    )
    
    try {
        Write-Information "Checking service health..."
        
        $servicesToCheck = if ($ServiceName) {
            if ($script:SERVICES.ContainsKey($ServiceName)) {
                @{ $ServiceName = $script:SERVICES[$ServiceName] }
            }
            else {
                throw "Service '$ServiceName' not found in configuration"
            }
        }
        else {
            $script:SERVICES
        }

        $results = @()
        foreach ($service in $servicesToCheck.GetEnumerator()) {
            $config = $service.Value
            if (-not $config.Url -or -not $config.HealthEndpoint) { continue }

            try {
                $uri = "$($config.Url)$($config.HealthEndpoint)"
                $response = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing -TimeoutSec 5

                $status = if ($response.StatusCode -eq 200) {
                    Write-Success "✓ $($service.Key) is healthy"
                    "Healthy"
                }
                else {
                    Write-Warning "⚠ $($service.Key) returned status code: $($response.StatusCode)"
                    "Unhealthy"
                }
            }
            catch {
                Write-Error "✗ $($service.Key) health check failed: $_"
                $status = "Error"
            }

            $results += [PSCustomObject]@{
                Service = $service.Key
                Status = $status
                Endpoint = $uri
            }
        }

        if ($results.Count -gt 0) {
            Write-Host "`nService Health Status:" -ForegroundColor Cyan
            $results | Format-Table -AutoSize
        }

        return $true
    }
    catch {
        Write-Error "Service health check failed: $_"
        return $false
    }
}

function Test-Configuration {
    [CmdletBinding()]
    param()

    try {
        Write-Information "Checking configuration files..."

        # Required configuration files
        $configRoot = "D:\Users\Pradeep\Downloads\Grafana solution architect demo\GrafanaDemo\InsightOps\Configurations"
        $requiredFiles = @{
            "Docker Compose" = Join-Path $configRoot "docker-compose.yml"
            "Prometheus" = Join-Path $configRoot "prometheus.yml"
            "Loki" = Join-Path $configRoot "loki-config.yaml"
            "Tempo" = Join-Path $configRoot "tempo.yaml"
        }

        $allValid = $true
        foreach ($file in $requiredFiles.GetEnumerator()) {
            if (Test-Path $file.Value) {
                Write-Success " Found $($file.Key) configuration: $($file.Value)"
            } else {
                Write-Warning " Missing $($file.Key) configuration: $($file.Value)"
                $allValid = $false
            }
        }

        if (-not $allValid) {
            Write-Information "Attempting to create default configurations..."
            Initialize-DefaultConfigurations -ConfigRoot $configRoot
        }

        return $allValid
    }
    catch {
        Write-Error "Configuration check failed: $_"
        return $false
    }
}

function _Test-Configuration {
    [CmdletBinding()]
    param()

    try {
        Write-Information "Checking configuration files..."

        # Required configuration files
        $requiredFiles = @{
            "Docker Compose" = $script:DOCKER_COMPOSE_FILE
            "Prometheus" = Join-Path $script:CONFIG_ROOT "prometheus.yml"
            "Loki" = Join-Path $script:CONFIG_ROOT "loki-config.yaml"
            "Tempo" = Join-Path $script:CONFIG_ROOT "tempo.yaml"
        }

        $allValid = $true
        foreach ($file in $requiredFiles.GetEnumerator()) {
            if (Test-Path $file.Value) {
                Write-Success " Found $($file.Key) configuration: $($file.Value)"
            } else {
                Write-Warning " Missing $($file.Key) configuration: $($file.Value)"
                $allValid = $false
            }
        }

        if (-not $allValid) {
            Write-Information "Attempting to create default configurations..."
            Initialize-DefaultConfigurations
        }

        return $allValid
    }
    catch {
        Write-Error "Configuration check failed: $_"
        return $false
    }
}

function Initialize-DefaultConfigurations {
    [CmdletBinding()]
    param(
        [string]$ConfigRoot
    )

    try {
        # Create Configurations directory if it doesn't exist
        if (-not (Test-Path $ConfigRoot)) {
            New-Item -ItemType Directory -Path $ConfigRoot -Force | Out-Null
            Write-Success "Created Configurations directory"
        }

        # Default configurations content...

        # Write docker-compose.yml
        $dockerComposeFilePath = Join-Path $ConfigRoot "docker-compose.yml"
        if (-not (Test-Path $dockerComposeFilePath)) {
            Set-Content -Path $dockerComposeFilePath -Value $dockerComposeContent
            Write-Success "Created default docker-compose.yml"
        }

        # Similarly, create other default configurations...
    }
    catch {
        Write-Error "Failed to initialize default configurations: $_"
        return $false
    }
}

function _Initialize-DefaultConfigurations {
    [CmdletBinding()]
    param()

    try {
        # Create Configurations directory if it doesn't exist
        if (-not (Test-Path $script:CONFIG_ROOT)) {
            New-Item -ItemType Directory -Path $script:CONFIG_ROOT -Force | Out-Null
            Write-Success "Created Configurations directory"
        }

        # Default docker-compose.yml content with correct PowerShell escaping
        $dockerComposeContent = @"
version: '3.8'

services:
  postgres:
    image: postgres:13
    container_name: "$($script:NAMESPACE)_db"
    environment:
      POSTGRES_USER: "`${DB_USER:-insightops_user}"
      POSTGRES_PASSWORD: "`${DB_PASSWORD:-insightops_pwd}"
      POSTGRES_DB: "`${DB_NAME:-insightops_db}"
    volumes:
      - "postgres_data:/var/lib/postgresql/data"
    ports:
      - "5433:5432"
    networks:
      - "$($script:NAMESPACE)_network"

  grafana:
    image: grafana/grafana:latest
    container_name: "$($script:NAMESPACE)_grafana"
    environment:
      - "GF_SECURITY_ADMIN_USER=admin"
      - "GF_SECURITY_ADMIN_PASSWORD=InsightOps2024!"
    volumes:
      - "grafana_data:/var/lib/grafana"
    ports:
      - "3001:3000"
    networks:
      - "$($script:NAMESPACE)_network"

  prometheus:
    image: prom/prometheus:latest
    container_name: "$($script:NAMESPACE)_prometheus"
    volumes:
      - "./prometheus.yml:/etc/prometheus/prometheus.yml"
      - "prometheus_data:/prometheus"
    ports:
      - "9091:9090"
    networks:
      - "$($script:NAMESPACE)_network"

  loki:
    image: grafana/loki:2.9.3
    container_name: "$($script:NAMESPACE)_loki"
    volumes:
      - "./loki-config.yaml:/etc/loki/config.yaml"
      - "loki_data:/loki"
    ports:
      - "3101:3100"
    networks:
      - "$($script:NAMESPACE)_network"

  tempo:
    image: grafana/tempo:latest
    container_name: "$($script:NAMESPACE)_tempo"
    volumes:
      - "./tempo.yaml:/etc/tempo.yaml"
      - "tempo_data:/tmp/tempo"
    ports:
      - "4317:4317"
      - "4318:4318"
    networks:
      - "$($script:NAMESPACE)_network"

volumes:
  postgres_data:
    name: "$($script:NAMESPACE)_postgres_data"
  grafana_data:
    name: "$($script:NAMESPACE)_grafana_data"
  prometheus_data:
    name: "$($script:NAMESPACE)_prometheus_data"
  loki_data:
    name: "$($script:NAMESPACE)_loki_data"
  tempo_data:
    name: "$($script:NAMESPACE)_tempo_data"

networks:
  "$($script:NAMESPACE)_network":
    name: "$($script:NAMESPACE)_network"
    driver: bridge
"@

        # Write docker-compose.yml
        $dockerComposeFilePath = Join-Path $script:CONFIG_ROOT "docker-compose.yml"
        if (-not (Test-Path $dockerComposeFilePath)) {
            Set-Content -Path $dockerComposeFilePath -Value $dockerComposeContent
            Write-Success "Created default docker-compose.yml"
        }

        # Create other default configurations
        $lokiConfigContent = @"
# Loki configuration content here
"@
        $lokiConfigFilePath = Join-Path $script:CONFIG_ROOT "loki-config.yaml"
        Set-Content -Path $lokiConfigFilePath -Value $lokiConfigContent
        Write-Success "Created default loki-config.yaml"

        $prometheusConfigContent = @"
# Prometheus configuration content here
"@
        $prometheusConfigFilePath = Join-Path $script:CONFIG_ROOT "prometheus.yml"
        Set-Content -Path $prometheusConfigFilePath -Value $prometheusConfigContent
        Write-Success "Created default prometheus.yml"

        $tempoConfigContent = @"
# Tempo configuration content here
"@
        $tempoConfigFilePath = Join-Path $script:CONFIG_ROOT "tempo.yaml"
        Set-Content -Path $tempoConfigFilePath -Value $tempoConfigContent
        Write-Success "Created default tempo.yaml"

        return $true
    }
    catch {
        Write-Error "Failed to initialize default configurations: $_"
        return $false
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-Environment',
    'Get-ServiceConfig',
    'Get-ServiceDependencies',
    'Test-ServiceHealth',
	'Test-NetworkConnectivity',
    'Test-ServiceHealth',
	'Test-Configuration',
    'Initialize-DefaultConfigurations'
) -Variable @(
    'NAMESPACE',
    'PROJECT_NAME',
    'ENVIRONMENT',
    'SERVICES',
    'SERVICE_GROUPS',
    'SERVICE_DEPENDENCIES',
    'CONFIG_PATH',
    'LOGS_PATH',
    'BACKUP_PATH',
    'REQUIRED_PATHS',
    'HEALTH_CHECK_CONFIG',
	'CONFIG_ROOT',
    'DOCKER_COMPOSE_FILE'
)