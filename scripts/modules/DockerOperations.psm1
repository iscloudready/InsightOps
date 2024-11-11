# DockerOperations.psm1
# Purpose: Docker operations management
# Add this at the beginning of DockerOperations.psm1
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

# Define common logging functions to match Logging module
function Write-Information { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host $Message -ForegroundColor Red }

function Start-DockerServices {
    [CmdletBinding()]
    param()
    
    try {
        $composeArgs = "up", "-d"
        $composePath = Join-Path $script:CONFIG_ROOT "docker-compose.yml"
        docker-compose -f $composePath $composeArgs
        Write-Success "Docker services started successfully"
    }
    catch {
        Write-Error "Failed to start Docker services: $_"
    }
}

function _Start-DockerServices {
    [CmdletBinding()]
    param (
        [string[]]$Services,
        [switch]$Build
    )
    
    try {
        Write-Information "Starting Docker services..."
        $composeArgs = @('up', '-d')
        
        if ($Build) {
            $composeArgs += '--build'
        }
        
        if ($Services) {
            $composeArgs += $Services
        }
        
        docker-compose $composeArgs
        Write-Success "Docker services started successfully"
        return $true
    }
    catch {
        Write-Error "Failed to start Docker services: $_"
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
        $composePath = Join-Path $script:CONFIG_ROOT "docker-compose.yml"
        if ($RemoveVolumes) {
            docker-compose -f $composePath down -v --remove-orphans
        }
        else {
            docker-compose -f $composePath down --remove-orphans
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
        docker-compose restart $ServiceName
        Write-Success "Service $ServiceName restarted successfully"
        return $true
    }
    catch {
        Write-Error "Failed to restart service $ServiceName : $_"
        return $false
    }
}

function Export-DockerLogs {
    [CmdletBinding()]
    param (
        [string]$ServiceName,
        [string]$OutputPath = "logs"
    )
    
    try {
        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        if ($ServiceName) {
            $logFile = Join-Path $OutputPath "${ServiceName}_${timestamp}.log"
            Write-Information "Exporting logs for $ServiceName to $logFile"
            docker-compose logs $ServiceName > $logFile
        }
        else {
            $logFile = Join-Path $OutputPath "all_services_${timestamp}.log"
            Write-Information "Exporting logs for all services to $logFile"
            docker-compose logs > $logFile
        }

        Write-Success "Logs exported successfully"
        return $true
    }
    catch {
        Write-Error "Failed to export Docker logs: $_"
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
    'Wait-ServiceHealth',
    'Clean-DockerEnvironment',
	'Test-ContainerHealth',
	'Initialize-DockerEnvironment'
)