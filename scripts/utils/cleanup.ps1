# Cleanup Script for InsightOps
param (
    [switch]$RemoveData,
    [switch]$RemoveConfigs,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configDir = Join-Path $rootDir "Configurations"

function Remove-DockerResources {
    Write-Host "Stopping and removing Docker resources..." -ForegroundColor Cyan
    
    # Stop containers
    docker-compose -f (Join-Path $configDir "docker-compose.yml") down
    
    if ($RemoveData) {
        Write-Host "Removing Docker volumes..." -ForegroundColor Yellow
        docker volume rm $(docker volume ls -q -f name=insightops_*) -f
    }
    
    # Remove images
    docker rmi $(docker images -q -f reference=insightops_*) -f
    
    # Remove network
    docker network rm insightops_network 2>$null
}

function Remove-Configurations {
    if ($RemoveConfigs) {
        Write-Host "Removing configuration files..." -ForegroundColor Yellow
        
        # Remove environment files
        Remove-Item (Join-Path $configDir ".env.*") -Force -ErrorAction SilentlyContinue
        
        # Remove generated compose files
        Remove-Item (Join-Path $configDir "docker-compose.*.yml") -Force -ErrorAction SilentlyContinue
        
        # Remove Grafana configs
        Remove-Item (Join-Path $configDir "grafana") -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Clean-Logs {
    Write-Host "Cleaning log files..." -ForegroundColor Cyan
    Get-ChildItem -Path $rootDir -Filter "*.log" -Recurse | Remove-Item -Force
}

# Main execution
try {
    if ($RemoveData -and -not $Force) {
        $confirm = Read-Host "This will remove all data. Are you sure? (y/n)"
        if ($confirm -ne "y") {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }
    }
    
    Remove-DockerResources
    Remove-Configurations
    Clean-Logs
    
    Write-Host "`nCleanup completed successfully! ✨" -ForegroundColor Green
}
catch {
    Write-Host "Error during cleanup: $_" -ForegroundColor Red
    exit 1
}