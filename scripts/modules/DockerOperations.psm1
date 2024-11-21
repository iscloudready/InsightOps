# DockerOperations.psm1
# Purpose: Docker operations management
$script:CONFIG_PATH = (Get-Variable -Name CONFIG_PATH -Scope Global).Value
$script:DOCKER_COMPOSE_PATH = Join-Path $script:CONFIG_PATH "docker-compose.yml"
$script:ENV_FILE = Join-Path $script:CONFIG_PATH ".env.Development"

# Check if PSScriptRoot is defined
if (-not $PSScriptRoot) {
    # Attempt to determine the script's path
    if ($MyInvocation.MyCommand.Path) {
        $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    } elseif (Get-Location) {
        # Fallback to the current working directory
        $PSScriptRoot = Get-Location
    }
}
$script:BASE_PATH = $PSScriptRoot
#$script:MODULE_PATH = Join-Path $BASE_PATH "Modules"

# Output paths for debugging
Write-Host "PSScriptRoot: $PSScriptRoot"
#Write-Host "Module Path: $script:MODULE_PATH"

# Import required modules
$monitoringModulePath = Join-Path $script:BASE_PATH "Monitoring.psm1"
if (Test-Path $monitoringModulePath) {
    Write-Host "Loading Monitoring module from: $monitoringModulePath" -ForegroundColor Cyan
    Import-Module $monitoringModulePath -Force
}
else {
    Write-Warning "Monitoring module not found at: $monitoringModulePath"
}

# Add to your script initialization
$env:DOCKER_BUILDKIT = 1
$env:COMPOSE_DOCKER_CLI_BUILD = 1

# Function to verify Docker environment
function Test-DockerEnvironment {
    [CmdletBinding()]
    param()
    
    try {
        # Check Docker daemon
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Docker daemon is not running"
            return $false
        }

        # Check Docker Compose
        $composeVersion = docker-compose version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Docker Compose is not available"
            return $false
        }

        # Check BuildKit
        if (-not $env:DOCKER_BUILDKIT) {
            $env:DOCKER_BUILDKIT = 1
            Write-Host "Enabled BuildKit" -ForegroundColor Yellow
        }

        return $true
    }
    catch {
        Write-Error "Error checking Docker environment: $_"
        return $false
    }
}

function Reset-DockerEnvironment {
    [CmdletBinding()]
    param()
    
    try {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $env:PROJECT_ROOT = $projectRoot
        $env:CONFIG_PATH = Join-Path $projectRoot "Configurations"
        $dockerComposePath = Join-Path $env:CONFIG_PATH "docker-compose.yml"

        # Print environment info
        Write-Host "Project Root: $projectRoot" -ForegroundColor Cyan
        Write-Host "Config Path: $($env:CONFIG_PATH)" -ForegroundColor Cyan
        Write-Host "Docker Compose Path: $dockerComposePath" -ForegroundColor Cyan

        # Stop containers
        Write-Host "Stopping all containers..." -ForegroundColor Yellow
        docker-compose -f $dockerComposePath down --volumes --remove-orphans

        # Clean up images
        Write-Host "Cleaning up insightops resources..." -ForegroundColor Yellow
        docker images -q "*insightops*" | ForEach-Object { docker rmi $_ -f }

        # Setup volumes
        Write-Host "Setting up Docker volumes..." -ForegroundColor Yellow
        if (-not (Setup-DockerVolumes)) {
            throw "Failed to setup Docker volumes"
        }

        Write-Host "Docker environment reset complete" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Error resetting Docker environment: $_"
        return $false
    }
}

function Initialize-DockerEnvironment {
    [CmdletBinding()]
    param()
    
    try {
        # Check if docker-compose.yml exists
        if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
            Write-Warning "Docker Compose configuration not found at: $script:DOCKER_COMPOSE_PATH"
            return $false
        }

        # Explicitly set CONFIG_PATH environment variable
        $env:CONFIG_PATH = $script:CONFIG_PATH
        Write-Verbose "Set CONFIG_PATH environment variable to: $($env:CONFIG_PATH)"

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

        # Set environment variables
        $env:CONFIG_PATH = $script:CONFIG_PATH
        
        # Create process start info for better environment variable handling
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "docker-compose"
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = "-f `"$script:DOCKER_COMPOSE_PATH`" down"
        
        if ($RemoveVolumes) {
            $pinfo.Arguments += " -v"
        }
        $pinfo.Arguments += " --remove-orphans"
        
        # Add environment variables
        $pinfo.EnvironmentVariables["CONFIG_PATH"] = $script:CONFIG_PATH
        
        # Create and start the process
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo
        $process.Start() | Out-Null
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ($process.ExitCode -ne 0) {
            Write-Warning "Process output: $stdout"
            Write-Warning "Process error: $stderr"
            throw "Docker Compose command failed with exit code: $($process.ExitCode)"
        }

        if ($RemoveVolumes) {
            Write-Information "Stopped services and removed volumes."
        }
        else {
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
        Write-Host "`nInitializing Docker services..." -ForegroundColor Cyan

        # 1. Check Docker environment
        if (-not (Test-DockerEnvironment)) {
            throw "Docker environment check failed. Please ensure Docker is running and properly configured."
        }

        # 2. Check Grafana configuration
        Write-Host "`nChecking Grafana configuration..." -ForegroundColor Cyan
        if (-not (Test-GrafanaConfiguration)) {
            $response = Read-Host "Grafana configuration issues detected. Continue anyway? (y/n)"
            if ($response -ne 'y') {
                Write-Host "Aborting service start. Please fix Grafana configuration issues." -ForegroundColor Yellow
                return $false
            }
            Write-Host "Proceeding with service start despite Grafana configuration issues..." -ForegroundColor Yellow
        }

        # 3. Set environment variables
        $env:CONFIG_PATH = $script:CONFIG_PATH
        Write-Host "Using configuration path: $script:CONFIG_PATH" -ForegroundColor Cyan

        # 4. Verify docker-compose file
        if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
            throw "Docker Compose file not found at: $script:DOCKER_COMPOSE_PATH"
        }

        # 5. Pull latest images
        Write-Host "`nPulling latest Docker images..." -ForegroundColor Cyan
        $pullResult = docker-compose -f $script:DOCKER_COMPOSE_PATH pull
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Some images failed to pull. Continuing with existing images..."
        }

        # 6. Build and start services
        Write-Host "`nBuilding and starting services..." -ForegroundColor Cyan
        $startResult = docker-compose -f $script:DOCKER_COMPOSE_PATH up -d --build --remove-orphans
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start services. Check docker-compose output for details."
        }

        # 7. Verify service status
        Write-Host "`nVerifying service status..." -ForegroundColor Cyan
        $services = docker-compose -f $script:DOCKER_COMPOSE_PATH ps
        Write-Host $services

        # 8. Additional health checks
        Write-Host "`nPerforming health checks..." -ForegroundColor Cyan
        $unhealthyServices = docker ps --format "{{.Names}}: {{.Status}}" | Where-Object { $_ -match "unhealthy" }
        if ($unhealthyServices) {
            Write-Warning "Some services are reporting unhealthy status:"
            $unhealthyServices | ForEach-Object { Write-Warning $_ }
        }

        # 9. Final status report
        Write-Host "`nService Startup Summary:" -ForegroundColor Cyan
        Write-Host "------------------------" -ForegroundColor Cyan
        Write-Host "✓ Docker environment verified" -ForegroundColor Green
        Write-Host "✓ Services built and started" -ForegroundColor Green
        
        if ($unhealthyServices) {
            Write-Host "! Some services are unhealthy" -ForegroundColor Yellow
            Write-Host "  Run 'Test-ServiceHealth' for detailed status" -ForegroundColor Yellow
        } else {
            Write-Host "✓ All services reporting healthy" -ForegroundColor Green
        }

        # 10. Provide next steps
        Write-Host "`nNext Steps:" -ForegroundColor Cyan
        Write-Host "1. Check service health: Option 10" -ForegroundColor Yellow
        Write-Host "2. View logs: Option 15" -ForegroundColor Yellow
        Write-Host "3. Access dashboards: Option 20" -ForegroundColor Yellow

        return $true
    }
    catch {
        Write-Error "Failed to start services: $_"
        Write-Host "`nTroubleshooting Steps:" -ForegroundColor Yellow
        Write-Host "1. Check Docker daemon status" -ForegroundColor Yellow
        Write-Host "2. Verify configuration in $script:CONFIG_PATH" -ForegroundColor Yellow
        Write-Host "3. Check service logs for specific errors" -ForegroundColor Yellow
        Write-Host "4. Ensure all required ports are available" -ForegroundColor Yellow
        
        # Cleanup on failure
        Write-Host "`nAttempting cleanup..." -ForegroundColor Cyan
        try {
            docker-compose -f $script:DOCKER_COMPOSE_PATH down
            Write-Host "Cleanup successful" -ForegroundColor Green
        }
        catch {
            Write-Warning "Cleanup failed: $_"
        }
        
        return $false
    }
    finally {
        # Reset environment variables
        if ($env:CONFIG_PATH) {
            Remove-Item Env:\CONFIG_PATH -ErrorAction SilentlyContinue
        }
    }
}

function Get-DetailedServiceLogs {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = $script:CONFIG_PATH,
        [int]$LogLines = 20
    )

    try {
        $services = @(
            @{
                Name = "Loki"
                Container = "insightops_loki"
                LogFile = "loki.log"
                HealthEndpoint = "http://localhost:3101/ready"
            },
            @{
                Name = "Tempo"
                Container = "insightops_tempo"
                LogFile = "tempo.log"
                HealthEndpoint = "http://localhost:3200/ready"
            },
            @{
                Name = "Grafana"
                Container = "insightops_grafana"
                LogFile = "grafana.log"
                HealthEndpoint = "http://localhost:3001/api/health"
            },
            @{
                Name = "Prometheus"
                Container = "insightops_prometheus"
                LogFile = "prometheus.log"
                HealthEndpoint = "http://localhost:9091/-/healthy"
            },
            @{
                Name = "Database"
                Container = "insightops_db"
                LogFile = "postgres.log"
                HealthEndpoint = $null  # PostgreSQL uses a different health check mechanism
            }
        )

        $logsPath = Join-Path $ConfigPath "logs"
        if (-not (Test-Path $logsPath)) {
            New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
            Write-Host "Created logs directory at: $logsPath" -ForegroundColor Green
        }

        foreach ($service in $services) {
            Write-Host "`n========== $($service.Name) Logs ==========" -ForegroundColor Cyan
            Write-Host "Container: $($service.Container)" -ForegroundColor Yellow
            
            # Get container details
            $details = docker inspect $service.Container 2>$null | ConvertFrom-Json
            $status = $details.State.Status
            $health = $details.State.Health.Status
            $startTime = $details.State.StartedAt
            
            Write-Host "Status: $status" -ForegroundColor Yellow
            Write-Host "Health: $health" -ForegroundColor Yellow
            Write-Host "Started At: $startTime" -ForegroundColor Yellow

            # Get and save logs
            $logFilePath = Join-Path $logsPath $service.LogFile
            docker logs --tail $LogLines $service.Container 2>&1 | Out-File -FilePath $logFilePath -Encoding UTF8
            
            Write-Host "`nRecent Logs:" -ForegroundColor Yellow
            $logs = Get-Content $logFilePath -Tail $LogLines
            if ($logs) {
                $logs | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
            } else {
                Write-Host "No recent logs found" -ForegroundColor Yellow
            }

            # Check HTTP health endpoint if available
            if ($service.HealthEndpoint) {
                Write-Host "`nHealth Check:" -ForegroundColor Yellow
                try {
                    $response = Invoke-WebRequest -Uri $service.HealthEndpoint -Method GET -TimeoutSec 5
                    Write-Host "Health endpoint ($($service.HealthEndpoint)) status: $($response.StatusCode)" -ForegroundColor Green
                } catch {
                    Write-Host "Health endpoint ($($service.HealthEndpoint)) failed: $_" -ForegroundColor Red
                }
            }

            Write-Host "----------------------------------------`n"
        }

        Write-Host "Detailed logs have been saved to: $logsPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Error getting service logs: $_"
        Write-Error $_.ScriptStackTrace
    }
}

# Also add this helper function for fixing permissions
function Set-VolumePermissions {
    [CmdletBinding()]
    param()

    try {
        $volumes = @(
            "loki_data",
            "loki_wal",
            "tempo_data",
            "prometheus_data",
            "grafana_data"
        )

        foreach ($vol in $volumes) {
            $path = Join-Path $script:CONFIG_PATH $vol
            if (Test-Path $path) {
                $acl = Get-Acl $path
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    "Everyone",
                    "FullControl",
                    "ContainerInherit,ObjectInherit",
                    "None",
                    "Allow"
                )
                $acl.SetAccessRule($rule)
                Set-Acl -Path $path -AclObject $acl
                Write-Host "Updated permissions for $path" -ForegroundColor Green
            }
            else {
                Write-Warning "Volume path not found: $path"
            }
        }
    }
    catch {
        Write-Error "Error setting volume permissions: $_"
    }
}

function _Stop-DockerServices {
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

function Test-GrafanaConfiguration {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = $script:CONFIG_PATH
    )
    
    Write-Host "`nChecking Grafana configuration..." -ForegroundColor Cyan
    
    # Check required paths
    $paths = @(
        "$ConfigPath/grafana",
        "$ConfigPath/grafana/provisioning",
        "$ConfigPath/grafana/provisioning/dashboards",
        "$ConfigPath/grafana/dashboards"
    )
    
    $allValid = $true
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Write-Host "✓ Found: $path" -ForegroundColor Green
        } else {
            Write-Host "✗ Missing: $path" -ForegroundColor Red
            $allValid = $false
        }
    }
    
    # Check dashboards.yaml
    $dashboardsYaml = "$ConfigPath/grafana/provisioning/dashboards/dashboards.yaml"
    if (Test-Path $dashboardsYaml) {
        Write-Host "✓ Found dashboards.yaml" -ForegroundColor Green
        
        # Verify content
        $content = Get-Content $dashboardsYaml -Raw
        if ($content -match '/etc/grafana/dashboards') {
            Write-Host "✓ Dashboard path configured correctly" -ForegroundColor Green
        } else {
            Write-Host "✗ Invalid dashboard path in dashboards.yaml" -ForegroundColor Red
            $allValid = $false
        }
    } else {
        Write-Host "✗ Missing dashboards.yaml" -ForegroundColor Red
        $allValid = $false
    }
    
    # Check for dashboard JSON files
    $dashboardFiles = Get-ChildItem "$ConfigPath/grafana/dashboards" -Filter "*.json" -ErrorAction SilentlyContinue
    if ($dashboardFiles) {
        Write-Host "✓ Found $($dashboardFiles.Count) dashboard files" -ForegroundColor Green
    } else {
        Write-Host "✗ No dashboard JSON files found" -ForegroundColor Yellow
        $allValid = $false
    }

    if (-not $allValid) {
        Write-Host "`nRecommended fixes:" -ForegroundColor Yellow
        Write-Host "1. Ensure proper folder structure in $ConfigPath/grafana/" -ForegroundColor Yellow
        Write-Host "2. Verify dashboards.yaml configuration" -ForegroundColor Yellow
        Write-Host "3. Check dashboard JSON files exist" -ForegroundColor Yellow
        Write-Host "4. Run Initialize-Environment to recreate missing components" -ForegroundColor Yellow
    }
    
    return $allValid
}

function Test-DashboardJson {
    param([string]$Path)
    try {
        $content = Get-Content $Path -Raw
        $null = ConvertFrom-Json $content
        Write-Host "✓ Valid JSON: $Path" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Invalid JSON in $Path : $_"
        return $false
    }
}

function Initialize-GrafanaDashboards {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = $script:CONFIG_PATH
    )
    try {
        # Create required Grafana directories
        $grafanaPath = Join-Path $ConfigPath "grafana"
        $directories = @(
            (Join-Path $grafanaPath "provisioning"),
            (Join-Path $grafanaPath "provisioning/dashboards"),
            (Join-Path $grafanaPath "provisioning/datasources"),
            (Join-Path $grafanaPath "dashboards")
        )
        foreach ($dir in $directories) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Host "Created directory: $dir" -ForegroundColor Green
            }
        }

        # Initialize monitoring dashboards
        Write-Host "Initializing monitoring dashboards..." -ForegroundColor Cyan
        # Check if monitoring module is available
        if (Get-Command Initialize-Monitoring -ErrorAction SilentlyContinue) {
            Write-Host "Initializing monitoring dashboards..." -ForegroundColor Cyan
            Initialize-Monitoring -ConfigPath $ConfigPath
        }
        else {
            Write-Warning "Monitoring module not loaded. Only creating base dashboards."
        }

        # Create dashboard provisioning config
        $dashboardConfig = @'
apiVersion: 1
providers:
  - name: 'InsightOps'
    orgId: 1
    folder: 'InsightOps'
    folderUid: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
      foldersFromFilesStructure: true
'@
        $dashboardProvisionPath = Join-Path $grafanaPath "provisioning/dashboards/dashboards.yaml"
        Set-Content -Path $dashboardProvisionPath -Value $dashboardConfig -Encoding UTF8

        # Create datasource provisioning config
        $datasourceConfig = @'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    version: 1
    editable: true
    jsonData:
      httpMethod: POST
      timeInterval: "5s"
    
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    version: 1
    editable: true
    jsonData:
      maxLines: 1000
    
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    version: 1
    editable: true
    jsonData:
      httpMethod: GET
      serviceMap:
        datasourceUid: prometheus
'@
        $datasourceProvisionPath = Join-Path $grafanaPath "provisioning/datasources/datasources.yaml"
        Set-Content -Path $datasourceProvisionPath -Value $datasourceConfig -Encoding UTF8

        # Create base dashboard
        $sampleDashboard = @'
{
  "annotations": {
    "list": []
  },
  "title": "InsightOps Overview",
  "uid": "insightops-overview",
  "version": 1,
  "panels": [],
  "refresh": "10s",
  "schemaVersion": 38,
  "tags": ["insightops"],
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "timepicker": {
    "refresh_intervals": [
      "5s",
      "10s",
      "30s",
      "1m",
      "5m",
      "15m",
      "30m",
      "1h",
      "2h",
      "1d"
    ]
  }
}
'@
        $dashboardPath = Join-Path $grafanaPath "dashboards/overview.json"
        Set-Content -Path $dashboardPath -Value $sampleDashboard -Encoding UTF8

        # Create all monitoring dashboards
        $dashboards = @{
            "api-gateway.json" = Get-ApiGatewayDashboard
            "security.json" = Get-SecurityDashboard
            "service-health.json" = Get-ServiceHealthDashboard
            "frontend-realtime.json" = Get-FrontendRealtimeDashboard
            "orders-realtime.json" = Get-OrdersRealtimeDashboard
            "inventory-realtime.json" = Get-InventoryRealtimeDashboard
        }

        foreach ($dashboard in $dashboards.GetEnumerator()) {
            $path = Join-Path $grafanaPath "dashboards/$($dashboard.Key)"
            Write-Host "Creating dashboard: $($dashboard.Key)" -ForegroundColor Cyan
            Set-Content -Path $path -Value $dashboard.Value -Encoding UTF8
        }

        Write-Host "✓ Grafana configurations created successfully" -ForegroundColor Green
        Write-Host "✓ Monitoring dashboards initialized successfully" -ForegroundColor Green
        Write-Host "! You'll need to restart Grafana for these changes to take effect" -ForegroundColor Yellow

        # Add to Initialize-GrafanaDashboards
        $dashboardFiles = Get-ChildItem -Path (Join-Path $grafanaPath "dashboards") -Filter "*.json"
        foreach ($file in $dashboardFiles) {
            Test-DashboardJson $file.FullName
        }

        return $true
    }
    catch {
        Write-Error "Failed to initialize Grafana configurations: $_"
        return $false
    }
}

function Rebuild-DockerService {
    [CmdletBinding()]
    param (
        [string]$ServiceName = $null
    )
    
    try {
        # Verify Docker Compose file
        if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
            throw "Docker Compose configuration not found at: $script:DOCKER_COMPOSE_PATH"
        }

        # Setup environment variables
        $env:NAMESPACE = if ([string]::IsNullOrEmpty($env:NAMESPACE)) { "insightops" } else { $env:NAMESPACE }
        
        # Create keys directory with proper permissions
        $keysPath = Join-Path $env:CONFIG_PATH "keys"
        if (-not (Test-Path $keysPath)) {
            Write-Host "Creating keys directory: $keysPath" -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $keysPath -Force | Out-Null
            Write-Host "✓ Created keys directory" -ForegroundColor Green
        }

        # Stop any existing containers
        Write-Host "Stopping existing containers..." -ForegroundColor Yellow
        if ($ServiceName) {
            docker-compose -f $script:DOCKER_COMPOSE_PATH stop $ServiceName
        } else {
            docker-compose -f $script:DOCKER_COMPOSE_PATH down
        }

        # Reset database
        Write-Host "Resetting database..." -ForegroundColor Yellow
        try {
            # Wait for postgres container to be ready
            Start-Sleep -Seconds 5
            docker exec insightops_db psql -U insightops_user -d postgres -c "
                SELECT pg_terminate_backend(pid) 
                FROM pg_stat_activity 
                WHERE datname = 'insightops_db';
                DROP DATABASE IF EXISTS insightops_db;
                CREATE DATABASE insightops_db;
            "
            Write-Host "Database reset successful" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to reset database: $_"
            # Continue anyway as the database might not exist yet
        }

        # Reinitialize Grafana dashboards
        Write-Host "Initializing Grafana dashboards..." -ForegroundColor Cyan
        Initialize-GrafanaDashboards

        # After initializing Grafana dashboards
        Set-GrafanaPermissions

        # Setup volumes
        Write-Host "Setting up Docker volumes..." -ForegroundColor Cyan
        if (-not (Setup-DockerVolumes)) {
            throw "Failed to setup Docker volumes"
        }

        # Build and start services
        Write-Host "Building and starting services..." -ForegroundColor Cyan
        if ($ServiceName) {
            Write-Host "Rebuilding service: $ServiceName" -ForegroundColor Yellow
            $buildResult = docker-compose -f $script:DOCKER_COMPOSE_PATH build $ServiceName
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to build service $ServiceName : $buildResult"
            }
            
            $upResult = docker-compose -f $script:DOCKER_COMPOSE_PATH up -d $ServiceName
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to start service $ServiceName : $upResult"
            }
        } else {
            Write-Host "Rebuilding all services" -ForegroundColor Yellow
            $buildResult = docker-compose -f $script:DOCKER_COMPOSE_PATH build
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to build services: $buildResult"
            }
            
            $upResult = docker-compose -f $script:DOCKER_COMPOSE_PATH up -d
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to start services: $upResult"
            }
        }

        # Wait longer for services to initialize
        Write-Host "Waiting for services to initialize..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30

        # Check service health
        Write-Host "Checking service health..." -ForegroundColor Cyan
        $services = if ($ServiceName) { @($ServiceName) } else { @("frontend", "apigateway", "orderservice", "inventoryservice") }
        
        foreach ($svc in $services) {
            $containerName = "${env:NAMESPACE}_$svc"
            $logs = docker logs $containerName 2>&1
            $status = docker inspect --format='{{.State.Health.Status}}' $containerName 2>$null
            
            Write-Host "`nService: $svc" -ForegroundColor Cyan
            Write-Host "Status: $status" -ForegroundColor $(if ($status -eq 'healthy') { 'Green' } else { 'Yellow' })
            if ($status -ne 'healthy') {
                Write-Host "Recent logs:" -ForegroundColor Yellow
                $logs | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
            }
        }

        Write-Host "`nService rebuild completed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to rebuild services: $_"
        Write-Error $_.ScriptStackTrace
        return $false
    }
}

function Set-GrafanaPermissions {
    param(
        [string]$ConfigPath = $script:CONFIG_PATH
    )
    
    $grafanaPath = Join-Path $ConfigPath "grafana"
    $paths = @(
        (Join-Path $grafanaPath "dashboards"),
        (Join-Path $grafanaPath "provisioning")
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            # Set directory permissions
            $acl = Get-Acl $path
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.SetAccessRule($accessRule)
            Set-Acl -Path $path -AclObject $acl
            Write-Host "Set permissions for: $path" -ForegroundColor Green
            
            # Set file permissions
            Get-ChildItem -Path $path -Recurse -File | ForEach-Object {
                $acl = Get-Acl $_.FullName
                $acl.SetAccessRule($accessRule)
                Set-Acl -Path $_.FullName -AclObject $acl
                Write-Host "Set permissions for: $($_.FullName)" -ForegroundColor Green
            }
        }
    }
}

function Test-ServiceDependencies {
    [CmdletBinding()]
    param()
    
    try {
        # Check PostgreSQL
        $dbHealth = docker exec insightops_db pg_isready
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Database is not ready"
            return $false
        }

        # Check API Gateway
        $gatewayHealth = Invoke-WebRequest "http://localhost:7237/health" -UseBasicParsing
        if ($gatewayHealth.StatusCode -ne 200) {
            Write-Warning "API Gateway is not healthy"
            return $false
        }

        return $true
    }
    catch {
        Write-Error "Failed to check service dependencies: $_"
        return $false
    }
}

function _Rebuild-DockerService {
    [CmdletBinding()]
    param([string]$ServiceName)
    try {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $env:PROJECT_ROOT = $projectRoot
        $env:CONFIG_PATH = Join-Path $projectRoot "Configurations"
        $dockerComposePath = Join-Path $env:CONFIG_PATH "docker-compose.yml"

        # Wait for Docker to be ready
        $retries = 5
        while ($retries -gt 0) {
            try {
                docker info > $null
                break
            }
            catch {
                Write-Host "Waiting for Docker..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                $retries--
            }
        }

        if ($retries -eq 0) {
            throw "Docker is not responding"
        }

        # Rest of your existing code...
        if ([string]::IsNullOrWhiteSpace($ServiceName)) {
            docker-compose -f $dockerComposePath build --no-cache
            docker-compose -f $dockerComposePath up -d
        }
    }
    catch {
        Write-Error "Failed to rebuild service: $_"
        return $false
    }
}

function Test-DirectoryStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseDirectory
    )

    Write-Host "Checking directory structure in: $BaseDirectory" -ForegroundColor Cyan

    # Expected directory structure
    $requiredDirs = @{
        "FrontendService" = "Frontend application"
        "ApiGateway" = "API Gateway service"
        "OrderService" = "Order management service"
        "InventoryService" = "Inventory management service"
        "Configurations" = "Configuration files"
    }

    $allExist = $true
    foreach ($dir in $requiredDirs.Keys) {
        $path = Join-Path $BaseDirectory $dir
        if (Test-Path $path) {
            Write-Host "✓ Found $($requiredDirs[$dir]) at: $dir" -ForegroundColor Green
        } else {
            Write-Host "✗ Missing $($requiredDirs[$dir]): $dir" -ForegroundColor Red
            $allExist = $false
        }
    }

    return $allExist
}

function Test-PreRebuildRequirements {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot
    )
    
    $checks = @(
        @{
            Name = "Docker Engine"
            Test = { docker info }
        },
        @{
            Name = "Required Directories"
            Test = { Test-DirectoryStructure -BaseDirectory $ProjectRoot }
        },
        @{
            Name = "Configuration Files"
            Test = { 
                $configPath = Join-Path $ProjectRoot "Configurations"
                Test-Path (Join-Path $configPath "appsettings.Docker.json") 
            }
        },
        @{
            Name = "Docker Network"
            Test = { 
                $network = docker network ls --filter name=insightops -q
                if (-not $network) {
                    docker network create insightops
                }
                $true
            }
        }
    )

    $allPassed = $true
    foreach ($check in $checks) {
        Write-Host "Checking $($check.Name)..." -ForegroundColor Yellow
        try {
            if (& $check.Test) {
                Write-Host "✓ $($check.Name) check passed" -ForegroundColor Green
            } else {
                Write-Host "✗ $($check.Name) check failed" -ForegroundColor Red
                $allPassed = $false
            }
        }
        catch {
            Write-Host "✗ $($check.Name) check failed: $_" -ForegroundColor Red
            $allPassed = $false
        }
    }

    return $allPassed
}

function Test-PathOrFail {
    param (
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path $Path)) {
        throw $Message
    }
}

function Setup-DockerVolumes {
    [CmdletBinding()]
    param()
    
    # Define consistent namespace
    $namespace = if ([string]::IsNullOrEmpty($env:NAMESPACE)) { "insightops" } else { $env:NAMESPACE }
    
    $volumes = @(
        "postgres_data",
        "grafana_data",
        "prometheus_data",
        "loki_data",
        "tempo_data",
        "frontend_keys",
        "keys_data"
    )
    
    try {
        Write-Host "Setting up Docker volumes with namespace: $namespace" -ForegroundColor Cyan
        
        foreach ($vol in $volumes) {
            $volumeName = "${namespace}_$vol"
            
            # Check if volume exists
            $existingVolume = docker volume ls --quiet --filter "name=^${volumeName}$"
            
            if (-not $existingVolume) {
                Write-Host "Creating Docker volume: $volumeName" -ForegroundColor Yellow
                $result = docker volume create --name $volumeName 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to create volume $volumeName : $result"
                    return $false
                }
                Write-Host "✓ Successfully created volume: $volumeName" -ForegroundColor Green
            } else {
                Write-Host "✓ Volume exists: $volumeName" -ForegroundColor Green
            }
        }
        return $true
    }
    catch {
        Write-Error "Failed to setup Docker volumes: $_"
        return $false
    }
}

# In DockerOperations.psm1, add function:
function Reset-Database {
    try {
        Write-Host "Resetting database..." -ForegroundColor Yellow
        # Connect to postgres container
        docker exec insightops_db psql -U insightops_user -d postgres -c "
            SELECT pg_terminate_backend(pid) 
            FROM pg_stat_activity 
            WHERE datname = 'insightops_db';
            DROP DATABASE IF EXISTS insightops_db;
            CREATE DATABASE insightops_db;
        "
        Write-Host "Database reset successful" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to reset database: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Setup-DockerVolumes',
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
    'Test-ServiceHealth',
    'Get-DetailedServiceLogs',     
    'Set-VolumePermissions',
    'Initialize-GrafanaDashboards',
    'Rebuild-DockerService',
    'Test-DockerEnvironment',
    'Reset-DockerEnvironment',
    'Test-PreRebuildRequirements',
    'Test-DirectoryStructure',
    'Reset-Database',
    'Set-GrafanaPermissions',
    'Test-DashboardJson',
    'Test-GrafanaConfiguration'
)
