# Check if running in PowerShell 7, and if not, relaunch with PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $ps7Path = "C:\Program Files\PowerShell\7\pwsh.exe"
    if (Test-Path $ps7Path) {
        Write-Output "Switching to PowerShell 7 to execute the script..."
        & "$ps7Path" -File $MyInvocation.MyCommand.Path @args
        exit
    } else {
        Write-Output "PowerShell 7 is not installed. Please install PowerShell 7 to continue."
        exit 1
    }
}

#Requires -Version 7.0
#Requires -RunAsAdministrator

# InsightOps Docker Management Script
using namespace System.Management.Automation
using namespace System.Collections.Generic
using namespace System.Diagnostics

param (
    [Parameter()]
    [string]$Environment = "Development",
    [switch]$Force,
    [switch]$Verbose
)

# Import dependent modules
$scriptPath = $PSScriptRoot
$modulesPath = Join-Path $scriptPath "modules"

# Import all module files
@(
    "Core.ps1",
    "Configuration.ps1",
    "Environment.ps1",
    "Services.ps1",
    "Monitoring.ps1",
    "Logging.ps1",
    "Security.ps1",
    "Network.ps1",
    "Backup.ps1",
    "Health.ps1",
    "Utils.ps1"
) | ForEach-Object {
    $modulePath = Join-Path $modulesPath $_
    if (Test-Path $modulePath) {
        . $modulePath
    }
    else {
        throw "Required module not found: $_"
    }
}

# Script Configuration
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$VerbosePreference = $Verbose ? "Continue" : "SilentlyContinue"

# Initialize Logging
Initialize-Logging

# Script Start
try {
    Write-Log "Starting InsightOps Docker Management Script"
    Write-Log "Environment: $Environment"
    
    # Validate Environment
    if (-not (Test-Environment)) {
        throw "Environment validation failed"
    }

    # Initialize Configuration
    Initialize-Configuration

    # Verify Prerequisites
    if (-not (Test-Prerequisites)) {
        throw "Prerequisites check failed"
    }

    # Main Menu Loop
    while ($true) {
        Clear-Host
        Show-Header
        Show-Menu
        
        try {
            $choice = Read-Host "`nEnter your choice (0-20)"
            
            switch ($choice) {
                # Environment Management
                0 { exit }
                1 { Initialize-InsightOpsEnvironment -Force:$Force }
                2 { Reset-InsightOpsEnvironment -Backup:$true }
                3 { Switch-Environment }
                
                # Service Management
                4 { Start-Services }
                5 { Stop-Services }
                6 { Show-ContainerStatus }
                7 { 
                    $serviceName = Get-ServiceSelection
                    Show-Logs $serviceName
                }
                8 { Show-ResourceUsage }
                9 { 
                    $serviceName = Get-ServiceSelection
                    Rebuild-Service $serviceName
                }
                10 { Clean-DockerSystem }
                
                # Monitoring & Access
                11 { Open-ServiceUrls }
                12 { Check-ServiceHealth }
                13 { Show-DetailedMetrics }
                14 { Export-ContainerLogs }
                
                # Security & Maintenance
                15 { Backup-Configuration }
                16 { Restore-Configuration }
                17 { Test-SecurityCompliance }
                18 { Show-NetworkStatus }
                
                # Advanced Options
                19 { Show-AdvancedOptions }
                20 { Show-Documentation }
                
                default { 
                    Write-Warning "Invalid option selected"
                }
            }
            
            if ($choice -ne 0) {
                Write-Host "`nOperation completed. Press Enter to continue..."
                Read-Host
            }
        }
        catch {
            Write-Error "An error occurred: $_"
            Write-Log "Error in main menu: $_" -Level Error
            Write-Host "Press Enter to continue..."
            Read-Host
        }
    }
}
catch {
    Write-Error "Fatal error occurred: $_"
    Write-Log "Fatal error: $_" -Level Error
    exit 1
}
finally {
    # Cleanup
    Write-Log "Script execution completed"
}