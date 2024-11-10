# InsightOps Docker Management Script
using namespace System.Management.Automation
using namespace System.Collections.Generic

# Script Configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script Paths
$scriptPath = $PSScriptRoot
$CONFIG_PATH = Join-Path $scriptPath "..\Configurations"
$GRAFANA_PATH = Join-Path $CONFIG_PATH "grafana"
$DOCKER_COMPOSE_FILE = Join-Path $CONFIG_PATH "docker-compose.yml"

# Color Configuration
$COLORS = @{
    Success = [System.ConsoleColor]::Green
    Error = [System.ConsoleColor]::Red
    Warning = [System.ConsoleColor]::Yellow
    Info = [System.ConsoleColor]::Cyan
    Header = [System.ConsoleColor]::Magenta
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
    Prometheus = @{
        Url = "http://localhost:9091"
        Container = "insightops_prometheus"
    }
    Loki = @{
        Url = "http://localhost:3101"
        Container = "insightops_loki"
    }
}

# Function Definitions
function Print-Header($title) {
    Write-Host "`n=== $title ===" -ForegroundColor $COLORS.Header
}

function Test-Environment {
    $required = @(
        $DOCKER_COMPOSE_FILE,
        (Join-Path $GRAFANA_PATH "provisioning\datasources\datasources.yml"),
        (Join-Path $CONFIG_PATH "prometheus.yml")
    )
    
    $missing = $required | Where-Object { -not (Test-Path $_) }
    if ($missing) {
        Write-Host "Missing required files:`n$($missing -join "`n")" -ForegroundColor $COLORS.Error
        return $false
    }
    return $true
}

function Start-Services {
    Print-Header "Starting Services"
    try {
        Push-Location $CONFIG_PATH
        docker-compose up -d --build
        Write-Host "Services started successfully" -ForegroundColor $COLORS.Success
    }
    catch {
        Write-Host "Error starting services: $_" -ForegroundColor $COLORS.Error
    }
    finally {
        Pop-Location
    }
}

function Stop-Services {
    Print-Header "Stopping Services"
    try {
        Push-Location $CONFIG_PATH
        docker-compose down
        Write-Host "Services stopped successfully" -ForegroundColor $COLORS.Success
    }
    catch {
        Write-Host "Error stopping services: $_" -ForegroundColor $COLORS.Error
    }
    finally {
        Pop-Location
    }
}

function Show-ContainerStatus {
    Print-Header "Container Status"
    try {
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    }
    catch {
        Write-Host "Error showing container status: $_" -ForegroundColor $COLORS.Error
    }
}

function Show-Logs($containerName) {
    if ([string]::IsNullOrEmpty($containerName)) {
        Print-Header "Showing logs for all containers"
        Push-Location $CONFIG_PATH
        docker-compose logs
        Pop-Location
    }
    else {
        Print-Header "Showing logs for $containerName"
        docker logs $containerName -f --tail 100
    }
}

function Show-Stats {
    Print-Header "Container Stats"
    try {
        docker stats --no-stream
    }
    catch {
        Write-Host "Error showing stats: $_" -ForegroundColor $COLORS.Error
    }
}

function Show-ResourceUsage {
    Print-Header "Resource Usage"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

function Open-ServiceUrls {
    Print-Header "Opening Service URLs"
    foreach ($service in $SERVICES.GetEnumerator()) {
        Write-Host "Opening $($service.Key) at $($service.Value.Url)" -ForegroundColor $COLORS.Info
        Start-Process $service.Value.Url
        Start-Sleep -Seconds 1
    }
}

function Check-ServiceHealth {
    Print-Header "Service Health Check"
    foreach ($service in $SERVICES.GetEnumerator()) {
        if ($service.Value.HealthEndpoint) {
            try {
                $response = Invoke-WebRequest -Uri "$($service.Value.Url)$($service.Value.HealthEndpoint)" -TimeoutSec 5
                $status = if ($response.StatusCode -eq 200) { "Healthy" } else { "Unhealthy" }
                $color = if ($response.StatusCode -eq 200) { $COLORS.Success } else { $COLORS.Error }
                Write-Host "$($service.Key): $status" -ForegroundColor $color
            }
            catch {
                Write-Host "$($service.Key): Unreachable" -ForegroundColor $COLORS.Error
            }
        }
    }
}

function Export-ContainerLogs {
    Print-Header "Export Container Logs"
    $logDir = Join-Path $scriptPath "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    
    foreach ($service in $SERVICES.GetEnumerator()) {
        $container = $service.Value.Container
        if ($container) {
            $logFile = Join-Path $logDir "$($service.Key).log"
            docker logs $container > $logFile 2>&1
            Write-Host "Exported logs for $($service.Key) to $logFile" -ForegroundColor $COLORS.Success
        }
    }
}

function Backup-Configuration {
    Print-Header "Backup Configuration"
    $backupDir = Join-Path $scriptPath "backups"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $backupDir "config_backup_$timestamp"
    
    New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
    Copy-Item $CONFIG_PATH\* $backupPath -Recurse -Force
    Write-Host "Configuration backed up to: $backupPath" -ForegroundColor $COLORS.Success
}

# Main Menu
function Show-Menu {
    Write-Host "`nInsightOps Docker Management" -ForegroundColor $COLORS.Success
    Write-Host "=== Services Management ===" -ForegroundColor $COLORS.Info
    Write-Host "1.  Start all services"
    Write-Host "2.  Stop all services"
    Write-Host "3.  Show container status"
    Write-Host "4.  Show container logs"
    Write-Host "5.  Show container stats"
    Write-Host "6.  Rebuild specific service"
    Write-Host "7.  Clean Docker system"
    Write-Host "8.  Show quick reference"
    Write-Host "=== Monitoring & Access ===" -ForegroundColor $COLORS.Info
    Write-Host "9.  Open all service URLs"
    Write-Host "10. Check service health"
    Write-Host "11. Show resource usage"
    Write-Host "=== Environment Management ===" -ForegroundColor $COLORS.Info
    Write-Host "12. Manage environments"
    Write-Host "13. Check prerequisites"
    Write-Host "14. Run cleanup tasks"
    Write-Host "=== Advanced Options ===" -ForegroundColor $COLORS.Info
    Write-Host "15. View system metrics"
    Write-Host "16. Export container logs"
    Write-Host "17. Backup configuration"
    Write-Host "0.  Exit"
}

# Main Execution
if (-not (Test-Environment)) {
    exit 1
}

while ($true) {
    Show-Menu
    $choice = Read-Host "`nEnter your choice (0-17)"
    
    switch ($choice) {
        0 { exit }
        1 { Start-Services }
        2 { Stop-Services }
        3 { Show-ContainerStatus }
        4 { 
            Write-Host "Available services:" -ForegroundColor $COLORS.Info
            $SERVICES.Keys | ForEach-Object { Write-Host "- $_" }
            $containerName = Read-Host "Enter service name (press Enter for all)"
            Show-Logs $SERVICES[$containerName].Container 
        }
        5 { Show-Stats }
        6 {
            Write-Host "Available services:" -ForegroundColor $COLORS.Info
            $SERVICES.Keys | ForEach-Object { Write-Host "- $_" }
            $serviceName = Read-Host "Enter service name to rebuild"
            Rebuild-Service $serviceName
        }
        7 { Clean-DockerSystem }
        8 { Show-QuickReference }
        9 { Open-ServiceUrls }
        10 { Check-ServiceHealth }
        11 { Show-ResourceUsage }
        12 { Manage-Environment }
        13 { & "$PSScriptRoot\utils\check-prereqs.ps1" -Detailed }
        14 { & "$PSScriptRoot\utils\cleanup.ps1" }
        15 { docker stats }
        16 { Export-ContainerLogs }
        17 { Backup-Configuration }
        default { Write-Host "Invalid option" -ForegroundColor $COLORS.Error }
    }
    
    if ($choice -ne 0) {
        Write-Host "`nPress Enter to continue..."
        Read-Host
    }
}