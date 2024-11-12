# main.ps1
# Purpose: Main entry point for InsightOps management script

$ErrorActionPreference = "Stop"
$script:BASE_PATH = $PSScriptRoot
$script:MODULE_PATH = Join-Path $BASE_PATH "Modules"

# Helper function to check prerequisites before starting services
function Test-Prerequisites {
    [CmdletBinding()]
    param()
    
    try {
        # Check Docker is running
        $dockerStatus = docker info 2>&1
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
    Write-Host "`nInsightOps Management Console" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    
    # System Setup & Prerequisites
    Write-Host "`nSetup & Prerequisites:" -ForegroundColor Yellow
    Write-Host "1.  Check Prerequisites"
    Write-Host "2.  Initialize Environment"
    Write-Host "3.  Test Configuration"
    Write-Host "4.  Initialize Required Directories"
    Write-Host "5.  Backup Configuration"

    # Core Service Operations
    Write-Host "`nService Operations:" -ForegroundColor Yellow
    Write-Host "6.  Start Services"
    Write-Host "7.  Stop Services"
    Write-Host "8.  Restart Services"
    Write-Host "9.  Rebuild Service"

    # Monitoring & Health
    Write-Host "`nMonitoring & Health:" -ForegroundColor Yellow
    Write-Host "10. Check Service Health"
    Write-Host "11. Show Container Status"
    Write-Host "12. View Resource Usage"
    Write-Host "13. View System Metrics"
    Write-Host "14. Test Network Connectivity"

    # Logging & Debugging
    Write-Host "`nLogging & Debugging:" -ForegroundColor Yellow
    Write-Host "15. View Service Logs"
    Write-Host "16. Export Container Logs"
    Write-Host "17. Show Quick Reference"

    # Maintenance
    Write-Host "`nMaintenance:" -ForegroundColor Yellow
    Write-Host "18. Clean Docker System"
    Write-Host "19. Run Cleanup Tasks"

    # Access
    Write-Host "`nAccess:" -ForegroundColor Yellow
    Write-Host "20. Open Service URLs"
    
    Write-Host "`n0.  Exit" -ForegroundColor Red
    Write-Host "=========================" -ForegroundColor Cyan
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

        # Define module loading order
        $moduleOrder = @(
            'Core',
            'Logging',
            'Utilities',
            'Prerequisites',
            'EnvironmentSetup',
            'DockerOperations'
        )

        # Load all modules
        foreach ($module in $moduleOrder) {
            try {
                $modulePath = Join-Path $script:MODULE_PATH "$module.psm1"
                Write-ModuleMessage "Loading module from: $modulePath" -Color Yellow
                
                if (-not (Test-Path $modulePath)) {
                    throw "Module file not found: $modulePath"
                }

                # Remove existing module if loaded
                if (Get-Module $module) {
                    Remove-Module $module -Force
                }

                # Import the module
                Import-Module $modulePath -Force -DisableNameChecking -Global
                Write-ModuleMessage "Successfully imported module: $module" -Color Green
            }
            catch {
                Write-ModuleMessage "Failed to load module $module" -Color Red
                Write-ModuleMessage "Error: $($_.Exception.Message)" -Color Red
                return $false
            }
        }

        Write-ModuleMessage "Initialization completed successfully" -Color Green
        return $true
    }
    catch {
        Write-ModuleMessage "Application initialization failed: $_" -Color Red
        return $false
    }
}

function _Initialize-Application {
    try {
        Write-ModuleMessage "`nInitializing InsightOps Management Console..." -Color Cyan

        # Create Modules directory if it doesn't exist
        if (-not (Test-Path $script:MODULE_PATH)) {
            New-Item -ItemType Directory -Path $script:MODULE_PATH -Force | Out-Null
            Write-ModuleMessage "Created Modules directory" -Color Yellow
        }

        # Define module loading order - Core must be first
        $moduleOrder = @(
            'Core',              # Must be first as others depend on it
            'Logging',
            'Utilities',
            'Prerequisites',
            'EnvironmentSetup',  # Needs Core to be loaded first
            'DockerOperations'
        )

        # Define required functions for each module
        $requiredExports = @{
            'Core' = @('Test-Configuration', 'Initialize-DefaultConfigurations')
            'Logging' = @('Write-Info', 'Write-Success', 'Write-Warning', 'Write-Error')
            'EnvironmentSetup' = @('Initialize-Environment', 'Set-EnvironmentConfig')
            'Prerequisites' = @('Test-AllPrerequisites')
            'DockerOperations' = @('Initialize-DockerEnvironment', 'Start-DockerServices', 'Stop-DockerServices')
        }

        # Load all modules
        $loadedModules = @()
        foreach ($module in $moduleOrder) {
            try {
                $modulePath = Join-Path $script:MODULE_PATH "$module.psm1"
                
                if (-not (Test-Path $modulePath)) {
                    throw "Module file not found: $modulePath"
                }

                # Remove existing module if loaded
                if (Get-Module $module) {
                    Remove-Module $module -Force -ErrorAction Stop
                }

                # Import the module
                Import-Module $modulePath -Force -DisableNameChecking -Global -ErrorAction Stop
                Write-ModuleMessage "Successfully imported module: $module" -Color Green
                
                # Verify required functions are exported
                if ($requiredExports.ContainsKey($module)) {
                    $module = Get-Module $module
                    foreach ($requiredFunction in $requiredExports[$module]) {
                        if (-not $module.ExportedFunctions.ContainsKey($requiredFunction)) {
                            throw "Required function '$requiredFunction' not exported from module '$module'"
                        }
                    }
                }
                
                $loadedModules += $module
            }
            catch {
                Write-ModuleMessage "Critical error loading $module" -Color Red
                Write-ModuleMessage $_.Exception.Message -Color Red
                Write-ModuleMessage $_.ScriptStackTrace -Color Red
                
                # Unload modules in reverse order
                [array]::Reverse($loadedModules)
                foreach ($loadedModule in $loadedModules) {
                    try {
                        Remove-Module $loadedModule -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        Write-ModuleMessage "Failed to unload module $loadedModule" -Color Yellow
                    }
                }
                return $false
            }
        }

        # Initialize configurations
        try {
            Write-ModuleMessage "Checking configuration..." -Color Cyan
            
            # Verify Core module functions are available
            $coreModule = Get-Module Core
            if (-not $coreModule) {
                throw "Core module not loaded"
            }

            # Check configuration
            $testConfig = $coreModule.ExportedFunctions['Test-Configuration']
            if (-not $testConfig) {
                throw "Test-Configuration function not available"
            }

            if (-not (& $testConfig)) {
                Write-ModuleMessage "Creating default configurations..." -Color Yellow
                $initConfig = $coreModule.ExportedFunctions['Initialize-DefaultConfigurations']
                if (-not $initConfig) {
                    throw "Initialize-DefaultConfigurations function not available"
                }
                if (-not (& $initConfig)) {
                    throw "Failed to create default configurations"
                }
            }

            # Initialize Docker environment
            $dockerModule = Get-Module DockerOperations
            if (-not $dockerModule) {
                throw "DockerOperations module not loaded"
            }

            $initDocker = $dockerModule.ExportedFunctions['Initialize-DockerEnvironment']
            if (-not $initDocker) {
                throw "Initialize-DockerEnvironment function not available"
            }

            if (-not (& $initDocker)) {
                throw "Failed to initialize Docker environment"
            }

            Write-ModuleMessage "Initialization completed successfully" -Color Green
            return $true
        }
        catch {
            Write-ModuleMessage "Initialization failed: $_" -Color Red
            Write-ModuleMessage $_.ScriptStackTrace -Color Red
            return $false
        }
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

function Invoke-MenuChoice {
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
                if (-not (Test-Prerequisites)) {
                    Write-Host "Prerequisites not met. Please run option 1 first." -ForegroundColor Red
                    return $true
                }
                Start-DockerServices 
            }
            "7" { Stop-DockerServices }
            "8" { 
                Stop-DockerServices
                Start-Sleep -Seconds 2
                Start-DockerServices 
            }
            "9" {
                $service = Read-Host "Enter service name to rebuild"
                Restart-DockerService -ServiceName $service
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

                # Service UIs
                Write-Host "`nOpening Service UIs..." -ForegroundColor Cyan
                Start-Process "http://localhost:5010"         # Frontend UI
                Start-Process "http://localhost:5010/swagger" # Frontend Swagger
                Start-Process "http://localhost:5011/swagger" # API Gateway Swagger
                Start-Process "http://localhost:5012/swagger" # Order Service Swagger
                Start-Process "http://localhost:5013/swagger" # Inventory Service Swagger

                Write-Host "`nService URLs:" -ForegroundColor Yellow
                Write-Host "Observability Stack:" -ForegroundColor Cyan
                Write-Host "  • Grafana:    http://localhost:3001" -ForegroundColor Green
                Write-Host "  • Prometheus: http://localhost:9091" -ForegroundColor Green
                Write-Host "  • Loki:       http://localhost:3101" -ForegroundColor Green
                Write-Host "  • Tempo:      http://localhost:4317" -ForegroundColor Green

                Write-Host "`nApplication Services:" -ForegroundColor Cyan
                Write-Host "  • Frontend UI:        http://localhost:5010" -ForegroundColor Green
                Write-Host "  • Frontend API:       http://localhost:5010/swagger" -ForegroundColor Green
                Write-Host "  • API Gateway:        http://localhost:5011/swagger" -ForegroundColor Green
                Write-Host "  • Order Service:      http://localhost:5012/swagger" -ForegroundColor Green
                Write-Host "  • Inventory Service:  http://localhost:5013/swagger" -ForegroundColor Green

                Write-Host "`nNote: It may take a few moments for all services to be ready." -ForegroundColor Yellow
                Write-Host "      Check service health (Option 10) to verify availability." -ForegroundColor Yellow
            }

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