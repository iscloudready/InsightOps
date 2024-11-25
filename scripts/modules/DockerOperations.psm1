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

function Verify-ProjectPaths {
    [CmdletBinding()]
    param()
    
    $projectRoot = $env:PROJECT_ROOT
    if (-not $projectRoot) {
        throw "PROJECT_ROOT environment variable not set"
    }

    Write-Host "Verifying project structure in: $projectRoot" -ForegroundColor Cyan

    $requiredPaths = @{
        "FrontendService" = @("Dockerfile", "FrontendService.csproj")
        "ApiGateway" = @("Dockerfile", "ApiGateway.csproj")
        "OrderService" = @("Dockerfile", "OrderService.csproj")
        "InventoryService" = @("Dockerfile", "InventoryService.csproj")
        "InsightOps.Observability" = @("Observability.csproj")
        "Configurations" = @("docker-compose.yml")
    }

    $allValid = $true
    foreach ($dir in $requiredPaths.Keys) {
        $path = Join-Path $projectRoot $dir
        Write-Host "`nChecking $dir..." -ForegroundColor Yellow
        
        if (-not (Test-Path $path -PathType Container)) {
            Write-Host "✗ Directory not found: $path" -ForegroundColor Red
            $allValid = $false
            continue
        }

        foreach ($file in $requiredPaths[$dir]) {
            $filePath = Join-Path $path $file
            if (Test-Path $filePath -PathType Leaf) {
                Write-Host "  ✓ Found: $file" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Missing: $file" -ForegroundColor Red
                $allValid = $false
            }
        }
    }

    return $allValid
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
        #$dashboardPath = Join-Path $grafanaPath "dashboards/overview.json"
        #Set-Content -Path $dashboardPath -Value $sampleDashboard -Encoding UTF8

        # Create all monitoring dashboards
        #$dashboards = @{
        #    "api-gateway.json" = Get-ApiGatewayDashboard
        #   "security.json" = Get-SecurityDashboard
        #    "service-health.json" = Get-ServiceHealthDashboard
        #    "frontend-realtime.json" = Get-FrontendRealtimeDashboard
        #    "orders-realtime.json" = Get-OrdersRealtimeDashboard
        #    "inventory-realtime.json" = Get-InventoryRealtimeDashboard
        #}

        #foreach ($dashboard in $dashboards.GetEnumerator()) {
        #    $path = Join-Path $grafanaPath "dashboards/$($dashboard.Key)"
        #    Write-Host "Creating dashboard: $($dashboard.Key)" -ForegroundColor Cyan
        #    Set-Content -Path $path -Value $dashboard.Value -Encoding UTF8
        #}

        #Write-Host "✓ Grafana configurations created successfully" -ForegroundColor Green
        #Write-Host "✓ Monitoring dashboards initialized successfully" -ForegroundColor Green
        #Write-Host "! You'll need to restart Grafana for these changes to take effect" -ForegroundColor Yellow

        # Add to Initialize-GrafanaDashboards
        #$dashboardFiles = Get-ChildItem -Path (Join-Path $grafanaPath "dashboards") -Filter "*.json"
        #foreach ($file in $dashboardFiles) {
        #    Test-DashboardJson $file.FullName
        #}

        return $true
    }
    catch {
        Write-Error "Failed to initialize Grafana configurations: $_"
        return $false
    }
}

function Test-DockerPrerequisites {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nChecking Docker Prerequisites..." -ForegroundColor Cyan
        $prerequisites = @{
            "Docker Engine" = $false
            "Docker Compose" = $false
            "Docker Service" = $false
            "Required Permissions" = $false
        }

        # Check Docker Engine
        Write-Host "Checking Docker Engine..." -ForegroundColor Yellow
        $dockerVersion = docker --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Docker Engine: $dockerVersion" -ForegroundColor Green
            $prerequisites["Docker Engine"] = $true
        } else {
            Write-Host "✗ Docker Engine not found or not accessible" -ForegroundColor Red
            return $false
        }

        # Check Docker Compose
        Write-Host "Checking Docker Compose..." -ForegroundColor Yellow
        $composeVersion = docker compose version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Docker Compose: $composeVersion" -ForegroundColor Green
            $prerequisites["Docker Compose"] = $true
        } else {
            Write-Host "✗ Docker Compose not found or not accessible" -ForegroundColor Red
            return $false
        }

        # Check Docker Service
        Write-Host "Checking Docker Service..." -ForegroundColor Yellow
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Docker Service is running" -ForegroundColor Green
            $prerequisites["Docker Service"] = $true
        } else {
            Write-Host "✗ Docker Service is not running" -ForegroundColor Red
            return $false
        }

        # Check Permissions
        Write-Host "Checking Docker Permissions..." -ForegroundColor Yellow
        docker ps > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Required permissions verified" -ForegroundColor Green
            $prerequisites["Required Permissions"] = $true
        } else {
            Write-Host "✗ Insufficient permissions to execute Docker commands" -ForegroundColor Red
            return $false
        }

        # Summary
        Write-Host "`nPrerequisites Summary:" -ForegroundColor Cyan
        $prerequisites.GetEnumerator() | ForEach-Object {
            $status = if ($_.Value) { "✓" } else { "✗" }
            $color = if ($_.Value) { "Green" } else { "Red" }
            Write-Host "$status $($_.Key)" -ForegroundColor $color
        }

        return $prerequisites.Values -notcontains $false
    }
    catch {
        Write-Host "Error checking prerequisites: $_" -ForegroundColor Red
        return $false
    }
}

# SQL template for database reset
$script:RESET_DATABASE_SQL = @"
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE datname = 'insightops_db';
DROP DATABASE IF EXISTS insightops_db;
CREATE DATABASE insightops_db;
\c insightops_db;
-- Clean up any existing migration history if it exists
DROP TABLE IF EXISTS public."__EFMigrationsHistory";
"@

function Reset-Database {
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    try {
        Write-Host "`nInitiating database reset..." -ForegroundColor Yellow
        
        # Safety check unless -Force is used
        if (-not $Force) {
            $confirmation = Read-Host "`nWARNING: This will delete all data. Are you sure? (y/n)"
            if ($confirmation -ne 'y') {
                Write-Host "Database reset cancelled." -ForegroundColor Yellow
                return $false
            }
        }

        # Create temporary SQL file
        $tempSqlPath = Join-Path $env:TEMP "insightops-db-reset.sql"
        $script:RESET_DATABASE_SQL | Set-Content -Path $tempSqlPath -Force

        try {
            Write-Host "Verifying database container status..." -ForegroundColor Yellow
            $containerStatus = docker inspect -f '{{.State.Status}}' insightops_db 2>$null
            
            if ($containerStatus -ne 'running') {
                Write-Warning "Database container is not running. Starting container..."
                docker-compose up -d postgres
                Start-Sleep -Seconds 10 # Wait for container startup
            }

            # Copy SQL file to container
            Write-Host "Copying reset script to container..." -ForegroundColor Yellow
            $copyResult = docker cp $tempSqlPath insightops_db:/tmp/reset-db.sql
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to copy reset script to container: $copyResult"
            }

            # Execute reset script
            Write-Host "Executing database reset..." -ForegroundColor Yellow
            $resetResult = docker exec insightops_db psql -U insightops_user -d postgres -f /tmp/reset-db.sql 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n✓ Database reset successful" -ForegroundColor Green
                Write-Host "✓ Migration history cleaned up" -ForegroundColor Green
                Write-Host "✓ Ready for new migrations" -ForegroundColor Green
            }
            else {
                throw "Database reset failed with exit code $LASTEXITCODE. Output: $resetResult"
            }

            # Verify database exists
            $verifyDb = docker exec insightops_db psql -U insightops_user -lqt | Select-String "insightops_db"
            if (-not $verifyDb) {
                throw "Database verification failed - insightops_db not found after reset"
            }

            return $true
        }
        finally {
            # Cleanup
            if (Test-Path $tempSqlPath) {
                Remove-Item $tempSqlPath -Force -ErrorAction SilentlyContinue
            }
            
            # Clean up SQL file from container
            docker exec insightops_db rm -f /tmp/reset-db.sql 2>$null
        }
    }
    catch {
        Write-Error "Database reset failed: $_"
        Write-Host "`nTroubleshooting steps:" -ForegroundColor Yellow
        Write-Host "1. Verify postgres container is running (docker ps)" -ForegroundColor Yellow
        Write-Host "2. Check postgres logs (docker logs insightops_db)" -ForegroundColor Yellow
        Write-Host "3. Verify database credentials in configuration" -ForegroundColor Yellow
        Write-Host "4. Ensure no active connections are blocking operations" -ForegroundColor Yellow
        return $false
    }
}

function Get-DatabaseSize {
    [CmdletBinding()]
    param()
    
    try {
        $query = "SELECT pg_size_pretty(pg_database_size('insightops_db'));"
        $size = docker exec insightops_db psql -U insightops_user -d insightops_db -t -c $query
        return $size.Trim()
    }
    catch {
        Write-Error "Error getting database size: $_"
        return "Unknown"
    }
}

function Show-DatabaseStatus {
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nDatabase Status:" -ForegroundColor Cyan
        Write-Host "----------------" -ForegroundColor Cyan
        
        # Check if container exists first
        $containerExists = docker ps -a --format "{{.Names}}" | Select-String "insightops_db"
        
        if (-not $containerExists) {
            Write-Host "Status: " -NoNewline
            Write-Host "Database container not found" -ForegroundColor Red
            Write-Host "Connection: " -NoNewline
            Write-Host "Not Available" -ForegroundColor Red
            Write-Host "Size: Not Available"
            Write-Host "Connections: Not Available"
            return $false
        }

        # Container Status
        $containerStatus = docker inspect -f '{{.State.Status}}' insightops_db 2>$null
        Write-Host "Status: " -NoNewline
        Write-Host $containerStatus -ForegroundColor $(if ($containerStatus -eq 'running') { 'Green' } else { 'Red' })

        if ($containerStatus -eq 'running') {
            # Only check these if container is running
            $connectionStatus = Test-DatabaseConnection -Quiet
            Write-Host "Connection: " -NoNewline
            Write-Host $(if ($connectionStatus) { "Connected" } else { "Disconnected" }) -ForegroundColor $(if ($connectionStatus) { 'Green' } else { 'Red' })

            if ($connectionStatus) {
                # Only get these details if connection is successful
                $dbSize = Get-DatabaseSize
                Write-Host "Size: $dbSize"

                $connections = Get-DatabaseConnections
                Write-Host "Active Connections: $connections"
            }
        }
        
        return $true
    }
    catch {
        Write-Host "Error checking database status" -ForegroundColor Red
        Write-Verbose $_.Exception.Message
        return $false
    }
}

# Add this helper function
function Test-DatabaseConnection {
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )
    
    try {
        if (-not $Quiet) {
            Write-Host "Testing database connection..." -ForegroundColor Yellow
        }
        
        $result = docker exec insightops_db pg_isready -U insightops_user -d insightops_db 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "Database connection failed."
        }
        return $false
    }
}

function Verify-DockerComposeFiles {
    [CmdletBinding()]
    param()
    
    try {
        $infraConfig = Join-Path $env:CONFIG_PATH "docker-compose.infrastructure.yml"
        $appConfig = Join-Path $env:CONFIG_PATH "docker-compose.application.yml"

        Write-Host "Verifying Docker Compose configurations..." -ForegroundColor Yellow
        
        if (-not (Test-Path $infraConfig)) {
            Write-Host "Infrastructure compose file missing: $infraConfig" -ForegroundColor Red
            return $false
        }

        if (-not (Test-Path $appConfig)) {
            Write-Host "Application compose file missing: $appConfig" -ForegroundColor Red
            return $false
        }

        # Validate infrastructure compose
        $result = docker-compose -f $infraConfig config
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Infrastructure compose validation failed: $result" -ForegroundColor Red
            return $false
        }

        # Validate application compose
        $result = docker-compose -f $appConfig config
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Application compose validation failed: $result" -ForegroundColor Red
            return $false
        }

        Write-Host "Docker Compose configurations validated successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to verify Docker Compose files: $_"
        return $false
    }
}

function Rebuild-DockerService {
    [CmdletBinding()]
    param (
        [string]$ServiceName = $null
    )

    try {
        # Set up logging files
        $outputFile = Join-Path $env:CONFIG_PATH "docker_rebuild.log"
        $dockerBuildLog = Join-Path $env:CONFIG_PATH "docker_build.log"
        $buildLogPath = Join-Path $env:CONFIG_PATH "docker_build_details.log"
        $frontendBuildLog = Join-Path $env:CONFIG_PATH "frontend_build.log"
        
        Write-Host "Logging output to: $outputFile" -ForegroundColor Cyan
        Write-Host "Docker build logs will be saved to: $dockerBuildLog" -ForegroundColor Cyan
        Write-Host "Detailed build logs will be saved to: $buildLogPath" -ForegroundColor Cyan
        Write-Host "Frontend build logs will be saved to: $frontendBuildLog" -ForegroundColor Cyan
        
        Start-Transcript -Path $outputFile -Append

        if (-not (Verify-ProjectPaths)) {
            throw "Project structure verification failed"
        }

        Write-Host "`nWorking directory: $(Get-Location)" -ForegroundColor Yellow | Tee-Object -Append -FilePath $outputFile
        Write-Host "Project root: $env:PROJECT_ROOT" -ForegroundColor Yellow | Tee-Object -Append -FilePath $outputFile
        Write-Host "Config path: $env:CONFIG_PATH" -ForegroundColor Yellow | Tee-Object -Append -FilePath $outputFile

        Write-Host "Verifying Docker Compose file..." -ForegroundColor Yellow | Tee-Object -Append -FilePath $outputFile

        if (-not $SkipDatabaseReset) {
            Write-Host "`nPreparing database reset..." -ForegroundColor Yellow | Tee-Object -Append -FilePath $outputFile
            $dbStatus = Show-DatabaseStatus
            
            if (-not $ServiceName -or $ServiceName -in @('orderservice', 'inventoryservice')) {
                $resetConfirm = Read-Host "`nWould you like to reset the database? (y/n)"
                if ($resetConfirm -eq 'y') {
                    if (-not (Reset-Database)) {
                        throw "Database reset failed"
                    }
                    Write-Host "✓ Database reset completed" -ForegroundColor Green | Tee-Object -Append -FilePath $outputFile
                } else {
                    Write-Host "Skipping database reset" -ForegroundColor Yellow | Tee-Object -Append -FilePath $outputFile
                }
            }
        }

        if (-not $script:DOCKER_COMPOSE_PATH) {
            $script:DOCKER_COMPOSE_PATH = Join-Path $env:CONFIG_PATH "docker-compose.yml"
            if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
                Write-Error "Docker Compose configuration not found at: $script:DOCKER_COMPOSE_PATH" | Tee-Object -Append -FilePath $outputFile
                throw "Docker Compose configuration not found"
            } else {
                Write-Host "Docker Compose file found: $script:DOCKER_COMPOSE_PATH" -ForegroundColor Green | Tee-Object -Append -FilePath $outputFile
            }
        }

        $tempScriptPath = Join-Path $env:TEMP "docker-compose-commands.cmd"
        Write-Host "Creating Docker commands..." -ForegroundColor Yellow | Tee-Object -Append -FilePath $dockerBuildLog
        
        # Build commands with debug logging
        $commands = "@echo off`n"
        $commands += "REM Validate configuration`n"
        $commands += "docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" config`n"
        $commands += "REM Stop existing containers`n"

        if ($ServiceName) {
            $commands += "docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" stop $ServiceName`n"
        } else {
            $commands += "docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" down --volumes --remove-orphans`n"
        }

        $commands += "REM Build and start services with debug logging`n"
        if ($ServiceName) {
            if ($ServiceName -eq "frontend") {
                $commands += @"
docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" build frontend 2>&1 | Tee-Object -Append -FilePath $frontendBuildLog
docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" up -d frontend
"@
            } else {
                $commands += @"
docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" build $ServiceName
docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" up -d $ServiceName
"@
            }
        } else {
            $commands += @"
docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" build
docker compose --log-level DEBUG --file `"$script:DOCKER_COMPOSE_PATH`" up -d
"@
        }

        $commands | Set-Content -Path $tempScriptPath -Force
        Write-Host "Created temporary command file: $tempScriptPath" -ForegroundColor Gray | Tee-Object -Append -FilePath $dockerBuildLog

        Write-Host "Setting up environment variables..." -ForegroundColor Yellow | Tee-Object -Append -FilePath $outputFile
        $env:NAMESPACE = if ([string]::IsNullOrEmpty($env:NAMESPACE)) { "insightops" } else { $env:NAMESPACE }
        Write-Host "Namespace set to: $env:NAMESPACE" -ForegroundColor Cyan | Tee-Object -Append -FilePath $outputFile

        Write-Host "Setting up Docker volumes..." -ForegroundColor Cyan | Tee-Object -Append -FilePath $outputFile
        
        # Setup Docker volumes with error handling
        $setupVolumesSuccess = $false
        try {
            Setup-DockerVolumes
            Write-Host "✓ Docker volumes configured" -ForegroundColor Green | Tee-Object -Append -FilePath $outputFile
            $setupVolumesSuccess = $true
        } catch {
            Write-Error "Failed to setup Docker volumes: $_" | Tee-Object -Append -FilePath $outputFile
            $_ | Format-List -Force | Out-File -FilePath $outputFile -Append
            throw
        }

        if (-not $setupVolumesSuccess) {
            throw "Docker volume setup failed"
        }

        Write-Host "`nExecuting Docker commands..." -ForegroundColor Cyan | Tee-Object -Append -FilePath $dockerBuildLog
        $output = & $tempScriptPath *>> $dockerBuildLog 2>&1
            
        if ($LASTEXITCODE -ne 0) {
            # Handle frontend specific failures
            if ($ServiceName -eq "frontend" -or -not $ServiceName) {
                $failedContainer = docker ps -a --filter "status=exited" --filter "name=frontend" --format "{{.ID}}" | Select-Object -First 1
                if ($failedContainer) {
                    Write-Warning "Frontend build failed. Getting container logs..." | Tee-Object -Append -FilePath $frontendBuildLog
                    docker logs $failedContainer 2>&1 | Tee-Object -Append -FilePath $frontendBuildLog
                    
                    Write-Host "Getting detailed build logs..." | Tee-Object -Append -FilePath $frontendBuildLog
                    docker-compose --log-level DEBUG -f $script:DOCKER_COMPOSE_PATH logs frontend 2>&1 | Tee-Object -Append -FilePath $frontendBuildLog
                    
                    $dotnetBuildLogs = docker exec $failedContainer cat /tmp/dotnet-build.log 2>$null
                    if ($dotnetBuildLogs) {
                        Write-Host "Found dotnet build logs:" | Tee-Object -Append -FilePath $frontendBuildLog
                        $dotnetBuildLogs | Tee-Object -Append -FilePath $frontendBuildLog
                    }
                }
            }

            # General error handling
            $criticalError = $output | Where-Object { 
                $_ -match "error|fail|exception" -and 
                $_ -notmatch "name: insightops" -and 
                $_ -notmatch "services:" -and
                $_ -notmatch "context:" -and
                $_ -notmatch "dockerfile:" -and
                $_ -notmatch "http2: server: error reading preface" -and
                $_ -notmatch "Error\(s\): 0" -and
                $_ -notmatch "file has already been closed" -and
                $_ -notmatch "warning CS\d+:" -and
                $_ -notmatch "\.cs\(\d+,\d+\):" -and
                $_ -notmatch "^#\d+\s+\d+\.\d+"
            } | Select-Object -First 3

            if ($criticalError) {
                Write-Host "`nError Details:" -ForegroundColor Red | Tee-Object -Append -FilePath $dockerBuildLog
                $criticalError | ForEach-Object { Write-Host "- $_" -ForegroundColor Red | Tee-Object -Append -FilePath $dockerBuildLog }

                # Get failed container logs for any service
                $failedContainer = docker ps -a --filter "status=exited" --format "{{.ID}}" | Select-Object -First 1
                if ($failedContainer) {
                    $containerLogPath = Join-Path $env:CONFIG_PATH "failed_container.log"
                    Write-Host "Saving failed container logs to: $containerLogPath" -ForegroundColor Yellow | Tee-Object -Append -FilePath $dockerBuildLog
                    docker logs $failedContainer > $containerLogPath

                    # Get build logs if available
                    $buildLogs = docker exec $failedContainer cat /tmp/build.log 2>$null
                    if ($buildLogs) {
                        Write-Host "Found build logs:" | Tee-Object -Append -FilePath $buildLogPath
                        $buildLogs | Tee-Object -Append -FilePath $buildLogPath
                    }
                }
                throw "Docker commands failed with critical errors"
            }
        }

        $dockerComposeFile = Join-Path $env:CONFIG_PATH "docker-compose.yml"
        $runningServices = docker-compose -f $dockerComposeFile ps --services --filter "status=running"

        Write-Host "Running services:" -ForegroundColor Cyan | Tee-Object -Append -FilePath $outputFile
        $runningServices | ForEach-Object { Write-Host "- $_" -ForegroundColor Green | Tee-Object -Append -FilePath $outputFile }

        if (-not $runningServices) {
            throw "No services are running after deployment"
        }

        Write-Host "Waiting for services to initialize..." -ForegroundColor Cyan | Tee-Object -Append -FilePath $outputFile
        Start-Sleep -Seconds 30

        Write-Host "Checking service health..." -ForegroundColor Cyan | Tee-Object -Append -FilePath $outputFile
        $services = if ($ServiceName) { @($ServiceName) } else { @("frontend", "apigateway", "orderservice", "inventoryservice") }

        foreach ($svc in $services) {
            $containerName = "${env:NAMESPACE}_$svc"
            try {
                $status = & docker inspect --format='{{.State.Health.Status}}' $containerName 2>$null
                if ($status) {
                    Write-Host "`nService: $svc" -ForegroundColor Cyan | Tee-Object -Append -FilePath $outputFile
                    Write-Host "Status: $status" -ForegroundColor $(if ($status -eq 'healthy') { 'Green' } else { 'Yellow' }) | Tee-Object -Append -FilePath $outputFile
                } else {
                    Write-Warning "Service $svc is not running or does not exist." | Tee-Object -Append -FilePath $outputFile
                }

                # Save logs for each service
                $logDir = ".\docker_logs"
                if (-not (Test-Path $logDir)) {
                    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
                }

                if (docker ps -a --filter name=$containerName 2>$null) {
                    Write-Host "Retrieving logs for $containerName..." -ForegroundColor Yellow | Tee-Object -Append -FilePath $outputFile
                    $logFilePath = Join-Path $logDir "$containerName.log"
                    docker logs $containerName > $logFilePath 2>&1
                    Write-Host " Logs saved to: $logFilePath" -ForegroundColor Green | Tee-Object -Append -FilePath $outputFile
                }
            } catch {
                Write-Error "Failed to check service $svc : $_" | Tee-Object -Append -FilePath $outputFile
            }
        }

        Write-Host "`n✓ Service rebuild completed successfully" -ForegroundColor Green | Tee-Object -Append -FilePath $outputFile
        return $true
    }
    catch {
        Write-Error "Failed to rebuild services: $_" | Tee-Object -Append -FilePath $outputFile
        $_ | Format-List -Force | Out-File -FilePath $outputFile -Append
        return $false
    }
    finally {
        if ($tempScriptPath -and (Test-Path $tempScriptPath)) {
            Remove-Item $tempScriptPath -Force
        }
        Remove-Item Env:\NAMESPACE -ErrorAction SilentlyContinue
        Stop-Transcript
    }
}

function RRRebuild-DockerService {
    [CmdletBinding()]
    param (
        [string]$ServiceName = $null
    )

    try {
        # Verify paths first
        if (-not (Verify-ProjectPaths)) {
            throw "Project structure verification failed"
        }

        Write-Host "`nWorking directory: $(Get-Location)" -ForegroundColor Yellow
        Write-Host "Project root: $env:PROJECT_ROOT" -ForegroundColor Yellow
        Write-Host "Config path: $env:CONFIG_PATH" -ForegroundColor Yellow

        # Verify Docker Compose file
        Write-Host "Verifying Docker Compose file..." -ForegroundColor Yellow

        # Database reset with proper handling
        if (-not $SkipDatabaseReset) {
            Write-Host "`nPreparing database reset..." -ForegroundColor Yellow
            $dbStatus = Show-DatabaseStatus
            
            if (-not $ServiceName -or $ServiceName -in @('orderservice', 'inventoryservice')) {
                $resetConfirm = Read-Host "`nWould you like to reset the database? (y/n)"
                if ($resetConfirm -eq 'y') {
                    if (-not (Reset-Database)) {
                        throw "Database reset failed"
                    }
                    Write-Host "✓ Database reset completed" -ForegroundColor Green
                } else {
                    Write-Host "Skipping database reset" -ForegroundColor Yellow
                }
            }
        }

        if (-not $script:DOCKER_COMPOSE_PATH) {
            $script:DOCKER_COMPOSE_PATH = Join-Path $env:CONFIG_PATH "docker-compose.yml"
            if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
                Write-Error "Docker Compose configuration not found at: $script:DOCKER_COMPOSE_PATH"
                throw "Docker Compose configuration not found"
            } else {
                Write-Host "Docker Compose file found: $script:DOCKER_COMPOSE_PATH" -ForegroundColor Green
            }
        }

        # Create a temporary script for Docker commands
        $tempScriptPath = Join-Path $env:TEMP "docker-compose-commands.cmd"
        
        # Create commands file with proper path handling
        $commands = @"
@echo off
REM Validate configuration
docker compose --file `"$script:DOCKER_COMPOSE_PATH`" config

REM Stop existing containers
"@
        if ($ServiceName) {
            $commands += "`ndocker compose --file `"$script:DOCKER_COMPOSE_PATH`" stop $ServiceName"
        } else {
            $commands += "`ndocker compose --file `"$script:DOCKER_COMPOSE_PATH`" down --volumes --remove-orphans"
        }

        $commands += @"

REM Build and start services
"@
        if ($ServiceName) {
            $commands += @"
docker compose --file `"$script:DOCKER_COMPOSE_PATH`" build $ServiceName
docker compose --file `"$script:DOCKER_COMPOSE_PATH`" up -d $ServiceName
"@
        } else {
            $commands += @"
docker compose --file `"$script:DOCKER_COMPOSE_PATH`" build
docker compose --file `"$script:DOCKER_COMPOSE_PATH`" up -d
"@
        }

        # Write commands to file
        $commands | Set-Content -Path $tempScriptPath -Force
        Write-Host "Created temporary command file: $tempScriptPath" -ForegroundColor Gray

        # Setup environment variables
        Write-Host "Setting up environment variables..." -ForegroundColor Yellow
        $env:NAMESPACE = if ([string]::IsNullOrEmpty($env:NAMESPACE)) { "insightops" } else { $env:NAMESPACE }
        Write-Host "Namespace set to: $env:NAMESPACE" -ForegroundColor Cyan

        # Create keys directory
        Write-Host "Creating keys directory..." -ForegroundColor Yellow
        $keysPath = Join-Path $env:CONFIG_PATH "keys"
        if (-not (Test-Path $keysPath)) {
            New-Item -ItemType Directory -Path $keysPath -Force | Out-Null
            Write-Host "Keys directory created: $keysPath" -ForegroundColor Green
        } else {
            Write-Host "Keys directory exists: $keysPath" -ForegroundColor Cyan
        }

        # Initialize Grafana dashboards
        Write-Host "Initializing Grafana dashboards..." -ForegroundColor Cyan
        try {
            Initialize-GrafanaDashboards
            Write-Host "✓ Grafana dashboards initialized" -ForegroundColor Green
        } catch {
            Write-Error "Failed to initialize Grafana dashboards: $_"
            $_ | Format-List -Force
        }

        # Setup Docker volumes
        Write-Host "Setting up Docker volumes..." -ForegroundColor Cyan
        try {
            Setup-DockerVolumes
            Write-Host "✓ Docker volumes configured" -ForegroundColor Green
        } catch {
            Write-Error "Failed to setup Docker volumes: $_"
            $_ | Format-List -Force
        }

        # Execute Docker commands
        Write-Host "`nExecuting Docker commands..." -ForegroundColor Cyan
        try {
            # Redirect verbose output to null and only capture errors
            $output = & $tempScriptPath 2>&1
            
            # Check if there were any errors
            if ($LASTEXITCODE -ne 0) {
                # Filter out known non-critical errors and warnings
                $criticalError = $output | Where-Object { 
                    $_ -match "error|fail|exception" -and 
                    $_ -notmatch "name: insightops" -and 
                    $_ -notmatch "services:" -and
                    $_ -notmatch "context:" -and
                    $_ -notmatch "dockerfile:" -and
                    $_ -notmatch "http2: server: error reading preface" -and
                    $_ -notmatch "Error\(s\): 0" -and
                    $_ -notmatch "file has already been closed" -and
                    # Ignore C# compiler warnings
                    $_ -notmatch "warning CS\d+:" -and
                    $_ -notmatch "\.cs\(\d+,\d+\):" -and
                    # Ignore build number outputs
                    $_ -notmatch "^#\d+\s+\d+\.\d+"
                } | Select-Object -First 3

                if ($criticalError) {
                    Write-Host "`nError Details:" -ForegroundColor Red
                    $criticalError | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
                    throw "Docker commands failed with critical errors"
                }
                else {
                    # Check if containers are actually running
                    $dockerComposeFile = Join-Path $env:CONFIG_PATH "docker-compose.yml"
                    $runningContainers = docker-compose -f $dockerComposeFile ps --services --filter "status=running"
                    if ($runningContainers) {
                        Write-Host "✓ Docker commands completed successfully - services are running" -ForegroundColor Green
                        return $true
                    }
                }
            }
            else {
                Write-Host "✓ Docker commands executed successfully" -ForegroundColor Green
            }

            # Final verification of running services
            $dockerComposeFile = Join-Path $env:CONFIG_PATH "docker-compose.yml"
            $runningServices = docker-compose -f $dockerComposeFile ps --services --filter "status=running"

            Write-Host "Running services:" -ForegroundColor Cyan
            $runningServices | ForEach-Object { Write-Host "- $_" -ForegroundColor Green }

            if ($runningServices) {
                return $true
            } else {
                Write-Error "No services are running after deployment" # throw
            }
        }
        catch {
            if ($_.Exception.Message -match "No services are running") {
                Write-Error "Deployment failed: No services are running"
                #throw
            }
            elseif ($_.Exception.Message -match "Docker commands failed with critical errors") {
                Write-Error "Failed to execute Docker commands with critical errors"
                #throw
            }
            else {
                # Log warning but continue if services are running
                $runningServices = docker-compose ps --services --filter "status=running"
                if ($runningServices) {
                    Write-Warning "Non-critical warning during deployment: $_"
                    Write-Host "Services are running despite warnings" -ForegroundColor Green
                    return $true
                }
                else {
                    Write-Error "Deployment failed: $_"
                    #throw
                }
            }
        }

        # Wait for services to initialize
        Write-Host "Waiting for services to initialize..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30

        # Check service health
        Write-Host "Checking service health..." -ForegroundColor Cyan
        $services = if ($ServiceName) { @($ServiceName) } else { @("frontend", "apigateway", "orderservice", "inventoryservice") }

        foreach ($svc in $services) {
            $containerName = "${env:NAMESPACE}_$svc"
            try {
                $status = & docker inspect --format='{{.State.Health.Status}}' $containerName 2>$null
                if ($status) {
                    Write-Host "`nService: $svc" -ForegroundColor Cyan
                    Write-Host "Status: $status" -ForegroundColor $(if ($status -eq 'healthy') { 'Green' } else { 'Yellow' })
                } else {
                    Write-Warning "Service $svc is not running or does not exist."
                }

                # Save logs
                $logDir = ".\docker_logs"
                if (-not (Test-Path $logDir)) {
                    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
                }

                if (docker ps -a --filter name=$containerName 2>$null) {
                    Write-Host "Retrieving logs for $containerName..." -ForegroundColor Yellow
                    $logFilePath = Join-Path $logDir "$containerName.log"
                    docker logs $containerName > $logFilePath 2>&1
                    Write-Host " Logs saved to: $logFilePath" -ForegroundColor Green
                }
            } catch {
                Write-Error "Failed to check service $svc : $_"
            }
        }

        Write-Host "`n✓ Service rebuild completed successfully" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to rebuild services: $_"
        $_ | Format-List -Force
        return $false
    } finally {
        # Cleanup
        if ($tempScriptPath -and (Test-Path $tempScriptPath)) {
            Remove-Item $tempScriptPath -Force
        }
        Remove-Item Env:\NAMESPACE -ErrorAction SilentlyContinue
    }
}

function __Rebuild-DockerService {
    [CmdletBinding()]
    param (
        [string]$ServiceName = $null
    )

    try {
        # Verify Docker Compose file
        Write-Host "Verifying Docker Compose file..." -ForegroundColor Yellow
        if (-not $script:DOCKER_COMPOSE_PATH) {
            $script:DOCKER_COMPOSE_PATH = Join-Path $env:CONFIG_PATH "docker-compose.yml"
            if (-not (Test-Path $script:DOCKER_COMPOSE_PATH)) {
                Write-Error "Docker Compose configuration not found at: $script:DOCKER_COMPOSE_PATH"
                throw "Docker Compose configuration not found"
            } else {
                Write-Host "Docker Compose file found: $script:DOCKER_COMPOSE_PATH" -ForegroundColor Green
            }
        }

        # Validate Docker Compose file
        $validationCmd = "docker-compose -f $script:DOCKER_COMPOSE_PATH config"
        $validationResult = Invoke-Expression $validationCmd
        if ($LASTEXITCODE -ne 0) {
            throw "Docker Compose validation failed. Logs: $validationResult"
        }

        # Setup environment variables
        Write-Host "Setting up environment variables..." -ForegroundColor Yellow
        $env:NAMESPACE = if ([string]::IsNullOrEmpty($env:NAMESPACE)) { "insightops" } else { $env:NAMESPACE }
        Write-Host "Namespace set to: $env:NAMESPACE" -ForegroundColor Cyan

        # Create keys directory with proper permissions
        Write-Host "Creating keys directory..." -ForegroundColor Yellow
        $keysPath = Join-Path $env:CONFIG_PATH "keys"
        if (-not (Test-Path $keysPath)) {
            New-Item -ItemType Directory -Path $keysPath -Force | Out-Null
            Write-Host "Keys directory created: $keysPath" -ForegroundColor Green
        } else {
            Write-Host "Keys directory already exists: $keysPath" -ForegroundColor Cyan
        }

        # Stop any existing containers
        Write-Host "Stopping existing containers..." -ForegroundColor Yellow
        try {
            if ($ServiceName) {
                if (docker ps --filter "name=$ServiceName" --format "{{.Names}}" | Select-String -Pattern $ServiceName) {
                    $stopCmd = "docker-compose -f $script:DOCKER_COMPOSE_PATH stop $ServiceName"
                    Write-Host "Executing: $stopCmd" -ForegroundColor Yellow
                    Invoke-Expression $stopCmd
                } else {
                    Write-Warning "Service $ServiceName is not running. Skipping stop."
                }
            } else {
                $stopCmd = "docker-compose -f $script:DOCKER_COMPOSE_PATH down --volumes --remove-orphans"
                Write-Host "Executing: $stopCmd" -ForegroundColor Yellow
                Invoke-Expression $stopCmd
            }
        } catch {
            Write-Error "Failed to stop existing containers: $_"
            $_ | Format-List -Force
        }

        # Reset database
        Write-Host "Resetting database..." -ForegroundColor Yellow
        try {
            if (docker ps --filter "name=insightops_db" --format "{{.Names}}" | Select-String -Pattern "insightops_db") {
                Start-Sleep -Seconds 5
                $resetCmd = @"
docker exec insightops_db psql -U insightops_user -d postgres -c "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = 'insightops_db';
    DROP DATABASE IF EXISTS insightops_db;
    CREATE DATABASE insightops_db;
"
"@
                Write-Host "Executing: $resetCmd" -ForegroundColor Yellow
                Invoke-Expression $resetCmd
                Write-Host "Database reset successful" -ForegroundColor Green
            } else {
                Write-Warning "Database container 'insightops_db' not found. Skipping database reset."
            }
        } catch {
            Write-Error "Failed to reset database: $_"
            $_ | Format-List -Force
        }

        # Reinitialize Grafana dashboards
        Write-Host "Initializing Grafana dashboards..." -ForegroundColor Cyan
        try {
            Initialize-GrafanaDashboards
        } catch {
            Write-Error "Failed to initialize Grafana dashboards: $_"
            $_ | Format-List -Force
        }

        # Set permissions
        Write-Host "Setting permissions for directories..." -ForegroundColor Cyan
        try {
            Set-GrafanaPermissions
            Write-Host "Permissions successfully set." -ForegroundColor Green
        } catch {
            Write-Error "Error setting permissions: $_"
            $_ | Format-List -Force
        }

        # Setup Docker volumes
        Write-Host "Setting up Docker volumes..." -ForegroundColor Cyan
        try {
            Setup-DockerVolumes
        } catch {
            Write-Error "Failed to setup Docker volumes: $_"
            $_ | Format-List -Force
        }

        # Build and start services
        Write-Host "Building and starting services..." -ForegroundColor Cyan
        try {
            if ($ServiceName) {
                $buildCmd = "docker-compose -f $script:DOCKER_COMPOSE_PATH build $ServiceName"
                Write-Host "Executing: $buildCmd" -ForegroundColor Yellow
                $buildResult = Invoke-Expression $buildCmd
                Write-Host "$buildResult" -ForegroundColor Cyan

                $upCmd = "docker-compose -f $script:DOCKER_COMPOSE_PATH up -d $ServiceName"
                Write-Host "Executing: $upCmd" -ForegroundColor Yellow
                $upResult = Invoke-Expression $upCmd
                Write-Host "$upResult" -ForegroundColor Cyan
            } else {
                $buildCmd = "docker-compose -f $script:DOCKER_COMPOSE_PATH build"
                Write-Host "Executing: $buildCmd" -ForegroundColor Yellow
                $buildResult = Invoke-Expression $buildCmd
                Write-Host "$buildResult" -ForegroundColor Cyan

                $upCmd = "docker-compose -f $script:DOCKER_COMPOSE_PATH up -d"
                Write-Host "Executing: $upCmd" -ForegroundColor Yellow
                $upResult = Invoke-Expression $upCmd
                Write-Host "$upResult" -ForegroundColor Cyan
            }
        } catch {
            Write-Error "Failed to build and start services: $_"
            $_ | Format-List -Force
        }

        # Wait for services to initialize
        Write-Host "Waiting for services to initialize..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30

        # Check service health
        Write-Host "Checking service health..." -ForegroundColor Cyan
        $services = if ($ServiceName) { @($ServiceName) } else { @("frontend", "apigateway", "orderservice", "inventoryservice") }
        foreach ($svc in $services) {
            $containerName = "${env:NAMESPACE}_$svc"

            try {
                $status = docker inspect --format='{{.State.Health.Status}}' $containerName 2>$null
                if ($status) {
                    Write-Host "`nService: $svc" -ForegroundColor Cyan
                    Write-Host "Status: $status" -ForegroundColor $(if ($status -eq 'healthy') { 'Green' } else { 'Yellow' })
                } else {
                    Write-Warning "Service $svc is not running or does not exist."
                }
            } catch {
                Write-Error "Failed to inspect service $($svc). Error: $_"
                $_ | Format-List -Force
            }

            # Retrieve and save logs
            if (docker ps -a --filter name=$containerName) {
                Write-Host "Retrieving logs for $containerName..." -ForegroundColor Yellow
                $dockerLogs = docker logs $containerName
                Write-Host "$dockerLogs" -ForegroundColor Cyan
                $logFilePath = ".\docker_logs\$containerName.log"
                $dockerLogs | Out-File -FilePath $logFilePath
            } else {
                Write-Warning "Container $containerName does not exist. Skipping log retrieval."
            }
        }

        Write-Host "`nService rebuild completed" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to rebuild services: $_"
        $_ | Format-List -Force
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
            try {
                # Set directory permissions
                $acl = Get-Acl $path
                $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    "Everyone", 
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    $inheritanceFlags,
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                
                # Remove existing rules for "Everyone" before adding new rule
                $acl.Access | Where-Object {$_.IdentityReference -eq "Everyone"} | ForEach-Object {$acl.RemoveAccessRule($_)}
                
                $acl.AddAccessRule($accessRule)
                Set-Acl -Path $path -AclObject $acl
                Write-Host "Set permissions for: $path" -ForegroundColor Green
                
                # Set file permissions
                Get-ChildItem -Path $path -Recurse -File | ForEach-Object {
                    $fileAcl = Get-Acl $_.FullName
                    $fileAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        "Everyone", 
                        [System.Security.AccessControl.FileSystemRights]::FullControl,
                        [System.Security.AccessControl.InheritanceFlags]::None,
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                    
                    # Remove existing rules for "Everyone" before adding new rule
                    $fileAcl.Access | Where-Object {$_.IdentityReference -eq "Everyone"} | ForEach-Object {$fileAcl.RemoveAccessRule($_)}
                    
                    $fileAcl.AddAccessRule($fileAccessRule)
                    Set-Acl -Path $_.FullName -AclObject $fileAcl
                    Write-Host "Set permissions for: $($_.FullName)" -ForegroundColor Green
                }
            } catch {
                Write-Error "Failed to set permissions for: $path. Error: $_"
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
    'Test-DatabaseConnection',
    'Get-DatabaseSize',
    'Show-DatabaseStatus',
    'Set-GrafanaPermissions',
    'Test-DashboardJson',
    'Test-GrafanaConfiguration',
    'Test-DockerPrerequisites'
)
