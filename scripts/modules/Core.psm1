# Core.psm1
# Purpose: Core configuration and utility functions for InsightOps
$ErrorActionPreference = "Stop"

# Base paths - corrected path resolution
#$script:PROJECT_ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
#$script:CONFIG_PATH = Join-Path -Path $script:PROJECT_ROOT -ChildPath "Configurations"
# Base paths - use environment variables set by main.ps1
$script:PROJECT_ROOT = $env:PROJECT_ROOT
$script:CONFIG_PATH = $env:CONFIG_PATH

# Add verification here
Write-Verbose "Verifying core environment variables..."
$requiredVars = @('PROJECT_ROOT', 'CONFIG_PATH', 'NAMESPACE')
foreach ($var in $requiredVars) {
    $value = Get-Item "env:$var" -ErrorAction SilentlyContinue
    if (-not $value) {
        throw "Required environment variable $var is not set"
    }
    Write-Verbose "Variable $var : $($value.Value)"
}

# Output path information for debugging
Write-Verbose "PSScriptRoot: $PSScriptRoot"
Write-Verbose "Project Root: $script:PROJECT_ROOT"
Write-Verbose "Config Path: $script:CONFIG_PATH"

# Environment Settings
$script:NAMESPACE = "insightops"
$script:DEFAULT_ENVIRONMENT = "Development"

# Verify environment variables
if (-not $script:PROJECT_ROOT) {
    throw "PROJECT_ROOT environment variable not set"
}

if (-not $script:CONFIG_PATH) {
    throw "CONFIG_PATH environment variable not set"
}

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
        Volumes = @{
            Config = "/etc/tempo/tempo.yaml"
            Data = "/var/tempo"
        }
    }
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

# Export module members
Export-ModuleMember -Function @(
    'Initialize-CorePaths'
) -Variable @(
    'PROJECT_ROOT',
    'CONFIG_PATH',
    'NAMESPACE',
    'DEFAULT_ENVIRONMENT',
    'REQUIRED_PATHS',
    'REQUIRED_FILES',
    'SERVICES'
)