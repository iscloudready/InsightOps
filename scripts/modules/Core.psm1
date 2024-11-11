# Core.psm1
# Core Configuration and Constants

# Paths and Configurations
$script:CONFIG_PATH = Join-Path $PSScriptRoot "..\Configurations"
$script:GRAFANA_PATH = Join-Path $script:CONFIG_PATH "grafana"
$script:DOCKER_COMPOSE_FILE = Join-Path $script:CONFIG_PATH "docker-compose.yml"
$script:LOGS_PATH = Join-Path $PSScriptRoot "..\logs"
$script:BACKUP_PATH = Join-Path $PSScriptRoot "..\backups"

# Environment and Project Settings
$script:NAMESPACE = "insightops"
$script:PROJECT_NAME = "insightops"
$script:ENVIRONMENT = "Development"

# Color Configurations
$script:COLORS = @{
    Success = [System.ConsoleColor]::Green
    Error = [System.ConsoleColor]::Red
    Warning = [System.ConsoleColor]::Yellow
    Info = [System.ConsoleColor]::Cyan
    Header = [System.ConsoleColor]::Magenta
    Debug = [System.ConsoleColor]::Gray
}

# Service Configuration
$script:SERVICES = @{
    Frontend = @{
        Url = "http://localhost:5010"
        HealthEndpoint = "/health"
        Container = "${script:NAMESPACE}_frontend"
        Required = $true
        MinMemory = "256M"
        MaxMemory = "512M"
        MinCPU = "0.1"
        MaxCPU = "0.5"
    }
    ApiGateway = @{
        Url = "http://localhost:5011"
        HealthEndpoint = "/health"
        Container = "${script:NAMESPACE}_gateway"
        Required = $true
        MinMemory = "256M"
        MaxMemory = "512M"
        MinCPU = "0.1"
        MaxCPU = "0.5"
    }
    OrderService = @{
        Url = "http://localhost:5012"
        HealthEndpoint = "/health"
        Container = "${script:NAMESPACE}_orders"
        Required = $true
        MinMemory = "256M"
        MaxMemory = "512M"
        MinCPU = "0.1"
        MaxCPU = "0.5"
    }
    InventoryService = @{
        Url = "http://localhost:5013"
        HealthEndpoint = "/health"
        Container = "${script:NAMESPACE}_inventory"
        Required = $true
        MinMemory = "256M"
        MaxMemory = "512M"
        MinCPU = "0.1"
        MaxCPU = "0.5"
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
        MinMemory = "512M"
        MaxMemory = "1G"
        MinCPU = "0.2"
        MaxCPU = "0.7"
    }
    Prometheus = @{
        Url = "http://localhost:9091"
        Container = "${script:NAMESPACE}_prometheus"
        HealthEndpoint = "/-/healthy"
        Required = $true
        MinMemory = "512M"
        MaxMemory = "1G"
        MinCPU = "0.2"
        MaxCPU = "0.7"
    }
    Loki = @{
        Url = "http://localhost:3101"
        Container = "${script:NAMESPACE}_loki"
        HealthEndpoint = "/ready"
        Required = $true
        MinMemory = "512M"
        MaxMemory = "1G"
        MinCPU = "0.2"
        MaxCPU = "0.7"
    }
    Tempo = @{
        Url = "http://localhost:4319"
        HealthEndpoint = "/ready"
        Container = "${script:NAMESPACE}_tempo"
        Required = $true
        MinMemory = "512M"
        MaxMemory = "1G"
        MinCPU = "0.2"
        MaxCPU = "0.7"
    }
}

# Required Directories and Files
$script:REQUIRED_DIRS = @(
    ".\Scripts\utils",
    ".\Scripts\logs",
    ".\Scripts\backups",
    ".\Scripts\modules",
    ".\Configurations\grafana\provisioning\datasources",
    ".\Configurations\grafana\provisioning\dashboards",
    ".\Configurations\prometheus\rules",
    ".\Configurations\loki\rules",
    ".\Configurations\tempo\rules"
)

$script:REQUIRED_FILES = @(
    ".\Configurations\docker-compose.yml",
    ".\Configurations\prometheus.yml",
    ".\Configurations\loki-config.yaml",
    ".\Configurations\tempo.yaml",
    ".\Configurations\.env"
)

# Health Check Configuration
$script:HEALTH_CHECK_CONFIG = @{
    Interval = 30
    Timeout = 5
    Retries = 3
    InitialDelay = 10
}

# Logging Configuration
$script:LOG_CONFIG = @{
    MaxSize = "10MB"
    MaxFiles = 5
    Level = "Information"
    Path = Join-Path $script:LOGS_PATH "insightops.log"
}

# Network Configuration
$script:NETWORK_CONFIG = @{
    Name = "${script:NAMESPACE}_network"
    Driver = "bridge"
    Subnet = "172.20.0.0/16"
    Gateway = "172.20.0.1"
}

# Backup Configuration
$script:BACKUP_CONFIG = @{
    MaxBackups = 5
    Compression = $true
    RetentionDays = 7
    ExcludePatterns = @(
        "*.log",
        "*.tmp",
        "node_modules"
    )
}

# Function to initialize required directories
function Initialize-RequiredDirectories {
    foreach ($dir in $script:REQUIRED_DIRS) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "Created directory: $dir"
        }
    }
}

# Function to initialize required files
function Initialize-RequiredFiles {
    foreach ($file in $script:REQUIRED_FILES) {
        if (-not (Test-Path -Path $file)) {
            New-Item -ItemType File -Path $file -Force | Out-Null
            Write-Host "Created placeholder file: $file"
        }
    }
}

# Function to create Docker network
function Create-Network {
    $networkName = $script:NETWORK_CONFIG.Name
    $existingNetwork = docker network ls | Where-Object { $_ -match $networkName }

    if (-not $existingNetwork) {
        docker network create `
            --driver $script:NETWORK_CONFIG.Driver `
            --subnet $script:NETWORK_CONFIG.Subnet `
            --gateway $script:NETWORK_CONFIG.Gateway `
            $networkName
        Write-Host "Created Docker network: $networkName"
    }
}

# Function to backup configurations
function Backup-Configurations {
    $backupDir = Join-Path -Path $script:BACKUP_PATH -ChildPath (Get-Date -Format "yyyyMMdd_HHmmss")
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    foreach ($dir in $script:REQUIRED_DIRS) {
        Copy-Item -Path $dir -Destination $backupDir -Recurse -ErrorAction SilentlyContinue
    }

    Write-Host "Backup completed at: $backupDir"
}

# Export module members
Export-ModuleMember -Function `
    Initialize-RequiredDirectories, `
    Initialize-RequiredFiles, `
    Create-Network, `
    Backup-Configurations
