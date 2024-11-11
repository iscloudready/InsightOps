param (
    [string]$Environment = "Production"
)

# Set proper encoding for emojis
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

#$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Configuration
$namespace = "insightops"
$configRoot = "Configurations"
$SERVICES = @{
    "frontend" = "FrontendService"
    "gateway" = "ApiGateway"
    "orders" = "OrderService"
    "inventory" = "InventoryService"
}

# Helper Functions
function Write-Info {
    param([string]$message)
    Write-Host "`n➡️ $message" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$message)
    Write-Step "`n➡️ $message" -ForegroundColor Cyan
}

function Check-Prerequisites {
    Write-Info "Checking prerequisites..."
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker is not installed or not in PATH"
    }
    if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
        throw "Docker Compose is not installed or not in PATH"
    }
    Write-Host "✅ Prerequisites check passed" -ForegroundColor Green
}

function Initialize-Directories {
    Write-Info "Creating required directories..."
    
    $directories = @(
        "$configRoot/prometheus",
        "$configRoot/loki",
        "$configRoot/tempo",
        "$configRoot/tempo/blocks",
        "$configRoot/tempo/wal",
        "tempo-data/blocks",
        "tempo-data/wal"
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $dir"
        }
    }

    # Set permissions for Tempo directories
    $tempoDirectories = @(
        "tempo-data",
        "tempo-data/blocks",
        "tempo-data/wal"
    )

    foreach ($dir in $tempoDirectories) {
        $acl = Get-Acl $dir
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Everyone",
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.SetAccessRule($accessRule)
        Set-Acl $dir $acl
        Write-Host "Set permissions for: $dir"
    }
}

function Start-Services {
    Write-Info "Starting services..."
    Initialize-Directories
    docker-compose up -d
    Write-Host "Services started successfully" -ForegroundColor Green
}

function Stop-Services {
    Write-Info "Stopping services..."
    docker-compose down
    Write-Host "Services stopped successfully" -ForegroundColor Green
}

function Show-ContainerStatus {
    Write-Info "Container Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

function Show-Logs {
    param($serviceName)
    
    if ([string]::IsNullOrWhiteSpace($serviceName)) {
        docker-compose logs --tail=100
    } else {
        docker-compose logs --tail=100 $serviceName
    }
}

function Rebuild-Service {
    param($serviceName)
    
    if ([string]::IsNullOrWhiteSpace($serviceName)) {
        Write-Warning "Service name is required"
        return
    }
    
    Write-Info "Rebuilding service: $serviceName"
    docker-compose up -d --build $serviceName
}

function Clean-DockerSystem {
    Write-Info "Cleaning Docker system..."
    docker-compose down -v
    docker system prune -f
    Write-Host "Docker system cleaned successfully" -ForegroundColor Green
}

function Show-QuickReference {
    Write-Info "Quick Reference Guide:"
    Write-Host @"
Common Commands:
1. Start all services: docker-compose up -d
2. Stop all services: docker-compose down
3. View logs: docker-compose logs [service]
4. Rebuild service: docker-compose up -d --build [service]
5. Check status: docker ps
6. Clean up: docker system prune
"@
}

function Open-ServiceUrls {
    Write-Info "Opening service URLs..."
    Start-Process "http://localhost:3001" # Grafana
    Start-Process "http://localhost:5010" # Frontend
}

function Check-ServiceHealth {
    Write-Info "Checking service health..."
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Health}}"
}

function Show-ResourceUsage {
    Write-Info "Resource Usage:"
    docker stats --no-stream
}

function Initialize-InsightOpsEnvironment {
    Write-Info "Initializing InsightOps environment..."
    Initialize-Directories
    Test-Configuration
    Start-Services
}

function Export-ContainerLogs {
    Write-Info "Exporting container logs..."
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logDir = "logs_$timestamp"
    New-Item -ItemType Directory -Force -Path $logDir
    
    foreach ($service in $SERVICES.Keys) {
        $logFile = Join-Path $logDir "$service.log"
        docker-compose logs $service > $logFile
    }
    Write-Host "Logs exported to: $logDir" -ForegroundColor Green
}

function Backup-Configuration {
    Write-Info "Backing up configuration..."
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = "backup_$timestamp"
    New-Item -ItemType Directory -Force -Path $backupDir
    
    Copy-Item -Path "$configRoot/*" -Destination $backupDir -Recurse
    Write-Host "Configuration backed up to: $backupDir" -ForegroundColor Green
}

function Test-Configuration {
    Write-Info "Verifying configurations..."

    # Check Tempo configuration
    $tempoConfig = "$configRoot/tempo/tempo.yaml"
    if (Test-Path $tempoConfig) {
        Write-Host "Tempo configuration exists at: $tempoConfig"
        $dockerPath = (Resolve-Path $tempoConfig).Path.Replace('\', '/').Replace('C:', '')
        docker run --rm -v "/${dockerPath}:/etc/tempo/tempo.yaml:ro" grafana/tempo --check-config
    } else {
        Write-Warning "Tempo configuration not found at: $tempoConfig"
    }

    # Check Loki configuration
    $lokiConfig = "$configRoot/loki/loki-config.yaml"
    if (Test-Path $lokiConfig) {
        Write-Host "Loki configuration exists at: $lokiConfig"
    } else {
        Write-Warning "Loki configuration not found at: $lokiConfig"
    }
}

function Test-NetworkConnectivity {
    Write-Info "Testing network connectivity..."
    docker exec ${namespace}_loki wget -q --spider http://tempo:3200/ready
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Loki can reach Tempo" -ForegroundColor Green
    } else {
        Write-Warning "Loki cannot reach Tempo"
    }
}

function Show-Menu {
    Write-Host "`nInsightOps Docker Management Menu" -ForegroundColor Green
    Write-Host "===============================" -ForegroundColor Green
    Write-Host "0. Exit"
    Write-Host "1. Start Services"
    Write-Host "2. Stop Services"
    Write-Host "3. Show Container Status"
    Write-Host "4. Show Service Logs"
    Write-Host "5. Show Container Stats"
    Write-Host "6. Rebuild Service"
    Write-Host "7. Clean Docker System"
    Write-Host "8. Show Quick Reference"
    Write-Host "9. Open Service URLs"
    Write-Host "10. Check Service Health"
    Write-Host "11. Show Resource Usage"
    Write-Host "12. Initialize Environment"
    Write-Host "13. Check Prerequisites"
    Write-Host "14. Clean Docker System"
    Write-Host "15. Show Container Stats"
    Write-Host "16. Export Container Logs"
    Write-Host "17. Backup Configuration"
    Write-Host "18. Test Configuration"
    Write-Host "19. Test Network Connectivity"
    Write-Host "20. Initialize Directories"
    Write-Host "===============================" -ForegroundColor Green
}

# Main Execution
try {
    Write-Info "Starting InsightOps Docker Management..."
    Check-Prerequisites
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
    exit 1
}