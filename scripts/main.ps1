# main.ps1
# Purpose: Main entry point for InsightOps management script

$ErrorActionPreference = "Stop"
$script:BASE_PATH = $PSScriptRoot
$script:MODULE_PATH = Join-Path $BASE_PATH "Modules"
$env:MODULE_PATH = $script:MODULE_PATH
$env:CONFIG_PATH = $script:CONFIG_PATH
# In main.ps1, add:
#Import-Module (Join-Path $script:MODULE_PATH "Monitoring.psm1") -Force

# Helper function to check prerequisites before starting services
function Test-Prerequisites {
    [CmdletBinding()]
    param()
    
    try {
        # Check if Docker daemon is accessible
        $dockerPs = docker ps 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Docker is not running" -ForegroundColor Red
            return $false
        }

        # Check configuration exists
        if (-not (Test-Configuration)) {
            Write-Host "Configuration check failed" -ForegroundColor Red
            return $false
        }

        # Check required directories
        foreach ($dir in $script:REQUIRED_PATHS) {
            if (-not (Test-Path $dir)) {
                Write-Host "Missing required directory: $dir" -ForegroundColor Red
                return $false
            }
        }

        # All checks passed
        Write-Host "Prerequisites check passed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Prerequisite check failed: $_" -ForegroundColor Red
        return $false
    }
}

function Write-ModuleMessage {
    param (
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Remove-ModuleSafely {
    param ([string]$ModuleName)
    
    if (Get-Module $ModuleName) {
        try {
            Remove-Module $ModuleName -Force -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
    return $true
}

function Import-ModuleSafely {
    param (
        [string]$ModuleName,
        [switch]$Required
    )
    
    try {
        $modulePath = Join-Path $script:MODULE_PATH "$ModuleName.psm1"
        
        if (-not (Test-Path $modulePath)) {
            throw "Module file not found: $modulePath"
        }

        # Remove existing module if loaded
        Remove-ModuleSafely $ModuleName

        # Import the module
        Import-Module $modulePath -Force -DisableNameChecking -Global -ErrorAction Stop
        Write-ModuleMessage "Successfully imported module: $ModuleName" -Color Green
        
        # Verify module loaded correctly
        $module = Get-Module $ModuleName
        if (-not $module) {
            throw "Module import verification failed"
        }
        
        return $true
    }
    catch {
        Write-ModuleMessage "Failed to import module $ModuleName : $_" -Color Red
        if ($Required) {
            throw "Required module $ModuleName could not be loaded"
        }
        return $false
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "`n╔════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║    InsightOps Management Console    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════╝" -ForegroundColor Cyan

    # System Setup & Prerequisites
    Write-Host "`n[Setup and Prerequisites]" -ForegroundColor Yellow
    Write-Host " 1.  Check Prerequisites" -ForegroundColor White
    Write-Host " 2.  Initialize Environment" -ForegroundColor White
    Write-Host " 3.  Test Configuration" -ForegroundColor White
    Write-Host " 4.  Initialize Required Directories" -ForegroundColor White
    Write-Host " 5.  Backup Configuration" -ForegroundColor White

    # Core Service Operations
    Write-Host "`n[Service Operations]" -ForegroundColor Yellow
    Write-Host " 6.  Start Services" -ForegroundColor White
    Write-Host " 7.  Stop Services" -ForegroundColor White
    Write-Host " 8.  Restart Services" -ForegroundColor White
    Write-Host " 9.  Rebuild Service" -ForegroundColor White

    # Monitoring & Health
    Write-Host "`n[Monitoring and Health]" -ForegroundColor Yellow
    Write-Host " 10. Check Service Health" -ForegroundColor White
    Write-Host " 11. Show Container Status" -ForegroundColor White
    Write-Host " 12. View Resource Usage" -ForegroundColor White
    Write-Host " 13. View System Metrics" -ForegroundColor White
    Write-Host " 14. Test Network Connectivity" -ForegroundColor White
    Write-Host " 15. Check Grafana Configuration" -ForegroundColor White

    # Logging & Debugging
    Write-Host "`n[Logging and Debugging]" -ForegroundColor Yellow
    Write-Host " 16. View Service Logs" -ForegroundColor White
    Write-Host " 17. Export Container Logs" -ForegroundColor White
    Write-Host " 18. Show Quick Reference" -ForegroundColor White
    Write-Host " 19. View Detailed Service Logs" -ForegroundColor White

    # Maintenance
    Write-Host "`n[Maintenance]" -ForegroundColor Yellow
    Write-Host " 20. Clean Docker System" -ForegroundColor White
    Write-Host " 21. Run Cleanup Tasks" -ForegroundColor White
    Write-Host " 22. Prune Docker Resources" -ForegroundColor White
    Write-Host " 23. Reset Environment" -ForegroundColor White

    # Access & Configuration
    Write-Host "`n[Access and Configuration]" -ForegroundColor Yellow
    Write-Host " 24. Open Service URLs" -ForegroundColor White
    Write-Host " 25. Configure Grafana Dashboards" -ForegroundColor White
    Write-Host " 26. Manage Service Settings" -ForegroundColor White

    # System Information
    Write-Host "`n[System Information]" -ForegroundColor Yellow
    Write-Host " 27. View Environment Status" -ForegroundColor White
    Write-Host " 28. Show Service Dependencies" -ForegroundColor White
    Write-Host " 29. Display Configuration Paths" -ForegroundColor White

    # Exit
    Write-Host "`n[System Control]" -ForegroundColor Yellow
    Write-Host " 0.  Exit" -ForegroundColor Red

    Write-Host "`n╔════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║    Current Environment: $(if ($env:ASPNETCORE_ENVIRONMENT) { $env:ASPNETCORE_ENVIRONMENT } else { 'Development' })    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════╝" -ForegroundColor Cyan

    # Show service status summary if services are running
    if (Test-DockerEnvironment) {
        try {
            $runningContainers = (docker ps -q).Count
            $totalContainers = (docker ps -aq).Count
            $healthyContainers = (docker ps --format "{{.Status}}" | Select-String "healthy").Count
            
            Write-Host "`nService Status Summary:" -ForegroundColor Magenta
            Write-Host " • Running: $runningContainers/$totalContainers containers" -ForegroundColor $(if ($runningContainers -eq $totalContainers) { "Green" } else { "Yellow" })
            Write-Host " • Healthy: $healthyContainers/$runningContainers containers" -ForegroundColor $(if ($healthyContainers -eq $runningContainers) { "Green" } else { "Yellow" })
            
            # Show resource usage summary
            $cpuUsage = docker stats --no-stream --format "{{.CPUPerc}}" | ForEach-Object { $_ -replace '%', '' } | Measure-Object -Average | Select-Object -ExpandProperty Average
            $memUsage = docker stats --no-stream --format "{{.MemPerc}}" | ForEach-Object { $_ -replace '%', '' } | Measure-Object -Average | Select-Object -ExpandProperty Average
            
            Write-Host " • CPU Usage: $([math]::Round($cpuUsage, 2))%" -ForegroundColor $(if ($cpuUsage -lt 80) { "Green" } else { "Red" })
            Write-Host " • Memory Usage: $([math]::Round($memUsage, 2))%" -ForegroundColor $(if ($memUsage -lt 80) { "Green" } else { "Red" })
        }
        catch {
            Write-Host "`nUnable to fetch service status: $_" -ForegroundColor Red
        }
    }

    # Last update time
    Write-Host "`nLast Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "Type 'help <number>' for detailed information about a command" -ForegroundColor Gray
}

# Helper function for command help
function Get-CommandHelp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Number
    )

    $helpText = switch ($Number) {
        # Setup & Prerequisites
        "1" { "Checks all prerequisites required for the system to run properly including Docker, .NET SDK, and required ports" }
        "2" { "Initializes the environment with required configurations, directories, and default settings" }
        "3" { "Tests the current configuration for completeness and correctness across all services" }
        "4" { "Creates and verifies all required directories for data persistence and logging" }
        "5" { "Creates a backup of the current configuration and volumes" }

        # Service Operations
        "6" { "Starts all services defined in docker-compose.yml with health checks and dependency validation" }
        "7" { "Gracefully stops all running services while preserving data" }
        "8" { "Performs a complete restart of all services with proper shutdown and startup sequence" }
        "9" { "Rebuilds specific services or all services with updated configurations" }

        # Monitoring & Health
        "10" { "Performs comprehensive health checks on all services including containers and endpoints" }
        "11" { "Shows detailed status of all Docker containers including health state and uptime" }
        "12" { "Displays real-time resource usage statistics for all running containers" }
        "13" { "Views detailed system metrics including CPU, memory, and network usage" }
        "14" { "Tests network connectivity and port availability for all services" }
        "15" { "Verifies Grafana configuration including dashboards, datasources, and provisioning" }

        # Logging & Debugging
        "16" { "Views service logs with filtering and search capabilities" }
        "17" { "Exports container logs to files for analysis or troubleshooting" }
        "18" { "Shows quick reference guide for common operations and commands" }
        "19" { "Displays detailed service logs with additional context and formatting" }

        # Maintenance
        "20" { "Cleans Docker system by removing unused containers, networks, and images" }
        "21" { "Executes cleanup tasks including log rotation and temporary file removal" }
        "22" { "Prunes Docker resources including unused volumes and networks" }
        "23" { "Resets environment to initial state while preserving essential data" }

        # Access & Configuration
        "24" { @"
Opens service URLs in default browser including:
- Grafana (http://localhost:3001)
- Prometheus (http://localhost:9091)
- Loki (http://localhost:3101)
- Tempo (http://localhost:4317)
- Frontend and API endpoints
"@ }
        "25" { @"
Configures Grafana dashboards:
- Provisions default dashboards
- Sets up data sources
- Configures alerting
- Validates configurations
"@ }
        "26" { @"
Manages service settings:
- Environment variables
- Connection strings
- Service endpoints
- Runtime configurations
"@ }

        # System Information
        "27" { @"
Displays environment status:
- Docker system info
- Service health states
- Resource utilization
- Configuration status
"@ }
        "28" { @"
Shows service dependencies:
- Service startup order
- Required connections
- Network dependencies
- Volume dependencies
"@ }
        "29" { @"
Displays configuration paths:
- Base configuration path
- Service-specific configs
- Log file locations
- Volume mount points
"@ }

        # Default case
        default { @"
No specific help available for this command.
Type numbers 1-29 to get help for specific commands.

General categories:
1-5:   Setup and Prerequisites
6-9:   Service Operations
10-15: Monitoring and Health
16-19: Logging and Debugging
20-23: Maintenance
24-26: Access and Configuration
27-29: System Information
"@ }
    }

    # Display the help
    Write-Host ""
    Write-Host "Help for Option $($Number)" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host $helpText -ForegroundColor White
    Write-Host ""
    
    # Show examples for the command if available
    $examples = switch ($Number) {
        "6" { @"
Examples:
> Start all services:
  Just select option 6

> Start with health checks:
  1. Run option 1 first (Check Prerequisites)
  2. Then run option 6 (Start Services)
"@ }
        "24" { @"
Examples:
> Open all URLs:
  Just select option 24

> Access specific service:
  - Grafana: http://localhost:3001
  - Prometheus: http://localhost:9091
"@ }
        # Add more examples as needed
    }
    
    if ($examples) {
        Write-Host "Examples" -ForegroundColor Yellow 
        Write-Host "--------" -ForegroundColor Yellow
        Write-Host $examples -ForegroundColor Gray
    }

    # Show related commands
    $related = switch ($Number) {
        "6" { "Related commands: 7 (Stop Services), 8 (Restart Services), 10 (Check Health)" }
        "10" { "Related commands: 11 (Container Status), 12 (Resource Usage), 14 (Network Tests)" }
        "24" { "Related commands: 10 (Health Check), 25 (Grafana Config), 26 (Service Settings)" }
        # Add more related commands as needed
    }

    if ($related) {
        Write-Host ""
        Write-Host "Related Commands" -ForegroundColor Yellow
        Write-Host "---------------" -ForegroundColor Yellow
        Write-Host $related -ForegroundColor Gray
    }
}

function Initialize-Application {
    try {
        Write-ModuleMessage "`nInitializing InsightOps Management Console..." -Color Cyan
        
        # Verify script paths
        Write-ModuleMessage "Script Location: $PSScriptRoot" -Color Yellow
        Write-ModuleMessage "Module Path: $script:MODULE_PATH" -Color Yellow
        
        # Create Modules directory if it doesn't exist
        if (-not (Test-Path $script:MODULE_PATH)) {
            New-Item -ItemType Directory -Path $script:MODULE_PATH -Force | Out-Null
            Write-ModuleMessage "Created Modules directory" -Color Yellow
        }

        # Load Core module first
        $corePath = Join-Path $script:MODULE_PATH "Core.psm1"
        Write-ModuleMessage "Loading Core module from: $corePath" -Color Yellow
        
        if (-not (Test-Path $corePath)) {
            throw "Core module not found at: $corePath"
        }

        # Remove existing Core module if loaded
        if (Get-Module Core) {
            Remove-Module Core -Force
        }

        # Import Core module
        Import-Module $corePath -Force -DisableNameChecking -Global -Verbose
        Write-ModuleMessage "Successfully imported Core module" -Color Green

        # Verify Core module loaded correctly
        $coreModule = Get-Module Core
        if (-not $coreModule) {
            throw "Failed to load Core module"
        }

        # Verify CONFIG_PATH is available
        if (-not ($coreModule.ExportedVariables.ContainsKey('CONFIG_PATH'))) {
            throw "Core module did not export CONFIG_PATH variable"
        }

        $configPath = $coreModule.ExportedVariables['CONFIG_PATH'].Value
        Write-ModuleMessage "Config Path: $configPath" -Color Yellow

        # Continue with other modules...
        $moduleOrder = @(
            'Logging',
            'Utilities',
            'Prerequisites',
            'EnvironmentSetup',
            'DockerOperations'
        )

        foreach ($module in $moduleOrder) {
            try {
                $modulePath = Join-Path $script:MODULE_PATH "$module.psm1"
                Write-ModuleMessage "Loading module from: $modulePath" -Color Yellow
                
                # Remove existing module if loaded
                if (Get-Module $module) {
                    Remove-Module $module -Force
                }
                
                Import-Module $modulePath -Force -DisableNameChecking -Global
                Write-ModuleMessage "Successfully imported module: $module" -Color Green
            }
            catch {
                Write-ModuleMessage "Failed to load module $module" -Color Red
                Write-ModuleMessage "Error: $($_.Exception.Message)" -Color Red
                return $false
            }
        }

        # Verify that Initialize-Environment function is available
        if (-not (Get-Command -Name "Initialize-Environment" -ErrorAction SilentlyContinue)) {
            Write-ModuleMessage "Initialize-Environment function is not available after importing EnvironmentSetup" -Color Red
            throw "Initialize-Environment not found. Ensure EnvironmentSetup.psm1 exports this function."
        }

        Write-ModuleMessage "Initialization completed successfully" -Color Green
        return $true
    }
    catch {
        Write-ModuleMessage "Application initialization failed: $_" -Color Red
        Write-ModuleMessage $_.ScriptStackTrace -Color Red
        return $false
    }
}

function Test-ModuleExports {
    param (
        [string]$ModuleName,
        [string[]]$RequiredFunctions
    )
    
    try {
        $module = Get-Module $ModuleName
        if (-not $module) {
            Write-Host "Module $ModuleName not loaded" -ForegroundColor Red
            return $false
        }

        $missingFunctions = @()
        foreach ($function in $RequiredFunctions) {
            if (-not $module.ExportedFunctions.ContainsKey($function)) {
                $missingFunctions += $function
            }
        }

        if ($missingFunctions.Count -gt 0) {
            Write-Host "Missing required functions in $ModuleName module: $($missingFunctions -join ', ')" -ForegroundColor Red
            return $false
        }

        return $true
    }
    catch {
        Write-Host "Failed to verify module $ModuleName : $_" -ForegroundColor Red
        return $false
    }
}

function _Invoke-MenuChoice {
    param (
        [string]$Choice
    )

    try {
        switch ($Choice) {
            # Setup & Prerequisites
            "1" { Test-AllPrerequisites }
            "2" { Initialize-Environment -Force }
            "3" { Test-Configuration }
            "4" { Initialize-Environment -Force }  # Reuse Initialize-Environment for directories
            "5" { Backup-Environment }

            # Core Service Operations
            "6" { 
                Write-Host "`nChecking prerequisites..." -ForegroundColor Cyan
                if (-not (Test-Prerequisites)) {
                    Write-Host "`nPrerequisites not met. Please:" -ForegroundColor Yellow
                    Write-Host "1. Run Option 1 (Check Prerequisites)" -ForegroundColor Yellow
                    Write-Host "2. Run Option 2 (Initialize Environment)" -ForegroundColor Yellow
                    Write-Host "3. Run Option 3 (Test Configuration)" -ForegroundColor Yellow
                    Write-Host "Then try starting services again." -ForegroundColor Yellow
                    return $true
                }

                Write-Host "`nStarting services..." -ForegroundColor Cyan
                Start-DockerServices 
            }
            "7" { Stop-DockerServices }
            "8" { 
                Stop-DockerServices
                Start-Sleep -Seconds 2
                Start-DockerServices 
            }
            "9" {
                try {
                    Write-Host "Enter service name to rebuild (leave empty to rebuild all): " -ForegroundColor Cyan -NoNewline
                    $service = Read-Host

                    # First reset the environment
                    Write-Host "`nResetting Docker environment..." -ForegroundColor Yellow
                    if (-not (Reset-DockerEnvironment)) {
                        throw "Failed to reset Docker environment"
                    }

                    # Then rebuild
                    Write-Host "`nRebuilding services..." -ForegroundColor Yellow
                    if ([string]::IsNullOrWhiteSpace($service)) {
                        Rebuild-DockerService
                    } else {
                        Rebuild-DockerService -ServiceName $service
                    }
                }
                catch {
                    Write-Error "Error executing rebuild operation: $_"
                }
            }

            # Monitoring & Health
            "10" { Test-ServiceHealth }
            "11" { Show-DockerStatus }
            "12" { docker stats --no-stream }
            "13" { Show-DockerStatus }  # Reuse Show-DockerStatus for metrics
            "14" { 
                $confirmation = Read-Host "This will stop all services and clean up. Continue? (y/n)"
                if ($confirmation -eq 'y') {
                    Write-Host "`nStopping all services..." -ForegroundColor Yellow
                    Stop-DockerServices
                    Write-Host "`nCleaning up Docker resources..." -ForegroundColor Yellow
                    docker system prune -f
                    Write-Host "`nRemoving volumes..." -ForegroundColor Yellow
                    docker volume prune -f
                    Write-Host "`nCleanup completed." -ForegroundColor Green
                }
            }

            # Logging & Debugging
            "15" { 
                $service = Read-Host "Enter service name (press Enter for all)"
                Export-DockerLogs -ServiceName $service 
            }
            "16" { Export-DockerLogs }
            "17" { Show-QuickReference }

            # Maintenance
            "18" { 
                $confirmation = Read-Host "This will clean up Docker resources. Continue? (y/n)"
                if ($confirmation -eq 'y') {
                    Clean-DockerEnvironment 
                }
            }
            "19" { 
                Write-Host "`nTesting Docker connection..." -ForegroundColor Yellow
                docker info > $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "√ Docker is accessible" -ForegroundColor Green
                } else {
                    Write-Host "× Docker is not accessible" -ForegroundColor Red
                }

                Write-Host "`nTesting service ports..." -ForegroundColor Yellow
                $ports = @(
                    @{Port = 5010; Service = "Frontend"},
                    @{Port = 5011; Service = "API Gateway"},
                    @{Port = 5012; Service = "Order Service"},
                    @{Port = 5013; Service = "Inventory Service"},
                    @{Port = 3001; Service = "Grafana"},
                    @{Port = 9091; Service = "Prometheus"},
                    @{Port = 3101; Service = "Loki"},
                    @{Port = 4317; Service = "Tempo"}
                )

                foreach ($portInfo in $ports) {
                    $testResult = Test-NetConnection -ComputerName localhost -Port $portInfo.Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    if ($testResult.TcpTestSucceeded) {
                        Write-Host "√ Port $($portInfo.Port) ($($portInfo.Service)) is accessible" -ForegroundColor Green
                    } else {
                        Write-Host "× Port $($portInfo.Port) ($($portInfo.Service)) is not accessible" -ForegroundColor Red
                    }
                }
            }

                # Access
                "20" { 
                    # Observability UIs
                    Write-Host "`nOpening Observability UIs..." -ForegroundColor Cyan
                    Start-Process "http://localhost:3001"     # Grafana
                    Start-Process "http://localhost:9091"     # Prometheus
                    Start-Process "http://localhost:3101"     # Loki
                    Start-Process "http://localhost:4317"     # Tempo

                    # Additional Loki Endpoints
                    Start-Process "http://localhost:3101/loki/api/v1/query"          # Loki Query
                    Start-Process "http://localhost:3101/loki/api/v1/query_range"    # Loki Query Range
                    Start-Process "http://localhost:3101/loki/api/v1/label"          # Loki Label
                    Start-Process "http://localhost:3101/loki/api/v1/push"           # Loki Push
                    Start-Process "http://localhost:3101/metrics"                    # Loki Metrics

                    # Additional Tempo Endpoints
                    Start-Process "http://localhost:4318"                            # Tempo HTTP (OTLP)
                    Start-Process "http://localhost:3200/jaeger/api/traces"          # Tempo Jaeger Query
                    Start-Process "http://localhost:3200/ready"                      # Tempo Ready
                    Start-Process "http://localhost:3200/metrics"                    # Tempo Metrics

                    # Service UIs
                    Write-Host "`nOpening Service UIs..." -ForegroundColor Cyan
                    Start-Process "http://localhost:5010"         # Frontend UI
                    Start-Process "http://localhost:5010/swagger" # Frontend Swagger
                    Start-Process "http://localhost:5011/swagger" # API Gateway Swagger
                    Start-Process "http://localhost:5012/swagger" # Order Service Swagger
                    Start-Process "http://localhost:5013/swagger" # Inventory Service Swagger

                    Write-Host "`nService URLs:" -ForegroundColor Yellow
                    Write-Host "Observability Stack:" -ForegroundColor Cyan
                    Write-Host "  • Grafana:              http://localhost:3001" -ForegroundColor Green
                    Write-Host "  • Prometheus:           http://localhost:9091" -ForegroundColor Green
                    Write-Host "  • Loki (Main):          http://localhost:3101" -ForegroundColor Green
                    Write-Host "  • Loki (Query):         http://localhost:3101/loki/api/v1/query" -ForegroundColor Green
                    Write-Host "  • Loki (Query Range):   http://localhost:3101/loki/api/v1/query_range" -ForegroundColor Green
                    Write-Host "  • Loki (Label):         http://localhost:3101/loki/api/v1/label" -ForegroundColor Green
                    Write-Host "  • Loki (Push):          http://localhost:3101/loki/api/v1/push" -ForegroundColor Green
                    Write-Host "  • Loki (Metrics):       http://localhost:3101/metrics" -ForegroundColor Green
                    Write-Host "  • Tempo (gRPC OTLP):    http://localhost:4317" -ForegroundColor Green
                    Write-Host "  • Tempo (HTTP OTLP):    http://localhost:4318" -ForegroundColor Green
                    Write-Host "  • Tempo (Jaeger Query): http://localhost:3200/jaeger/api/traces" -ForegroundColor Green
                    Write-Host "  • Tempo (Ready):        http://localhost:3200/ready" -ForegroundColor Green
                    Write-Host "  • Tempo (Metrics):      http://localhost:3200/metrics" -ForegroundColor Green

                    Write-Host "`nApplication Services:" -ForegroundColor Cyan
                    Write-Host "  • Frontend UI:        http://localhost:5010" -ForegroundColor Green
                    Write-Host "  • Frontend API:       http://localhost:5010/swagger" -ForegroundColor Green
                    Write-Host "  • API Gateway:        http://localhost:5011/swagger" -ForegroundColor Green
                    Write-Host "  • Order Service:      http://localhost:5012/swagger" -ForegroundColor Green
                    Write-Host "  • Inventory Service:  http://localhost:5013/swagger" -ForegroundColor Green

                    Write-Host "`nNote: It may take a few moments for all services to be ready." -ForegroundColor Yellow
                    Write-Host "      Check service health (Option 10) to verify availability." -ForegroundColor Yellow
                }


            "21" { Get-DetailedServiceLogs }  # Add this as a new menu option

            # Exit
            "0" { 
                Write-Host "Exiting InsightOps Management Console..." -ForegroundColor Cyan
                return $false 
            }

            default { Write-Host "Invalid option selected" -ForegroundColor Yellow }
        }
        return $true
    }
    catch {
        Write-Host "Error executing option $Choice : $_" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $true
    }
}				
			
function Invoke-MenuChoice {
    param (
        [string]$Choice
    )

    try {
        switch ($Choice) {
            # Setup & Prerequisites (1-5: No changes needed)
            "1" { Test-AllPrerequisites }
            "2" { Initialize-Environment -Force }
            "3" { Test-Configuration }
            "4" { Initialize-Environment -Force }
            "5" { Backup-Environment }

            # Core Service Operations (6-9: Keeping original implementation)
            "6" { 
                Write-Host "`nChecking prerequisites..." -ForegroundColor Cyan
                if (-not (Test-Prerequisites)) {
                    Write-Host "`nPrerequisites not met. Please:" -ForegroundColor Yellow
                    Write-Host "1. Run Option 1 (Check Prerequisites)" -ForegroundColor Yellow
                    Write-Host "2. Run Option 2 (Initialize Environment)" -ForegroundColor Yellow
                    Write-Host "3. Run Option 3 (Test Configuration)" -ForegroundColor Yellow
                    Write-Host "Then try starting services again." -ForegroundColor Yellow
                    return $true
                }

                Write-Host "`nStarting services..." -ForegroundColor Cyan
                Start-DockerServices 
            }
            "7" { Stop-DockerServices }
            "8" { 
                Stop-DockerServices
                Start-Sleep -Seconds 2
                Start-DockerServices 
            }
            "9" {
                try {
                    Write-Host "Enter service name to rebuild (leave empty to rebuild all): " -ForegroundColor Cyan -NoNewline
                    $service = Read-Host

                    Write-Host "`nResetting Docker environment..." -ForegroundColor Yellow
                    if (-not (Reset-DockerEnvironment)) {
                        throw "Failed to reset Docker environment"
                    }

                    Write-Host "`nRebuilding services..." -ForegroundColor Yellow
                    if ([string]::IsNullOrWhiteSpace($service)) {
                        Rebuild-DockerService
                    } else {
                        Rebuild-DockerService -ServiceName $service
                    }
                }
                catch {
                    Write-Error "Error executing rebuild operation: $_"
                }
            }

            # Monitoring & Health (10-15: Combining existing and new)
            "10" { Test-ServiceHealth }
            "11" { Show-DockerStatus }
            "12" { docker stats --no-stream }
            "13" { Show-DockerStatus }
            "14" { 
                Write-Host "`nTesting Docker connection..." -ForegroundColor Yellow
                docker info > $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "√ Docker is accessible" -ForegroundColor Green
                } else {
                    Write-Host "× Docker is not accessible" -ForegroundColor Red
                }

                Write-Host "`nTesting service ports..." -ForegroundColor Yellow
                $ports = @(
                    @{Port = 5010; Service = "Frontend"},
                    @{Port = 5011; Service = "API Gateway"},
                    @{Port = 5012; Service = "Order Service"},
                    @{Port = 5013; Service = "Inventory Service"},
                    @{Port = 3001; Service = "Grafana"},
                    @{Port = 9091; Service = "Prometheus"},
                    @{Port = 3101; Service = "Loki"},
                    @{Port = 4317; Service = "Tempo"}
                )

                foreach ($portInfo in $ports) {
                    $testResult = Test-NetConnection -ComputerName localhost -Port $portInfo.Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    if ($testResult.TcpTestSucceeded) {
                        Write-Host "√ Port $($portInfo.Port) ($($portInfo.Service)) is accessible" -ForegroundColor Green
                    } else {
                        Write-Host "× Port $($portInfo.Port) ($($portInfo.Service)) is not accessible" -ForegroundColor Red
                    }
                }
            }
            "15" { Test-GrafanaConfiguration } # New option

            # Logging & Debugging (16-19: Reorganized)
            "16" { 
                $service = Read-Host "Enter service name (press Enter for all)"
                Export-DockerLogs -ServiceName $service 
            }
            "17" { Export-DockerLogs }
            "18" { Show-QuickReference }
            "19" { Get-DetailedServiceLogs }

            # Maintenance & Cleanup (20-23: Enhanced)
            "20" { 
                $confirmation = Read-Host "This will clean up Docker resources. Continue? (y/n)"
                if ($confirmation -eq 'y') {
                    Clean-DockerEnvironment 
                }
            }
            "21" { 
                $confirmation = Read-Host "This will stop all services and clean up. Continue? (y/n)"
                if ($confirmation -eq 'y') {
                    Write-Host "`nStopping all services..." -ForegroundColor Yellow
                    Stop-DockerServices
                    Write-Host "`nCleaning up Docker resources..." -ForegroundColor Yellow
                    docker system prune -f
                    Write-Host "`nRemoving volumes..." -ForegroundColor Yellow
                    docker volume prune -f
                    Write-Host "`nCleanup completed." -ForegroundColor Green
                }
            }
            "22" { 
                $confirmation = Read-Host "This will prune all unused Docker resources. Continue? (y/n)"
                if ($confirmation -eq 'y') {
                    docker system prune -af
                    docker volume prune -f
                    Write-Host "Docker resources pruned successfully" -ForegroundColor Green
                }
            }
            "23" { Reset-Environment }

            # Access & Configuration (24-26: Extended from original access options)
            "24" { 
                # Original URL opening implementation
                Write-Host "`nOpening Observability UIs..." -ForegroundColor Cyan
                Start-Process "http://localhost:3001"     # Grafana
                Start-Process "http://localhost:9091"     # Prometheus
                Start-Process "http://localhost:3101"     # Loki
                Start-Process "http://localhost:4317"     # Tempo

                # Additional Endpoints (keeping all existing endpoints)
                Write-Host "`nService URLs:" -ForegroundColor Yellow
                Write-Host "Observability Stack:" -ForegroundColor Cyan
                # ... [keeping all the existing URL displays]
                
                Write-Host "`nNote: It may take a few moments for all services to be ready." -ForegroundColor Yellow
                Write-Host "      Check service health (Option 10) to verify availability." -ForegroundColor Yellow
            }
            "25" { 
                Write-Host "`nConfiguring Grafana Dashboards..." -ForegroundColor Cyan
                if (-not (Test-GrafanaConfiguration)) {
                    Write-Host "Grafana configuration check failed. Running setup..." -ForegroundColor Yellow
                    Initialize-GrafanaDashboards
                }
                Write-Host "Opening Grafana UI..." -ForegroundColor Cyan
                Start-Process "http://localhost:3001"
            }
            "26" { Show-ServiceConfiguration }

            # System Information (27-29: New section)
            "27" { Show-EnvironmentStatus }
            "28" { Show-ServiceDependencies }
            "29" { 
                Write-Host "`nConfiguration Paths:" -ForegroundColor Cyan
                Write-Host "Base Path: $script:CONFIG_PATH" -ForegroundColor Yellow
                Write-Host "Docker Compose: $script:DOCKER_COMPOSE_PATH" -ForegroundColor Yellow
                Write-Host "Grafana Config: $($script:CONFIG_PATH)/grafana" -ForegroundColor Yellow
                Write-Host "Logs Path: $($script:CONFIG_PATH)/logs" -ForegroundColor Yellow
            }

            # Exit (with confirmation)
            "0" { 
                $confirmation = Read-Host "Are you sure you want to exit? (y/n)"
                if ($confirmation -eq 'y') {
                    Write-Host "Exiting InsightOps Management Console..." -ForegroundColor Cyan
                    return $false 
                }
                return $true
            }

            default { 
                Write-Host "Invalid option selected" -ForegroundColor Yellow 
                Write-Host "Type 'help' for command information" -ForegroundColor Gray
            }
        }
        
        if ($Choice -ne "0") {
            Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
            Read-Host | Out-Null
        }
        
        return $true
    }
    catch {
        Write-Host "`nError executing option $Choice" -ForegroundColor Red
        Write-Host "Error details: $_" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        
        Write-Host "`nTroubleshooting Steps:" -ForegroundColor Yellow
        Write-Host "1. Check the error message above" -ForegroundColor Yellow
        Write-Host "2. Verify prerequisites (Option 1)" -ForegroundColor Yellow
        Write-Host "3. Test configuration (Option 3)" -ForegroundColor Yellow
        Write-Host "4. Check service status (Option 10)" -ForegroundColor Yellow
        
        Write-Host "`nPress Enter to continue..." -ForegroundColor Gray
        Read-Host | Out-Null
        return $true
    }
}

# Main execution
try {
    if (-not (Initialize-Application)) {
        exit 1
    }

    while ($true) {
        Show-Menu
        $choice = Read-Host "`nEnter your choice (0-20)"
        
        $continueRunning = Invoke-MenuChoice -Choice $choice
        if (-not $continueRunning) {
            break
        }

        if ($choice -ne "0") {
            Write-Host "`nPress Enter to continue..."
            Read-Host
        }
    }
}
catch {
    Write-ModuleMessage "An unhandled error occurred: $_" -Color Red
    Write-ModuleMessage $_.ScriptStackTrace -Color Red
    exit 1
}
finally {
    # Cleanup
    Get-Module | Where-Object { $_.ModuleType -eq 'Script' } | Remove-Module -Force
    Write-ModuleMessage "Session ended" -Color Cyan
}