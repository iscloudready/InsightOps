# Environment Setup Script for InsightOps
param (
    [Parameter(Mandatory=$true)]
    [ValidateSet('Development', 'Staging', 'Production')]
    [string]$Environment,
    
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configDir = Join-Path $rootDir "Configurations"

# Environment-specific configurations
$configs = @{
    Development = @{
        GrafanaAuth = $false
        MetricsRetention = "2d"
        LogLevel = "Debug"
        PostgresPort = 5433
        GrafanaPort = 3001
    }
    Staging = @{
        GrafanaAuth = $true
        MetricsRetention = "15d"
        LogLevel = "Information"
        PostgresPort = 5434
        GrafanaPort = 3002
    }
    Production = @{
        GrafanaAuth = $true
        MetricsRetention = "30d"
        LogLevel = "Warning"
        PostgresPort = 5435
        GrafanaPort = 3003
    }
}

# Create environment configuration
function New-EnvironmentConfig {
    $config = $configs[$Environment]
    
    # Create environment-specific docker-compose
    $composeTemplate = Get-Content (Join-Path $configDir "docker-compose.template.yml")
    $composeContent = $composeTemplate `
        -replace '{{POSTGRES_PORT}}', $config.PostgresPort `
        -replace '{{GRAFANA_PORT}}', $config.GrafanaPort `
        -replace '{{METRICS_RETENTION}}', $config.MetricsRetention
        
    Set-Content -Path (Join-Path $configDir "docker-compose.$Environment.yml") -Value $composeContent
    
    # Create environment-specific appsettings
    $appSettings = @{
        Logging = @{
            LogLevel = @{
                Default = $config.LogLevel
            }
        }
        ConnectionStrings = @{
            Postgres = "Host=localhost;Port=$($config.PostgresPort);Database=insightops_db;Username=insightops_user;Password=insightops_pwd"
        }
    }
    
    $services = @("OrderService", "InventoryService", "ApiGateway", "FrontendService")
    foreach ($service in $services) {
        $settingsPath = Join-Path $rootDir $service "appsettings.$Environment.json"
        $appSettings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
    }
}

# Create environment variables file
function New-EnvironmentVariables {
    $envFile = @"
ASPNETCORE_ENVIRONMENT=$Environment
POSTGRES_PORT=$($configs[$Environment].PostgresPort)
GRAFANA_PORT=$($configs[$Environment].GrafanaPort)
METRICS_RETENTION=$($configs[$Environment].MetricsRetention)
"@
    
    Set-Content -Path (Join-Path $configDir ".env.$Environment") -Value $envFile
}

# Setup SSL certificates for non-Development environments
function Setup-SSL {
    if ($Environment -ne "Development") {
        Write-Host "Setting up SSL certificates for $Environment..." -ForegroundColor Cyan
        # Add your SSL setup logic here
    }
}

# Main execution
try {
    Write-Host "Setting up $Environment environment..." -ForegroundColor Cyan
    
    # Check if environment already exists
    $envFile = Join-Path $configDir ".env.$Environment"
    if (Test-Path $envFile -and -not $Force) {
        Write-Host "Environment $Environment already exists. Use -Force to overwrite." -ForegroundColor Yellow
        return
    }
    
    New-EnvironmentConfig
    New-EnvironmentVariables
    Setup-SSL
    
    Write-Host "`nEnvironment $Environment setup completed successfully! ✨" -ForegroundColor Green
    Write-Host "Use 'docker-compose -f docker-compose.$Environment.yml up -d' to start services" -ForegroundColor Yellow
}
catch {
    Write-Host "Error setting up environment: $_" -ForegroundColor Red
    exit 1
}