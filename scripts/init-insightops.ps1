# InsightOps Initialization Script
param (
    [switch]$Development = $true,
    [switch]$ForceRecreate = $false
)

# Script Variables
$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $PSScriptRoot
$configDir = Join-Path $rootDir "Configurations"
$logsDir = Join-Path $rootDir "logs"
$grafanaDir = Join-Path $configDir "grafana"

# Color Output Functions
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success($message) { Write-ColorOutput Green $message }
function Write-Info($message) { Write-ColorOutput Cyan $message }
function Write-Warning($message) { Write-ColorOutput Yellow $message }
function Write-Error($message) { Write-ColorOutput Red $message }

# Check Prerequisites
function Check-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check Docker
    try {
        docker info > $null 2>&1
        Write-Success "✓ Docker is running"
    }
    catch {
        Write-Error "✗ Docker is not running or not installed"
        exit 1
    }

    # Check .NET SDK
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        Write-Success "✓ .NET SDK is installed"
    }
    else {
        Write-Error "✗ .NET SDK is not installed"
        exit 1
    }
}

# Create Directory Structure
function Create-DirectoryStructure {
    Write-Info "Creating directory structure..."
    
    $directories = @(
        $configDir,
        (Join-Path $grafanaDir "provisioning\dashboards"),
        (Join-Path $grafanaDir "provisioning\datasources"),
        $logsDir
    )

    foreach ($dir in $directories) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force
            Write-Success "Created directory: $dir"
        }
    }
}

# Create Configuration Files
function Create-ConfigurationFiles {
    Write-Info "Creating configuration files..."
    
    # Create Grafana datasources configuration
    $datasourcesConfig = @"
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://insightops_prometheus:9090
    isDefault: true
  - name: Loki
    type: loki
    access: proxy
    url: http://insightops_loki:3100
  - name: Tempo
    type: tempo
    access: proxy
    url: http://insightops_tempo:4317
"@
    
    Set-Content -Path (Join-Path $grafanaDir "provisioning\datasources\datasources.yaml") -Value $datasourcesConfig
    Write-Success "Created Grafana datasources configuration"

    # Copy dashboard files (ensure these exist in your source)
    Copy-Item -Path "$PSScriptRoot\dashboards\*.json" -Destination (Join-Path $grafanaDir "provisioning\dashboards\") -Force
    Write-Success "Copied dashboard configurations"
}

# Start Services
function Start-Services {
    Write-Info "Starting services..."
    
    Set-Location $configDir
    try {
        docker-compose down -v
        docker-compose up -d --build
        Write-Success "Services started successfully"
    }
    catch {
        Write-Error "Failed to start services: $_"
        exit 1
    }
}

# Open Service URLs
function Open-ServiceUrls {
    Write-Info "Opening service URLs..."
    
    $urls = @{
        "Frontend" = "http://localhost:5010"
        "API Gateway" = "http://localhost:5011"
        "Order Service" = "http://localhost:5012"
        "Inventory Service" = "http://localhost:5013"
        "Grafana" = "http://localhost:3001"
        "Prometheus" = "http://localhost:9091"
    }

    foreach ($service in $urls.Keys) {
        Write-Info "Opening $service..."
        Start-Process $urls[$service]
        Start-Sleep -Seconds 1
    }
}

# Monitor Services
function Monitor-Services {
    Write-Info "Monitoring services..."
    
    $services = @(
        "insightops_frontend",
        "insightops_gateway",
        "insightops_orders",
        "insightops_inventory",
        "insightops_db"
    )

    foreach ($service in $services) {
        Write-Info "Checking logs for $service..."
        docker logs $service --tail 50
    }
}

# Main Execution
try {
    Write-Info "Starting InsightOps initialization..."
    Check-Prerequisites
    Create-DirectoryStructure
    Create-ConfigurationFiles
    Start-Services
    Open-ServiceUrls
    Monitor-Services
    Write-Success "InsightOps initialization completed successfully!"
    Write-Info "Grafana: http://localhost:3001 (admin/InsightOps2024!)"
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}