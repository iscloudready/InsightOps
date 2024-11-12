# DockerOperations.psm1
# Purpose: Docker operations management
$script:CONFIG_ROOT = Join-Path (Split-Path -Parent $PSScriptRoot) "Configurations"
$script:DOCKER_COMPOSE_PATH = Join-Path $script:CONFIG_ROOT "docker-compose.yml"

function Initialize-DockerEnvironment {
    [CmdletBinding()]
    param()
    
    try {
        # Check if docker-compose.yml exists
        if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
            Write-Warning "Docker Compose configuration not found. Creating default configuration..."
            if (-not (Initialize-DefaultConfigurations)) {
                throw "Failed to create default configurations"
            }
        }

        # Verify Docker is running
        $dockerPsOutput = docker ps -q
        if (-not $dockerPsOutput) {
            throw "Docker service is not running"
        }

        return $true
    }
    catch {
        Write-Error "Failed to initialize Docker environment: $_"
        return $false
    }
}

# Modify existing functions to use DOCKER_COMPOSE_FILE
function Show-DockerStatus {
    [CmdletBinding()]
    param()
    
    try {
        if (-not (Initialize-DockerEnvironment)) {
            return $false
        }

        Write-Information "Current Docker container status:"
        docker-compose -f $script:DOCKER_COMPOSE_FILE ps

        Write-Information "`nResource usage:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
        return $true
    }
    catch {
        Write-Error "Failed to show Docker status: $_"
        return $false
    }
}

# Modify the docker-compose commands to use the config file path
function Show-DockerStatus {
    [CmdletBinding()]
    param()
    
    try {
        if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
            Write-Error "Docker Compose configuration not found at: $script:DOCKER_COMPOSE_PATH"
            return $false
        }

        Write-Information "Current Docker container status:"
        docker-compose -f $script:DOCKER_COMPOSE_PATH ps

        Write-Information "`nResource usage:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
        return $true
    }
    catch {
        Write-Error "Failed to show Docker status: $_"
        return $false
    }
}

function Test-ServiceHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServiceName
    )
    
    try {
        Write-Host "`nChecking service health..." -ForegroundColor Cyan
        
        # Get all containers status
        $runningContainers = docker ps --format "{{.Names}}" 2>$null
        $allContainers = docker ps -a --format "{{.Names}}|{{.Status}}" 2>$null

        $services = @{
            "insightops_db" = "Database"
            "insightops_frontend" = "Frontend"
            "insightops_gateway" = "API Gateway"
            "insightops_orders" = "Order Service"
            "insightops_inventory" = "Inventory Service"
            "insightops_tempo" = "Tempo"
            "insightops_grafana" = "Grafana"
            "insightops_loki" = "Loki"
            "insightops_prometheus" = "Prometheus"
        }

        foreach ($container in $services.Keys) {
            $serviceName = $services[$container]
            $containerStatus = $allContainers | Where-Object { $_ -like "$container|*" }
            
            if ($containerStatus) {
                $status = $containerStatus.Split('|')[1]
                if ($status -like "Up*") {
                    $health = docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' $container 2>$null
                    Write-Host "  • $serviceName : $health" -ForegroundColor $(
                        switch ($health) {
                            "healthy" { "Green" }
                            "unhealthy" { "Red" }
                            "running" { "Green" }
                            default { "Yellow" }
                        }
                    )
                }
                elseif ($status -like "Exited*") {
                    $exitInfo = docker inspect --format='{{.State.ExitCode}}' $container 2>$null
                    Write-Host "  • $serviceName : Exited (code: $exitInfo)" -ForegroundColor Red
                }
                else {
                    Write-Host "  • $serviceName : $status" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "  • $serviceName : not found" -ForegroundColor Red
            }
        }

        Write-Host "`nTroubleshooting Tips:" -ForegroundColor Yellow
        Write-Host "  1. View service logs: Option 15" -ForegroundColor Yellow
        Write-Host "  2. Check container details: Option 11" -ForegroundColor Yellow
        Write-Host "  3. Restart services if needed: Option 8" -ForegroundColor Yellow
        
        return $true
    }
    catch {
        Write-Host "Health check failed: $_" -ForegroundColor Red
        return $false
    }
}

# Define common logging functions to match Logging module
function Write-Information { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host $Message -ForegroundColor Red }

function Start-DockerServices {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nStarting Docker services..." -ForegroundColor Cyan

        # Use DOCKER_COMPOSE_PATH instead of CONFIG_PATH
        if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
            throw "Docker Compose file not found at: $script:DOCKER_COMPOSE_PATH"
        }

        Write-Host "Using compose file: $script:DOCKER_COMPOSE_PATH" -ForegroundColor Yellow

        # Change to the configuration directory
        $configDir = Split-Path $script:DOCKER_COMPOSE_PATH -Parent
        $currentLocation = Get-Location
        Set-Location $configDir

        try {
            # Start the services
            Write-Host "Starting containers..." -ForegroundColor Yellow
            docker-compose -f $script:DOCKER_COMPOSE_PATH up -d

            # Show status
            Write-Host "`nContainer Status:" -ForegroundColor Cyan
            docker-compose -f $script:DOCKER_COMPOSE_PATH ps

            Write-Host "`nServices started successfully" -ForegroundColor Green
            Write-Host "Use Option 10 to check service health" -ForegroundColor Yellow
            Write-Host "Use Option 20 to open service URLs" -ForegroundColor Yellow
        }
        finally {
            # Restore original location
            Set-Location $currentLocation
        }
        
        return $true
    }
    catch {
        Write-Host "Failed to start services: $_" -ForegroundColor Red
        Write-Host "Location: $(Get-Location)" -ForegroundColor Yellow  # Debug info
        return $false
    }
}

# Also update Stop-DockerServices to use the correct path
function Stop-DockerServices {
    [CmdletBinding()]
    param (
        [switch]$RemoveVolumes
    )
    
    try {
        Write-Information "Stopping Docker services..."
        
        if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
            throw "Docker Compose configuration not found at: $script:DOCKER_COMPOSE_PATH"
        }

        $configDir = Split-Path $script:DOCKER_COMPOSE_PATH -Parent
        $currentLocation = Get-Location
        Set-Location $configDir

        try {
            if ($RemoveVolumes) {
                docker-compose -f $script:DOCKER_COMPOSE_PATH down -v --remove-orphans
            }
            else {
                docker-compose -f $script:DOCKER_COMPOSE_PATH down --remove-orphans
            }
            Write-Success "Docker services stopped successfully"
        }
        finally {
            Set-Location $currentLocation
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to stop Docker services: $_"
        return $false
    }
}

function Restart-DockerService {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )
    
    try {
        Write-Information "Restarting Docker service: $ServiceName"
        docker-compose restart $ServiceName
        Write-Success "Service $ServiceName restarted successfully"
        return $true
    }
    catch {
        Write-Error "Failed to restart service $ServiceName : $_"
        return $false
    }
}

function Get-ContainerLogs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )
    
    try {
        $containerExists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
        if (-not $containerExists) {
            Write-Host "Container $ContainerName not found" -ForegroundColor Red
            return $false
        }

        Write-Host "`nLogs for container $ContainerName" -ForegroundColor Cyan
        Write-Host "-----------------------------------------" -ForegroundColor Gray
        docker logs $ContainerName 2>&1
        Write-Host "-----------------------------------------" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Host "Failed to get logs: $_" -ForegroundColor Red
        return $false
    }
}

function Export-DockerLogs {
    [CmdletBinding()]
    param (
        [string]$ServiceName
    )
    
    try {
        if ($ServiceName) {
            Get-ContainerLogs -ContainerName $ServiceName
        }
        else {
            Write-Host "`nGetting logs for all services..." -ForegroundColor Cyan
            
            $containers = docker ps -a --format "{{.Names}}"
            foreach ($container in $containers) {
                Get-ContainerLogs -ContainerName $container
            }
        }
        return $true
    }
    catch {
        Write-Host "Failed to get logs: $_" -ForegroundColor Red
        return $false
    }
}

function Wait-ServiceHealth {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [int]$TimeoutSeconds = 30
    )
    
    try {
        $startTime = Get-Date
        $timeout = $startTime.AddSeconds($TimeoutSeconds)
        
        Write-Information "Waiting for $ServiceName to be healthy..."
        while ((Get-Date) -lt $timeout) {
            $status = docker inspect --format='{{.State.Health.Status}}' $ServiceName 2>$null
            if ($status -eq 'healthy') {
                Write-Success "$ServiceName is healthy"
                return $true
            }
            Start-Sleep -Seconds 2
        }
        
        Write-Warning "$ServiceName did not become healthy within $TimeoutSeconds seconds"
        return $false
    }
    catch {
        Write-Error "Error checking service health: $_"
        return $false
    }
}

function Clean-DockerEnvironment {
    [CmdletBinding()]
    param (
        [switch]$RemoveVolumes,
        [switch]$RemoveImages,
        [switch]$Force
    )
    
    try {
        Write-Information "Cleaning Docker environment..."
        
        # Stop all containers first
        Stop-DockerServices -RemoveVolumes:$RemoveVolumes
        
        if ($RemoveImages) {
            Write-Information "Removing all Docker images..."
            if ($Force) {
                docker system prune -af
            }
            else {
                docker system prune -a
            }
        }
        else {
            if ($Force) {
                docker system prune -f
            }
            else {
                docker system prune
            }
        }
        
        Write-Success "Docker environment cleaned successfully"
        return $true
    }
    catch {
        Write-Error "Failed to clean Docker environment: $_"
        return $false
    }
}

function Test-ContainerHealth {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ContainerName
    )
    
    try {
        Write-Information "Checking container health..."
        
        $containers = if ($ContainerName) {
            docker ps --filter "name=$ContainerName" --format "{{.Names}}"
        }
        else {
            docker ps --format "{{.Names}}"
        }

        $results = @()
        foreach ($container in $containers) {
            $health = docker inspect --format='{{.State.Health.Status}}' $container 2>$null
            $status = if ($health) { $health } else { "running" }
            
            $results += [PSCustomObject]@{
                Container = $container
                Status = $status
                Uptime = (docker ps --format "{{.Status}}" --filter "name=$container")
            }
        }

        if ($results.Count -gt 0) {
            Write-Host "`nContainer Health Status:" -ForegroundColor Cyan
            $results | Format-Table -AutoSize
            return $true
        }
        else {
            Write-Warning "No containers found"
            return $false
        }
    }
    catch {
        Write-Error "Container health check failed: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Show-DockerStatus',
    'Start-DockerServices',
    'Stop-DockerServices',
    'Restart-DockerService',
    'Export-DockerLogs',
    'Get-ContainerLogs',
    'Wait-ServiceHealth',
    'Clean-DockerEnvironment',
	'Test-ContainerHealth',
	'Initialize-DockerEnvironment',
    'Test-ContainerHealth',
    'Test-ServiceHealth' 
)