# Start-TempoTest.ps1
$ErrorActionPreference = "Stop"

# Import required modules
$modulePath = Join-Path $PSScriptRoot "\\Modules"
Import-Module "$modulePath\\DockerCleanup.psm1" -Force
Import-Module "$modulePath\\TempoValidation.psm1" -Force
Import-Module "$modulePath\\TempoTest.psm1" -Force

# Logging function for output
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp : $Message" -ForegroundColor $Color
}

# Main function to start the Tempo test sequence
function Start-TempoTestSequence {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$TestDirectory = "D:\\tempo-test",

        [Parameter(Mandatory = $false)]
        [switch]$SkipValidation,

        [Parameter(Mandatory = $false)]
        [switch]$NoCleanup
    )

    try {
        Write-Log "Starting Tempo test sequence..." -Color Cyan

        # Initial cleanup
        if (-not $NoCleanup) {
            Write-Log "Performing initial cleanup..." -Color Yellow
            Stop-ProjectContainers -ProjectPattern "tempo"
            Remove-ProjectVolumes -ProjectPattern "tempo"
            Remove-ProjectNetworks -ProjectPattern "tempo"
        }

        # Initialize environment
        $initialized = Start-TempoTestEnvironment -TestDirectory $TestDirectory
        if (-not $initialized) {
            throw "Failed to initialize test environment"
        }

        # Start Tempo container (remove ContainerName parameter if not implemented)
        $containerStarted = Start-TempoContainer -TestDirectory $TestDirectory
        if (-not $containerStarted) {
            throw "Failed to start Tempo container"
        }

        # Validate configuration if requested
        if (-not $SkipValidation) {
            Write-Log "Validating Tempo configuration..." -Color Yellow
            $configPath = Join-Path $TestDirectory "tempo.yaml"
            $validated = Test-TempoConfiguration -ConfigPath $configPath
            if (-not $validated) {
                throw "Configuration validation failed"
            }
        }

        Write-Log "Test sequence completed successfully!" -Color Green

        # Show available endpoints
        Write-Log "nAvailable Endpoints:" -Color Cyan
        Write-Log "- Tempo UI:    http://localhost:3200" -Color Yellow
        Write-Log "- Health:      http://localhost:3200/ready" -Color Yellow
        Write-Log "- Metrics:     http://localhost:3200/metrics" -Color Yellow
        Write-Log "- OTLP HTTP:   http://localhost:4318" -Color Yellow
        Write-Log "- OTLP gRPC:   localhost:4317" -Color Yellow

        return $true
    }
    catch {
        Write-Log "Test sequence failed: $_" -Color Red
        Write-Log $_.ScriptStackTrace -Color Red
        return $false
    }
}

# Execute the test sequence
Start-TempoTestSequence