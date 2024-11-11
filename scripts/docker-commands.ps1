#region Script Configuration

# Set error handling preferences
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Load Required Modules
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "Modules"
Import-Module (Join-Path $modulePath "Logging.psm1")
Import-Module (Join-Path $modulePath "Utilities.psm1")
Import-Module (Join-Path $modulePath "Prerequisites.psm1")

#endregion

#region Path Configuration

# Script Paths
$scriptPath = $PSScriptRoot
$rootDir = Split-Path -Parent $scriptPath
$configDir = Join-Path $rootDir "Configurations"
$logsDir = Join-Path $rootDir "logs"
$grafanaDir = Join-Path $configDir "grafana"

# Required Directories
$requiredDirectories = @(
    "$configDir",                          
    "$configDir\grafana\provisioning\dashboards", 
    "$configDir\grafana\provisioning\datasources",
    "$configDir\prometheus",              
    "$configDir\loki",                     
    "$configDir\tempo",                    
    "$configDir\tempo\blocks",             
    "$configDir\tempo\wal",                
    "$logsDir"                             
)

#endregion

#region Initialization

# Ensure required directories exist
function Initialize-RequiredDirectories {
    Log-Message "Ensuring required directories exist..." -Level "INFO"
    foreach ($directory in $requiredDirectories) {
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
            Log-Message "Created missing directory: $directory" -Level "INFO"
        }
    }
}

Initialize-RequiredDirectories

#endregion

#region Service Configuration

$SERVICES = @{
    Frontend = @{
        Url = "http://localhost:5010"
        HealthEndpoint = "/health"
        Container = "insightops_frontend"
    }
    ApiGateway = @{
        Url = "http://localhost:5011"
        HealthEndpoint = "/health"
        Container = "insightops_gateway"
    }
    OrderService = @{
        Url = "http://localhost:5012"
        HealthEndpoint = "/health"
        Container = "insightops_orders"
    }
    InventoryService = @{
        Url = "http://localhost:5013"
        HealthEndpoint = "/health"
        Container = "insightops_inventory"
    }
    Grafana = @{
        Url = "http://localhost:3001"
        HealthEndpoint = "/api/health"
        Container = "insightops_grafana"
        Credentials = @{
            Username = "admin"
            Password = "InsightOps2024!"
        }
    }
}

#endregion

#region Core Functions

function Show-Menu {
    Write-ColorMessage "`nInsightOps Docker Management" $COLORS.Header
    Write-ColorMessage "=== Services Management ===" $COLORS.Info
    Write-Host "1.  Start all services"
    Write-Host "2.  Stop all services"
    Write-Host "3.  Show container status"
    Write-Host "4.  Show container logs"
    Write-Host "5.  Show container stats"
    Write-Host "6.  Rebuild specific service"
    Write-Host "7.  Clean Docker system"
    Write-Host "8.  Show quick reference"
    Write-ColorMessage "=== Monitoring & Access ===" $COLORS.Info
    Write-Host "9.  Open all service URLs"
    Write-Host "10. Check service health"
    Write-Host "11. Show resource usage"
    Write-ColorMessage "=== Environment Management ===" $COLORS.Info
    Write-Host "12. Initialize environment"
    Write-Host "13. Check prerequisites"
    Write-Host "14. Run cleanup tasks"
    Write-ColorMessage "=== Advanced Options ===" $COLORS.Info
    Write-Host "15. View system metrics"
    Write-Host "16. Export container logs"
    Write-Host "17. Backup configuration"
    Write-Host "18. Test configuration"
    Write-Host "19. Test network connectivity"
    Write-Host "20. Initialize required directories"
    Write-Host "0.  Exit"
}

#endregion

#region Directory and Backup Functions

function Export-ContainerLogs {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logPath = Join-Path $logsDir $timestamp
    New-Item -ItemType Directory -Force -Path $logPath | Out-Null
    
    foreach ($service in $SERVICES.Keys) {
        $container = $SERVICES[$service].Container
        $logFile = Join-Path $logPath "$service.log"
        docker logs $container > $logFile 2>&1
        Write-Success "Exported logs for $service"
    }
}

function Backup-Configuration {
    Write-Info "Backing up configuration..."
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = "backup_$timestamp"
    New-Item -ItemType Directory -Force -Path $backupDir
    Copy-Item -Path "$configDir/*" -Destination $backupDir -Recurse
    Write-Success "Configuration backed up to: $backupDir"
}

#endregion

#region Main Execution Loop

try {
    Write-Info "Starting InsightOps Docker Management..."
    Initialize-RequiredDirectories
    Check-Prerequisites  # Imported from Prerequisites.psm1

    while ($true) {
        Show-Menu
        $choice = Read-Host "`nEnter your choice (0-20)"
        
        switch ($choice) {
            0 { exit }
            1 { Start-Services }
            2 { Stop-Services }
            3 { Show-ContainerStatus }
            4 {
                Write-Host "Available services:"
                $SERVICES.Keys | ForEach-Object { Write-Host "- $_" }
                $serviceName = Read-Host "Enter service name (press Enter for all)"
                Show-Logs $serviceName
            }
            5 { docker stats }
            6 {
                Write-Host "Available services:"
                $SERVICES.Keys | ForEach-Object { Write-Host "- $_" }
                $serviceName = Read-Host "Enter service name to rebuild"
                Rebuild-Service $serviceName
            }
            7 { Clean-DockerSystem }
            8 { Show-QuickReference }
            9 { Open-ServiceUrls }
            10 { Check-ServiceHealth }
            11 { Show-ResourceUsage }
            12 { Initialize-InsightOpsEnvironment }
            13 { Check-Prerequisites }
            14 { Clean-DockerSystem }
            15 { docker stats }
            16 { Export-ContainerLogs }
            17 { Backup-Configuration }
            18 { Test-Configuration }
            19 { Test-NetworkConnectivity }
            20 { Initialize-Directories }
            default { Write-Warning "Invalid option" }
        }

        if ($choice -ne 0) {
            Write-Host "`nPress Enter to continue..."
            Read-Host
        }
    }
}
catch {
    Write-Error "An error occurred: $_"
    Log-Message "An error occurred: $_" -Level "ERROR"
    exit 1
}

#endregion
