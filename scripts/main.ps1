# main.ps1
# Purpose: Main entry point for InsightOps management script

$ErrorActionPreference = "Stop"
$script:BASE_PATH = $PSScriptRoot
$script:MODULE_PATH = Join-Path $BASE_PATH "Modules"

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
    Write-Host "1.  Start Services"
    Write-Host "2.  Stop Services"
    Write-Host "3.  Show Container Status"
    Write-Host "4.  View Service Logs"
    Write-Host "5.  View Resource Usage"
    Write-Host "6.  Rebuild Service"
    Write-Host "7.  Clean Docker System"
    Write-Host "8.  Show Quick Reference"
    Write-Host "9.  Open Service URLs"
    Write-Host "10. Check Service Health"
    Write-Host "11. Show Resource Usage"
    Write-Host "12. Initialize Environment"
    Write-Host "13. Check Prerequisites"
    Write-Host "14. Run Cleanup Tasks"
    Write-Host "15. View System Metrics"
    Write-Host "16. Export Container Logs"
    Write-Host "17. Backup Configuration"
    Write-Host "18. Test Configuration"
    Write-Host "19. Test Network Connectivity"
    Write-Host "20. Initialize Required Directories"
    Write-Host "0.  Exit"
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
            "0" { 
                Write-ModuleMessage "Exiting InsightOps Management Console..." -Color Cyan
                return $false 
            }
            "1" { Start-DockerServices }
            "2" { Stop-DockerServices }
            "3" { Show-DockerStatus }
            "4" { 
                $service = Read-Host "Enter service name (or press Enter for all)"
                Export-DockerLogs -ServiceName $service 
            }
            "5" { docker stats --no-stream }
            "6" {
                $service = Read-Host "Enter service name to rebuild"
                Restart-DockerService -ServiceName $service
            }
            "7" { Clean-DockerEnvironment }
            "8" { Show-QuickReference }
            "9" { Open-ServiceUrls }
            # For option 10 (Check Service Health):
			"10" { 
				Test-NetworkConnectivity
				Test-ServiceHealth
				Test-ContainerHealth 
			}
            "11" { Show-DockerStatus }
            "12" { Initialize-Environment -Force }
            "13" { Test-AllPrerequisites }
            "14" { Clean-DockerEnvironment -RemoveVolumes }
            "15" { Show-DockerStatus }
            "16" { Export-DockerLogs }
            "17" { Backup-Environment }
            "18" { Test-Configuration }
			# For option 19 (Test Network Connectivity):
			"19" { Test-NetworkConnectivity }
            "20" { Initialize-Environment }
            default { Write-ModuleMessage "Invalid option selected" -Color Yellow }
        }
        return $true
    }
    catch {
        Write-ModuleMessage "Error executing option $Choice : $_" -Color Red
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