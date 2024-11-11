# Cleanup Script for InsightOps
param (
    [switch]$RemoveData,
    [switch]$RemoveConfigs,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configDir = Join-Path $rootDir "Configurations"

# Ensure logging is set up if Logging.psm1 is available
if (Test-Path "$PSScriptRoot\Logging.psm1") {
    Import-Module "$PSScriptRoot\Logging.psm1"
} else {
    function Log-Message { param([string]$Message, [string]$Level = "INFO") Write-Host "$Message" }
}

function Remove-DockerResources {
    Log-Message "Stopping and removing Docker resources..." -Level "INFO"
    
    try {
        # Stop containers
        docker-compose -f (Join-Path $configDir "docker-compose.yml") down
        Log-Message "Stopped and removed containers" -Level "SUCCESS"
        
        if ($RemoveData) {
            Log-Message "Removing Docker volumes..." -Level "WARNING"
            docker volume rm $(docker volume ls -q -f name=insightops_*) -f
        }
        
        # Remove images
        docker rmi $(docker images -q -f reference=insightops_*) -f
        Log-Message "Removed Docker images" -Level "SUCCESS"
        
        # Remove network
        docker network rm insightops_network 2>$null
        Log-Message "Removed Docker network" -Level "SUCCESS"
    }
    catch {
        Log-Message "Error during Docker resource cleanup: $_" -Level "ERROR"
    }
}

function Remove-Configurations {
    if ($RemoveConfigs) {
        Log-Message "Removing configuration files..." -Level "WARNING"
        
        try {
            # Remove environment files
            Remove-Item (Join-Path $configDir ".env.*") -Force -ErrorAction SilentlyContinue
            
            # Remove generated compose files
            Remove-Item (Join-Path $configDir "docker-compose.*.yml") -Force -ErrorAction SilentlyContinue
            
            # Remove Grafana configs
            Remove-Item (Join-Path $configDir "grafana") -Recurse -Force -ErrorAction SilentlyContinue
            Log-Message "Removed configurations successfully" -Level "SUCCESS"
        }
        catch {
            Log-Message "Error during configuration file cleanup: $_" -Level "ERROR"
        }
    }
}

function Clean-Logs {
    Log-Message "Cleaning log files..." -Level "INFO"
    try {
        Get-ChildItem -Path $rootDir -Filter "*.log" -Recurse | Remove-Item -Force
        Log-Message "Log cleanup completed" -Level "SUCCESS"
    }
    catch {
        Log-Message "Error during log cleanup: $_" -Level "ERROR"
    }
}

# Main execution
try {
    if ($RemoveData -and -not $Force) {
        $confirm = Read-Host "This will remove all data. Are you sure? (y/n)"
        if ($confirm -ne "y") {
            Log-Message "Operation cancelled by user." -Level "WARNING"
            return
        }
    }
    
    Remove-DockerResources
    Remove-Configurations
    Clean-Logs
    
    Log-Message "`nCleanup completed successfully!" -Level "SUCCESS"
}
catch {
    Log-Message "Error during cleanup: $_" -Level "ERROR"
    exit 1
}
