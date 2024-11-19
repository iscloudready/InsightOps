# DockerOperations.psm1
# Purpose: Docker operations management
$script:CONFIG_PATH = (Get-Variable -Name CONFIG_PATH -Scope Global).Value
$script:DOCKER_COMPOSE_PATH = Join-Path $script:CONFIG_PATH "docker-compose.yml"
$script:ENV_FILE = Join-Path $script:CONFIG_PATH ".env.Development"

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

        # Set default namespace if not set
        if (-not $env:NAMESPACE) {
            $env:NAMESPACE = "insightops"
        }

        # Print environment info
        Write-Host "Project Root: $projectRoot" -ForegroundColor Cyan
        Write-Host "Config Path: $($env:CONFIG_PATH)" -ForegroundColor Cyan
        Write-Host "Docker Compose Path: $dockerComposePath" -ForegroundColor Cyan
        Write-Host "Namespace: $($env:NAMESPACE)" -ForegroundColor Cyan

        # Stop and cleanup containers
        Write-Host "Stopping all containers..." -ForegroundColor Yellow
        docker-compose -f $dockerComposePath down --volumes --remove-orphans

        # Clean up images
        Write-Host "Cleaning up resources..." -ForegroundColor Yellow
        docker images -q "*$($env:NAMESPACE)*" | ForEach-Object { docker rmi $_ -f }

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
        if (-not (Test-DockerEnvironment)) {
            throw "Docker environment check failed"
        }

        Write-Host "Starting Docker services..." -ForegroundColor Cyan
        $env:CONFIG_PATH = $script:CONFIG_PATH
        
        # Pull latest images
        docker-compose -f $script:DOCKER_COMPOSE_PATH pull

        # Build and start services
        docker-compose -f $script:DOCKER_COMPOSE_PATH up -d --build --remove-orphans

        Write-Host "Services started successfully" -ForegroundColor Green
        docker-compose -f $script:DOCKER_COMPOSE_PATH ps
        
        return $true
    }
    catch {
        Write-Error "Failed to start services: $_"
        return $false
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
    
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    jsonData:
      httpMethod: GET
      serviceMap:
        datasourceUid: prometheus
'@

        $datasourceProvisionPath = Join-Path $grafanaPath "provisioning/datasources/datasources.yaml"
        Set-Content -Path $datasourceProvisionPath -Value $datasourceConfig -Encoding UTF8

        # Create a sample dashboard
        $sampleDashboard = @'
{
  "annotations": {
    "list": []
  },
  "title": "InsightOps Overview",
  "uid": "insightops-overview",
  "version": 1,
  "panels": []
}
'@

        $dashboardPath = Join-Path $grafanaPath "dashboards/overview.json"
        Set-Content -Path $dashboardPath -Value $sampleDashboard -Encoding UTF8

        Write-Host "Grafana configurations created successfully" -ForegroundColor Green
        Write-Host "You'll need to restart Grafana for these changes to take effect" -ForegroundColor Yellow

        return $true
    }
    catch {
        Write-Error "Failed to initialize Grafana configurations: $_"
        return $false
    }
}

function Rebuild-DockerService {
    param (
        [string]$ServiceName = $null
    )

    Test-PathOrFail -Path $script:DOCKER_COMPOSE_PATH -Message "Docker Compose configuration not found"

    # Create keys directory with proper permissions
    $keysPath = Join-Path $env:CONFIG_PATH "keys"
    if (-not (Test-Path $keysPath)) {
        New-Item -ItemType Directory -Path $keysPath -Force
    }

    # Setup volumes
    Setup-DockerVolumes

    if ($ServiceName) {
        Write-Host "Rebuilding service: $ServiceName"
        docker-compose -f $script:DOCKER_COMPOSE_PATH build $ServiceName
        docker-compose -f $script:DOCKER_COMPOSE_PATH up -d $ServiceName
    } else {
        Write-Host "Rebuilding all services"
        docker-compose -f $script:DOCKER_COMPOSE_PATH build
        docker-compose -f $script:DOCKER_COMPOSE_PATH up -d
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
    
    try {
        # Define base volume names
        $volumes = @(
            "postgres_data",
            "grafana_data",
            "prometheus_data",
            "loki_data",
            "tempo_data",
            "frontend_keys",
            "keys_data"
        )

        # Get namespace from environment or use default
        $namespace = if ($env:NAMESPACE) { $env:NAMESPACE } else { "insightops" }
        
        foreach ($vol in $volumes) {
            $volumeName = "$namespace`_$vol"
            Write-Host "Checking volume: $volumeName" -ForegroundColor Yellow
            
            if (-not (docker volume ls --filter "name=^$volumeName$" -q)) {
                Write-Host "Creating Docker volume: $volumeName" -ForegroundColor Green
                $result = docker volume create --name $volumeName 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Failed to create volume $volumeName : $result"
                } else {
                    Write-Host "Successfully created volume: $volumeName" -ForegroundColor Green
                }
            } else {
                Write-Host "Volume exists: $volumeName" -ForegroundColor Cyan
            }
        }
        return $true
    }
    catch {
        Write-Error "Failed to setup Docker volumes: $_"
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
    'Test-DirectoryStructure'
)
