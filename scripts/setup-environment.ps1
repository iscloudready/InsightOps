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

# Import logging if available
if (Test-Path "$PSScriptRoot\Modules\Logging.psm1") {
    Import-Module "$PSScriptRoot\Modules\Logging.psm1"
} else {
    function Log-Message { param([string]$Message, [string]$Level = "INFO") Write-Host "$Message" }
}

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
    Log-Message "Creating environment-specific configuration for $Environment" -Level "INFO"
    
    $config = $configs[$Environment]
    
    # Create docker-compose config
    try {
        $composeTemplate = Get-Content (Join-Path $configDir "docker-compose.template.yml")
        $composeContent = $composeTemplate `
            -replace '{{POSTGRES_PORT}}', $config.PostgresPort `
            -replace '{{GRAFANA_PORT}}', $config.GrafanaPort `
            -replace '{{METRICS_RETENTION}}', $config.MetricsRetention
            
        Set-Content -Path (Join-Path $configDir "docker-compose.$Environment.yml") -Value $composeContent
        Log-Message "docker-compose configuration created for $Environment" -Level "SUCCESS"
    }
    catch {
        Log-Message "Error creating docker-compose configuration: $_" -Level "ERROR"
        throw
    }

    # Create application settings
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
        try {
            $appSettings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
            Log-Message "Created appsettings for $service in $Environment" -Level "SUCCESS"
        }
        catch {
            Log-Message "Error creating appsettings for $service: $_" -Level "ERROR"
            throw
        }
    }
}

# Create environment variables file
function New-EnvironmentVariables {
    try {
        $envFile = @"
ASPNETCORE_ENVIRONMENT=$Environment
POSTGRES_PORT=$($configs[$Environment].PostgresPort)
GRAFANA_PORT=$($configs[$Environment].GrafanaPort)
METRICS_RETENTION=$($configs[$Environment].MetricsRetention)
"@
        Set-Content -Path (Join-Path $configDir ".env.$Environment") -Value $envFile
        Log-Message "Environment variables file created for $Environment" -Level "SUCCESS"
    }
    catch {
        Log-Message "Error creating environment variables file: $_" -Level "ERROR"
        throw
    }
}

# Setup SSL certificates for non-Development environments
function Setup-SSL {
    if ($Environment -ne "Development") {
        Log-Message "Setting up SSL certificates for $Environment..." -Level "INFO"
        # Add SSL setup logic here
    }
}

# Main execution
try {
    Log-Message "Setting up $Environment environment..." -Level "INFO"
    
    # Check if environment already exists
    $envFile = Join-Path $configDir ".env.$Environment"
    if (Test-Path $envFile -and -not $Force) {
        Log-Message "Environment $Environment already exists. Use -Force to overwrite." -Level "WARNING"
        return
    }
    
    New-EnvironmentConfig
    New-EnvironmentVariables
    Setup-SSL
    
    Log-Message "Environment $Environment setup completed successfully!" -Level "SUCCESS"
    Log-Message "Use 'docker-compose -f docker-compose.$Environment.yml up -d' to start services" -Level "INFO"
}
catch {
    Log-Message "Error setting up environment: $_" -Level "ERROR"
    exit 1
}
