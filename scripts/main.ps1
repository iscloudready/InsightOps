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

        # Create Modules directory if it doesn't exist
        if (-not (Test-Path $script:MODULE_PATH)) {
            New-Item -ItemType Directory -Path $script:MODULE_PATH -Force | Out-Null
            Write-ModuleMessage "Created Modules directory" -Color Yellow
        }

        # Define module loading order
        $moduleOrder = @(
            'Logging',
            'Utilities',
            'Core',
            'Prerequisites',
            'EnvironmentSetup',
            'DockerOperations'
        )

        # Load all modules
        $loadedModules = @()
        foreach ($module in $moduleOrder) {
            try {
                $success = Import-ModuleSafely -ModuleName $module -Required
                if ($success) {
                    $loadedModules += $module
                }
                else {
                    throw "Failed to load required module: $module"
                }
            }
            catch {
                Write-ModuleMessage "Critical error loading $module : $_" -Color Red
                # Unload modules in reverse order
                [array]::Reverse($loadedModules)
                foreach ($loadedModule in $loadedModules) {
                    Remove-ModuleSafely $loadedModule
                }
                return $false
            }
        }

        try {
            Write-ModuleMessage "Checking configuration..." -Color Cyan
            
            # Check and initialize configuration
            if (-not (Test-Configuration)) {
                Write-ModuleMessage "Creating default configurations..." -Color Yellow
                if (-not (Initialize-DefaultConfigurations)) {
                    throw "Failed to create default configurations"
                }
            }

            # Initialize Docker environment
            if (-not (Initialize-DockerEnvironment)) {
                throw "Failed to initialize Docker environment"
            }

            Write-ModuleMessage "Initialization completed successfully" -Color Green
            return $true
        }
        catch {
            Write-ModuleMessage "Initialization failed: $_" -Color Red
            return $false
        }
    }
    catch {
        Write-ModuleMessage "Application initialization failed: $_" -Color Red
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
            "4" { Initialize-RequiredDirectories }
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
            "13" { Show-SystemMetrics }
            "14" { Test-NetworkConnectivity }

            # Logging & Debugging
            "15" { 
                $service = Read-Host "Enter service name (press Enter for all)"
                View-ServiceLogs -ServiceName $service 
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
                $confirmation = Read-Host "This will perform cleanup tasks. Continue? (y/n)"
                if ($confirmation -eq 'y') {
                    Clean-DockerEnvironment -RemoveVolumes 
                }
            }

            # Access
            "20" { Open-ServiceUrls }

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