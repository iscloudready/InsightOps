# DockerOperations.psm1
# Purpose: Docker operations management
#$script:CONFIG_ROOT = Join-Path (Split-Path -Parent $PSScriptRoot) "Configurations"
#$script:DOCKER_COMPOSE_PATH = Join-Path $script:CONFIG_ROOT "docker-compose.yml"

$script:CONFIG_PATH = (Get-Variable -Name CONFIG_PATH -Scope Global).Value
$script:DOCKER_COMPOSE_PATH = Join-Path $script:CONFIG_PATH "docker-compose.yml"
#$env:CONFIG_PATH = $script:CONFIG_PATH  # Setting the environment variable for Docker Compose

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

function Show-DockerStatus {
    [CmdletBinding()]
    param()
    
    try {
        if (-not (Initialize-DockerEnvironment)) {
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
    param (
        [Parameter(Mandatory = $false)]
        [string]$ServiceName,
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectPrefix = "insightops"
    )
    
    try {
        Write-Host "`nChecking service health..." -ForegroundColor Cyan
        
        $services = @{
            "db" = @{
                Name = "Database"
                HealthCheck = "pg_isready"
            }
            "grafana" = @{
                Name = "Grafana"
                Port = 3001
            }
            "prometheus" = @{
                Name = "Prometheus"
                Port = 9091
            }
            "loki" = @{
                Name = "Loki"
                Port = 3101
            }
            "tempo" = @{
                Name = "Tempo"
                Port = 4317
            }
        }

        $results = @()
        foreach ($svc in $services.GetEnumerator()) {
            $containerName = "${ProjectPrefix}_$($svc.Key)"
            
            # Skip if specific service requested and this isn't it
            if ($ServiceName -and $containerName -notlike "*$ServiceName*") {
                continue
            }

            $status = docker ps -a --filter "name=$containerName" --format "{{.Status}}"
            $health = docker inspect --format='{{.State.Health.Status}}' $containerName 2>$null
            $ipAddress = docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $containerName 2>$null
            $ports = docker port $containerName 2>$null

            $results += [PSCustomObject]@{
                Service = $svc.Value.Name
                Container = $containerName
                Status = if ($status -like "Up*") { "Running" } else { "Stopped" }
                Health = if ($health) { $health } else { "N/A" }
                IP = $ipAddress
                Ports = ($ports -join ", ")
                Uptime = $status
            }
        }

        if ($results.Count -gt 0) {
            Write-Host "`nService Health Status:" -ForegroundColor Cyan
            Write-Host "===========================================" -ForegroundColor Cyan
            
            foreach ($result in $results) {
                $statusColor = switch ($result.Status) {
                    "Running" { "Green" }
                    "Stopped" { "Red" }
                    default { "Yellow" }
                }
                
                $healthColor = switch ($result.Health) {
                    "healthy" { "Green" }
                    "unhealthy" { "Red" }
                    "starting" { "Yellow" }
                    default { "Gray" }
                }

                Write-Host "`nService: " -NoNewline -ForegroundColor Cyan
                Write-Host $result.Service -ForegroundColor White
                Write-Host "Container: " -NoNewline -ForegroundColor Cyan
                Write-Host $result.Container -ForegroundColor White
                Write-Host "Status: " -NoNewline -ForegroundColor Cyan
                Write-Host $result.Status -ForegroundColor $statusColor
                Write-Host "Health: " -NoNewline -ForegroundColor Cyan
                Write-Host $result.Health -ForegroundColor $healthColor
                Write-Host "IP Address: " -NoNewline -ForegroundColor Cyan
                Write-Host $result.IP -ForegroundColor White
                Write-Host "Ports: " -NoNewline -ForegroundColor Cyan
                Write-Host $result.Ports -ForegroundColor White
                Write-Host "Uptime: " -NoNewline -ForegroundColor Cyan
                Write-Host $result.Uptime -ForegroundColor White
                Write-Host "-------------------------------------------" -ForegroundColor Gray
            }

            return $true
        } else {
            Write-Host "`nNo services found matching pattern: $ServiceName" -ForegroundColor Yellow
            return $false
        }

        try {
            Write-Host "`nChecking service health..." -ForegroundColor Cyan
        
            # Special handling for Tempo volume check
            if ($ServiceName -eq "tempo" -or -not $ServiceName) {
                $tempoVolume = docker volume ls --format "{{.Name}}" | Where-Object { $_ -like "*tempo*" }
                if ($tempoVolume) {
                    Write-Host "Tempo volume exists: $tempoVolume" -ForegroundColor Green
                } else {
                    Write-Host "Tempo volume not found" -ForegroundColor Yellow
                }
            }

            # Rest of your existing health check code...
        }
        catch {
            Write-Host "Health check failed: $_" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "`nError checking service health: $_" -ForegroundColor Red
        return $false
    }
}

function Start-DockerServices { 
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nStarting Docker services..." -ForegroundColor Cyan

        # Set the CONFIG_PATH environment variable for Docker Compose
        $env:CONFIG_PATH = $script:CONFIG_PATH  
        Write-Host "Config Path: $script:CONFIG_PATH"

        if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
            throw "Docker Compose file not found at: $script:DOCKER_COMPOSE_PATH"
        }

        docker-compose -f $script:DOCKER_COMPOSE_PATH up -d

        Write-Host "`nContainer Status:" -ForegroundColor Cyan
        docker-compose -f $script:DOCKER_COMPOSE_PATH ps

        Write-Host "`nServices started successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to start services: $_"
        return $false
    }
}

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

        Write-Information "Docker Compose configuration found. Proceeding to stop services..."

        if ($RemoveVolumes) {
            docker-compose -f $script:DOCKER_COMPOSE_PATH down -v --remove-orphans
            Write-Information "Stopped services and removed volumes."
        }
        else {
            docker-compose -f $script:DOCKER_COMPOSE_PATH down --remove-orphans
            Write-Information "Stopped services without removing volumes."
        }

        Write-Success "Docker services stopped successfully"
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
        docker-compose -f $script:DOCKER_COMPOSE_PATH restart $ServiceName
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
        Write-Host "`nLogs for container $ContainerName" -ForegroundColor Cyan
        docker logs $ContainerName 2>&1
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

function Clean-DockerEnvironment {
    [CmdletBinding()]
    param (
        [switch]$RemoveVolumes,
        [switch]$RemoveImages,
        [switch]$Force
    )
    
    try {
        Write-Information "Cleaning Docker environment..."
        
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
    'Test-ServiceHealth'
)
