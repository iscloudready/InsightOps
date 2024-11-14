# Stop-TempoTest.ps1
$ErrorActionPreference = "Stop"

# Import required modules
$modulePath = Join-Path $PSScriptRoot "..\\Modules"
Import-Module "$modulePath\\DockerCleanup.psm1" -Force
Import-Module "$modulePath\\TempoValidation.psm1" -Force
Import-Module "$modulePath\\TempoTest.psm1" -Force

# Logging function for output
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp : $Message" -ForegroundColor $Color
}

# Main function to stop the Tempo test environment
function Stop-TempoTestEnvironment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$TestDirectory = "D:\\tempo-test",

        [Parameter(Mandatory = $false)]
        [switch]$NoPrune  # Optional switch to skip Docker prune if needed
    )

    try {
        Write-Log "Stopping Tempo test environment..." -Color Cyan

        # Stop containers and remove resources
        if (Test-DockerRunning) {
            Write-Log "Stopping and removing containers..." -Color Yellow
            Stop-ProjectContainers -ProjectPattern "tempo"

            Write-Log "Removing volumes..." -Color Yellow
            Remove-ProjectVolumes -ProjectPattern "tempo"

            Write-Log "Removing networks..." -Color Yellow
            Remove-ProjectNetworks -ProjectPattern "tempo"
        }

        # Perform Docker prune if NoPrune is not set
        if (-not $NoPrune) {
            Write-Log "Performing system-wide Docker prune..." -Color Yellow
            $pruned = Remove-DockerResources -Force
            if (-not $pruned) {
                throw "System-wide Docker prune encountered issues."
            }
        }

        # Optionally remove the test directory
        if (Test-Path $TestDirectory) {
            Write-Log "Cleaning up test directory: $TestDirectory" -Color Yellow
            Remove-ProjectDirectory -DirectoryPath $TestDirectory -Force
        }

        Write-Log "Tempo test environment stopped and cleaned successfully." -Color Green
        return $true
    }
    catch {
        Write-Log "Failed to stop the Tempo test environment: $_" -Color Red
        Write-Log $_.ScriptStackTrace -Color Red
        return $false
    }
}

# Execute the stop environment function with parameters from config.json
Stop-TempoTestEnvironment @PSBoundParameters