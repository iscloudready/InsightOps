# Script Configuration
$ErrorActionPreference = "Stop"

# Check PowerShell Version and switch if needed
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $ps7Path = @(
        "${env:ProgramFiles}\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
        "$env:LocalAppData\Microsoft\PowerShell\7\pwsh.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($ps7Path) {
        Write-Host "Switching to PowerShell 7..."
        Start-Process -FilePath $ps7Path -ArgumentList "-File `"$PSCommandPath`"" -NoNewWindow -Wait
        exit
    }
    else {
        Write-Host "PowerShell 7 is recommended but not found. Continuing with PowerShell $($PSVersionTable.PSVersion)..." -ForegroundColor Yellow
    }
}

# Script Paths
$scriptPath = $PSScriptRoot
$rootDir = Split-Path -Parent $scriptPath
$configDir = Join-Path $rootDir "Configurations"
$logsDir = Join-Path $rootDir "logs"
$grafanaDir = Join-Path $configDir "grafana"

# Color Configuration
$COLORS = @{
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Info = "Cyan"
    Header = "Magenta"
}

# Service Configuration
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

# Import init-insightops.ps1 if it exists
$initScript = Join-Path $scriptPath "init-insightops.ps1"
if (Test-Path $initScript) {
    . $initScript
}

# Functions
function Write-ColorMessage($Message, $Color) {
    $originalColor = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Message
    $host.UI.RawUI.ForegroundColor = $originalColor
}

function Write-Success($message) { Write-ColorMessage $message $COLORS.Success }
function Write-Info($message) { Write-ColorMessage $message $COLORS.Info }
function Write-Warning($message) { Write-ColorMessage $message $COLORS.Warning }
function Write-Error($message) { Write-ColorMessage $message $COLORS.Error }

# Menu Function
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
    Write-Host "0.  Exit"
}

# Main Functions
function Show-ContainerStatus {
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

function Show-ResourceUsage {
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

function Clean-DockerSystem {
    Write-Info "This will remove all containers and volumes. Continue? (y/N)"
    $confirm = Read-Host
    if ($confirm -eq 'y') {
        Set-Location $configDir
        docker-compose down -v
        docker system prune -f
        Write-Success "Docker system cleaned"
    }
}

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

# Main Execution
try {
    Write-Info "Starting InsightOps Docker Management..."
    Check-Prerequisites

    while ($true) {
        Show-Menu
        $choice = Read-Host "`nEnter your choice (0-17)"
        
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
    exit 1
}