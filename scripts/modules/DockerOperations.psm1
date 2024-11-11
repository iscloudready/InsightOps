# Module: DockerOperations.psm1
# Purpose: Contains functions for managing Docker services, containers, logs, and cleanup tasks

# Region: Docker Service Management

# Starts Docker services based on a provided docker-compose file path
function Start-DockerServices {
    param (
        [string]$ComposeFilePath
    )
    try {
        Write-Info "Starting Docker services from: $ComposeFilePath"
        docker-compose -f $ComposeFilePath up -d --build
        Write-Success "Docker services started successfully."
    }
    catch {
        Write-Error "Failed to start Docker services: ${Error[0]}"
        return $false
    }
}

# Stops all running Docker services based on a provided docker-compose file path
function Stop-DockerServices {
    param (
        [string]$ComposeFilePath
    )
    try {
        Write-Info "Stopping Docker services from: $ComposeFilePath"
        docker-compose -f $ComposeFilePath down
        Write-Success "Docker services stopped successfully."
    }
    catch {
        Write-Error "Failed to stop Docker services: ${Error[0]}"
        return $false
    }
}

# Rebuilds (stops, rebuilds, and restarts) a specific Docker service
function Rebuild-DockerService {
    param (
        [string]$ComposeFilePath,
        [string]$ServiceName
    )
    try {
        Write-Info "Rebuilding Docker service: $ServiceName from: $ComposeFilePath"
        docker-compose -f $ComposeFilePath up -d --build $ServiceName
        Write-Success "Docker service '$ServiceName' rebuilt and restarted successfully."
    }
    catch {
        Write-Error "Failed to rebuild Docker service '$ServiceName': ${Error[0]}"
        return $false
    }
}

# Shows the status of all running Docker containers
function Show-DockerStatus {
    try {
        Write-Info "Fetching Docker container status..."
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    }
    catch {
        Write-Error "Failed to fetch Docker status: ${Error[0]}"
    }
}

# Opens specified Docker service URLs in the browser
function Open-ServiceUrls {
    param (
        [hashtable]$ServiceUrls
    )

    foreach ($service in $ServiceUrls.Keys) {
        Write-Info "Opening $service at URL: $($ServiceUrls[$service])"
        try {
            Start-Process $ServiceUrls[$service]
            Start-Sleep -Seconds 1
        }
        catch {
            Write-Warning "Failed to open URL for $service: $($_)"
        }
    }
}

# EndRegion

# Region: Docker Log Management

# Exports logs for specified Docker containers
function Export-DockerLogs {
    param (
        [string]$LogDirectory,
        [array]$Services
    )

    # Ensure the log directory exists
    if (!(Test-Path -Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    # Export logs for each service
    foreach ($service in $Services) {
        $logFile = Join-Path $LogDirectory "$service.log"
        try {
            Write-Info "Exporting logs for Docker service: $service"
            docker logs $service > $logFile 2>&1
            Write-Success "Exported logs for $service to $logFile."
        }
        catch {
            Write-Error "Failed to export logs for $service: $($_)"
        }
    }
}

# Shows logs for a specific Docker service
function Show-DockerLogs {
    param (
        [string]$ServiceName,
        [int]$TailCount = 50
    )
    try {
        Write-Info "Fetching logs for service: $ServiceName"
        docker logs $ServiceName --tail $TailCount
    }
    catch {
        Write-Error "Failed to fetch logs for service '$ServiceName': ${Error[0]}"
    }
}

# EndRegion

# Region: Docker System Cleanup

# Cleans up Docker containers, networks, volumes, and optionally images
function Clean-DockerSystem {
    param (
        [switch]$RemoveImages = $false
    )
    try {
        Write-Info "Cleaning up Docker containers and volumes..."
        docker system prune -f --volumes
        Write-Success "Docker system cleaned successfully."

        if ($RemoveImages) {
            Write-Info "Removing Docker images..."
            docker rmi $(docker images -q) -f
            Write-Success "Docker images removed successfully."
        }
    }
    catch {
        Write-Error "Failed to clean Docker system: ${Error[0]}"
    }
}

# Removes specific Docker volumes based on a naming pattern
function Remove-DockerVolumes {
    param (
        [string]$Pattern
    )
    try {
        Write-Info "Removing Docker volumes with pattern: $Pattern"
        $volumes = docker volume ls -q -f name=$Pattern
        if ($volumes) {
            docker volume rm $volumes -f
            Write-Success "Removed Docker volumes matching pattern: $Pattern"
        }
        else {
            Write-Warning "No Docker volumes found matching pattern: $Pattern"
        }
    }
    catch {
        Write-Error "Failed to remove Docker volumes: ${Error[0]}"
    }
}

# EndRegion

# Export module members
Export-ModuleMember -Function `
    Start-DockerServices, `
    Stop-DockerServices, `
    Rebuild-DockerService, `
    Show-DockerStatus, `
    Open-ServiceUrls, `
    Export-DockerLogs, `
    Show-DockerLogs, `
    Clean-DockerSystem, `
    Remove-DockerVolumes
