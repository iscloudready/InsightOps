# DockerCleanup.psm1

# Logging function for standardized timestamped logs
function Write-CleanupLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp : $Message" -ForegroundColor $Color
}

# Function to check if Docker is accessible
function Test-DockerRunning {
    try {
        $result = docker ps 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-CleanupLog "Docker is running and accessible" -Color Green
            return $true
        }
        Write-CleanupLog "Docker is not responding properly" -Color Red
        return $false
    }
    catch {
        Write-CleanupLog "Docker command not found or not accessible: $_" -Color Red
        return $false
    }
}

# Function to stop and remove project containers
function Stop-ProjectContainers {
    param (
        [string]$ProjectPattern
    )

    if (-not (Test-DockerRunning)) {
        Write-CleanupLog "Skipping container cleanup due to Docker inaccessibility." -Color Red
        return $false
    }

    try {
        $containers = docker ps -a --format "{{.Names}}" | Where-Object { $_ -like "*$ProjectPattern*" }

        if ($containers) {
            foreach ($container in $containers) {
                Write-CleanupLog "Stopping container: $container" -Color Yellow
                docker stop $container 2>&1 | Out-Null

                Write-CleanupLog "Removing container: $container" -Color Yellow
                docker rm $container 2>&1 | Out-Null
            }
            Write-CleanupLog "Containers cleaned up" -Color Green
        } else {
            Write-CleanupLog "No containers found matching pattern: *$ProjectPattern*" -Color Yellow
        }
        return $true
    }
    catch {
        Write-CleanupLog "Error processing containers: $_" -Color Red
        return $false
    }
}

# Function to remove project volumes
function Remove-ProjectVolumes {
    param (
        [string]$ProjectPattern
    )

    if (-not (Test-DockerRunning)) {
        Write-CleanupLog "Skipping volume cleanup due to Docker inaccessibility." -Color Red
        return $false
    }

    try {
        $volumes = docker volume ls --format "{{.Name}}" | Where-Object { $_ -like "*$ProjectPattern*" }

        if ($volumes) {
            foreach ($volume in $volumes) {
                Write-CleanupLog "Removing volume: $volume" -Color Yellow
                docker volume rm -f $volume 2>&1 | Out-Null
            }
            Write-CleanupLog "Volumes cleaned up" -Color Green
        } else {
            Write-CleanupLog "No volumes found matching pattern: *$ProjectPattern*" -Color Yellow
        }
        return $true
    }
    catch {
        Write-CleanupLog "Error removing volumes: $_" -Color Red
        return $false
    }
}

# Function to remove project networks
function Remove-ProjectNetworks {
    param (
        [string]$ProjectPattern
    )

    if (-not (Test-DockerRunning)) {
        Write-CleanupLog "Skipping network cleanup due to Docker inaccessibility." -Color Red
        return $false
    }

    try {
        $networks = docker network ls --format "{{.Name}}" | Where-Object { $_ -like "*$ProjectPattern*" }

        if ($networks) {
            foreach ($network in $networks) {
                Write-CleanupLog "Removing network: $network" -Color Yellow
                docker network rm $network 2>&1 | Out-Null
            }
            Write-CleanupLog "Networks cleaned up" -Color Green
        } else {
            Write-CleanupLog "No networks found matching pattern: *$ProjectPattern*" -Color Yellow
        }
        return $true
    }
    catch {
        Write-CleanupLog "Error removing networks: $_" -Color Red
        return $false
    }
}

# Function to remove project directory
function Remove-ProjectDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,
        [switch]$Force
    )

    try {
        if (Test-Path $DirectoryPath) {
            if (-not $Force) {
                Write-CleanupLog "Skipping directory removal (Force not specified): $DirectoryPath" -Color Yellow
                return $false
            }

            Write-CleanupLog "Removing directory: $DirectoryPath" -Color Yellow
            Set-Location $HOME  # Ensure we don't accidentally remove the current working directory
            Remove-Item -Path $DirectoryPath -Recurse -Force
            Write-CleanupLog "Directory removed" -Color Green
        } else {
            Write-CleanupLog "Directory not found: $DirectoryPath" -Color Yellow
        }
        return $true
    }
    catch {
        Write-CleanupLog "Error removing directory: $_" -Color Red
        return $false
    }
}

# Function to prune Docker resources
function Remove-DockerResources {
    param(
        [switch]$Force
    )

    if (-not (Test-DockerRunning)) {
        Write-CleanupLog "Skipping Docker system prune due to Docker inaccessibility." -Color Red
        return $false
    }

    try {
        Write-CleanupLog "Running Docker system prune..." -Color Yellow
        if ($Force) {
            docker system prune -f 2>&1 | Out-Null
        } else {
            docker system prune 2>&1 | Out-Null
        }
        Write-CleanupLog "Docker system cleaned" -Color Green
        return $true
    }
    catch {
        Write-CleanupLog "Error during Docker cleanup: $_" -Color Red
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Write-CleanupLog',
    'Test-DockerRunning',
    'Stop-ProjectContainers',
    'Remove-ProjectVolumes',
    'Remove-ProjectNetworks',
    'Remove-ProjectDirectory',
    'Remove-DockerResources'
)