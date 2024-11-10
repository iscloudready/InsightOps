# Enhanced Docker Management Script for InsightOps

# InsightOps Docker Management Script
using namespace System.Management.Automation
using namespace System.Collections.Generic

# Script Configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import dependent modules
$scriptPath = $PSScriptRoot
$utilsPath = Join-Path $scriptPath "utils"

# Import utility functions
. (Join-Path $utilsPath "check-prereqs.ps1")
. (Join-Path $utilsPath "cleanup.ps1")
. (Join-Path $utilsPath "setup-environment.ps1")

# Constants
$CONFIG_PATH = Join-Path $scriptPath "..\Configurations"
$GRAFANA_PATH = Join-Path $CONFIG_PATH "grafana"
$DOCKER_COMPOSE_FILE = Join-Path $CONFIG_PATH "docker-compose.yml"

# Service configuration
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
}

# Color configuration
$COLORS = @{
    Success = [System.ConsoleColor]::Green
    Error = [System.ConsoleColor]::Red
    Warning = [System.ConsoleColor]::Yellow
    Info = [System.ConsoleColor]::Cyan
    Header = [System.ConsoleColor]::Magenta
}

# Function to validate environment
function Test-Environment {
    $required = @(
        $DOCKER_COMPOSE_FILE,
        (Join-Path $GRAFANA_PATH "provisioning\datasources\datasources.yml"),
        (Join-Path $CONFIG_PATH "prometheus.yml")
    )
    
    $missing = $required | Where-Object { -not (Test-Path $_) }
    if ($missing) {
        Write-Error "Missing required files:`n$($missing -join "`n")"
        return $false
    }
    return $true
}

# Initialize script
if (-not (Test-Environment)) {
    exit 1
}

# Additional script imports
. "$PSScriptRoot\utils\check-prereqs.ps1"

# Colors and Variables (existing)
$Red = [System.ConsoleColor]::Red
$Green = [System.ConsoleColor]::Green
$Yellow = [System.ConsoleColor]::Yellow
$Cyan = [System.ConsoleColor]::Cyan

# Service URLs
$serviceUrls = @{
    "Frontend" = "http://localhost:5010"
    "API Gateway" = "http://localhost:5011"
    "Order Service" = "http://localhost:5012"
    "Inventory Service" = "http://localhost:5013"
    "Grafana" = "http://localhost:3001"
    "Prometheus" = "http://localhost:9091"
    "Loki" = "http://localhost:3101"
}

# [Keep existing functions...]

# New function to open service URLs
function Open-ServiceUrls {
    Print-Header "Opening Service URLs"
    
    foreach ($service in $serviceUrls.GetEnumerator()) {
        Write-Host "Opening $($service.Key) at $($service.Value)" -ForegroundColor Cyan
        Start-Process $service.Value
        Start-Sleep -Seconds 1
    }
}

# New function to check service health
function Check-ServiceHealth {
    Print-Header "Service Health Check"
    
    foreach ($service in $serviceUrls.GetEnumerator()) {
        try {
            $response = Invoke-WebRequest -Uri "$($service.Value)/health" -TimeoutSec 5
            $status = if ($response.StatusCode -eq 200) { "Healthy" } else { "Unhealthy" }
            $color = if ($response.StatusCode -eq 200) { $Green } else { $Red }
            Write-Host "$($service.Key): $status" -ForegroundColor $color
        }
        catch {
            Write-Host "$($service.Key): Unreachable" -ForegroundColor $Red
        }
    }
}

# New function to monitor resource usage
function Show-ResourceUsage {
    Print-Header "Resource Usage"
    
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

# New function to manage environments
function Manage-Environment {
    Print-Header "Environment Management"
    Write-Host "1. Development"
    Write-Host "2. Staging"
    Write-Host "3. Production"
    Write-Host "4. Back to main menu"
    
    $envChoice = Read-Host "Select environment"
    switch ($envChoice) {
        "1" { & "$PSScriptRoot\utils\setup-environment.ps1" -Environment Development }
        "2" { & "$PSScriptRoot\utils\setup-environment.ps1" -Environment Staging }
        "3" { & "$PSScriptRoot\utils\setup-environment.ps1" -Environment Production }
        "4" { return }
        default { Write-Host "Invalid choice" -ForegroundColor Red }
    }
}

# Enhanced Show-Menu function
function Show-Menu {
    Write-Host "`nInsightOps Docker Management" -ForegroundColor Green
    Write-Host "=== Services Management ===" -ForegroundColor Cyan
    Write-Host "1.  Start all services"
    Write-Host "2.  Stop all services"
    Write-Host "3.  Show container status"
    Write-Host "4.  Show container logs"
    Write-Host "5.  Show container stats"
    Write-Host "6.  Rebuild specific service"
    Write-Host "7.  Clean Docker system"
    Write-Host "8.  Show quick reference"
    Write-Host "=== Monitoring & Access ===" -ForegroundColor Cyan
    Write-Host "9.  Open all service URLs"
    Write-Host "10. Check service health"
    Write-Host "11. Show resource usage"
    Write-Host "=== Environment Management ===" -ForegroundColor Cyan
    Write-Host "12. Manage environments"
    Write-Host "13. Check prerequisites"
    Write-Host "14. Run cleanup tasks"
    Write-Host "=== Advanced Options ===" -ForegroundColor Cyan
    Write-Host "15. View system metrics"
    Write-Host "16. Export container logs"
    Write-Host "17. Backup configuration"
    Write-Host "0.  Exit"
}

# New function to export logs
function Export-ContainerLogs {
    Print-Header "Export Container Logs"
    $logDir = Join-Path $PSScriptRoot "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    
    foreach ($container in (docker ps --format "{{.Names}}")) {
        $logFile = Join-Path $logDir "$container.log"
        docker logs $container > $logFile
        Write-Host "Exported logs for $container to $logFile" -ForegroundColor Green
    }
}

# New function to backup configuration
function Backup-Configuration {
    Print-Header "Backup Configuration"
    $backupDir = Join-Path $PSScriptRoot "backups"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $backupDir "config_backup_$timestamp"
    
    New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "Configurations\*") $backupPath -Recurse -Force
    Write-Host "Configuration backed up to: $backupPath" -ForegroundColor Green
}

# Print header function
function Print-Header($title) {
    Write-Host "`n=== $title ===" -ForegroundColor $COLORS.Header
}

# Fixed Start-Services function
function Start-Services {
    Print-Header "Starting Services"
    try {
        Set-Location $CONFIG_PATH
        docker-compose up -d --build
        Write-Host "Services started successfully" -ForegroundColor $COLORS.Success
        Set-Location $scriptPath
    }
    catch {
        Write-Host "Error starting services: $_" -ForegroundColor $COLORS.Error
    }
}

# Fixed Stop-Services function
function Stop-Services {
    Print-Header "Stopping Services"
    try {
        Set-Location $CONFIG_PATH
        docker-compose down
        Write-Host "Services stopped successfully" -ForegroundColor $COLORS.Success
        Set-Location $scriptPath
    }
    catch {
        Write-Host "Error stopping services: $_" -ForegroundColor $COLORS.Error
    }
}

# Fixed Show-ContainerStatus function (formerly Show-Status)
function Show-ContainerStatus {
    Print-Header "Container Status"
    try {
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    }
    catch {
        Write-Host "Error showing container status: $_" -ForegroundColor $COLORS.Error
    }
}

# Fixed Show-Logs function
function Show-Logs($containerName) {
    if ([string]::IsNullOrEmpty($containerName)) {
        Print-Header "Showing logs for all containers"
        Set-Location $CONFIG_PATH
        docker-compose logs
        Set-Location $scriptPath
    }
    else {
        Print-Header "Showing logs for $containerName"
        docker logs $containerName -f --tail 100
    }
}

# Fixed Show-Stats function
function Show-Stats {
    Print-Header "Container Stats"
    try {
        docker stats --no-stream
    }
    catch {
        Write-Host "Error showing stats: $_" -ForegroundColor $COLORS.Error
    }
}

# Fixed Rebuild-Service function
function Rebuild-Service($serviceName) {
    if ([string]::IsNullOrEmpty($serviceName)) {
        Write-Host "Error: Please specify a service name" -ForegroundColor $COLORS.Error
        return
    }
    Print-Header "Rebuilding service: $serviceName"
    try {
        Set-Location $CONFIG_PATH
        docker-compose up -d --no-deps --build $serviceName
        Set-Location $scriptPath
        Write-Host "Service rebuilt successfully" -ForegroundColor $COLORS.Success
    }
    catch {
        Write-Host "Error rebuilding service: $_" -ForegroundColor $COLORS.Error
    }
}

# Fixed Show-QuickReference function
function Show-QuickReference {
    Print-Header "Quick Reference Guide"
    Write-Host @"
Available Services:
------------------
Frontend          - $($SERVICES.Frontend.Url)
API Gateway       - $($SERVICES.ApiGateway.Url)
Order Service     - $($SERVICES.OrderService.Url)
Inventory Service - $($SERVICES.InventoryService.Url)
Grafana          - $($SERVICES.Grafana.Url) (${$SERVICES.Grafana.Credentials.Username}/${$SERVICES.Grafana.Credentials.Password})
Prometheus       - $($SERVICES.Prometheus.Url)

Database Connection:
------------------
Host: localhost
Port: 5433
Database: insightops_db
Username: insightops_user
Password: insightops_pwd

Common Commands:
--------------
docker ps                    # List running containers
docker logs [service]        # View service logs
docker-compose up --build -d # Start all services
docker-compose down         # Stop all services
"@ -ForegroundColor $COLORS.Info
}

# Update the main switch block
switch ($choice) {
    0 { exit }
    1 { Start-Services }
    2 { Stop-Services }
    3 { Show-ContainerStatus }  # Fixed function name
    4 { 
        Write-Host "Available services:" -ForegroundColor $COLORS.Info
        $SERVICES.Keys | ForEach-Object { Write-Host "- $_" }
        $containerName = Read-Host "Enter container name (press Enter for all)"
        Show-Logs $containerName
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

# Enhanced main loop
while ($true) {
    Show-Menu
    $choice = Read-Host "`nEnter your choice (0-17)"
    
    switch ($choice) {
        # Existing options
        0 { exit }
        { 1..8 -contains $_ } {
            # Existing switch cases...
            switch ($_) {
                1 { Start-Services }
                2 { Stop-Services }
                3 { Show-Status }
                4 { 
                    Write-Host "Available services: frontend, api_gateway, order_service, inventory_service, postgres, prometheus, loki, tempo"
                    $containerName = Read-Host "Enter container name (press Enter for all)"
                    Show-Logs $containerName
                }
                5 { Show-Stats }
                6 {
                    Write-Host "Available services: frontend, api_gateway, order_service, inventory_service"
                    $serviceName = Read-Host "Enter service name to rebuild"
                    Rebuild-Service $serviceName
                }
                7 { Clean-DockerSystem }
                8 { Show-QuickReference }
            }
        }
        # New options
        9 { Open-ServiceUrls }
        10 { Check-ServiceHealth }
        11 { Show-ResourceUsage }
        12 { Manage-Environment }
        13 { & "$PSScriptRoot\utils\check-prereqs.ps1" -Detailed }
        14 { & "$PSScriptRoot\utils\cleanup.ps1" }
        15 { docker stats }
        16 { Export-ContainerLogs }
        17 { Backup-Configuration }
        default { Write-Host "Invalid option" -ForegroundColor Red }
    }
    
    if ($choice -ne 0) {
        Write-Host "`nPress Enter to continue..."
        Read-Host
    }
}