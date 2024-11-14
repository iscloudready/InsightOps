# Set ErrorActionPreference to stop on errors
$ErrorActionPreference = "Stop"

# Load JSON Configuration from the same directory as this script
$configPath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "config.json"
if (Test-Path $configPath) {
    $config = Get-Content -Path $configPath | ConvertFrom-Json
} else {
    Write-Output "Configuration file not found at path: $configPath"
    exit
}

# Retrieve values from config.json
$TestDirectory = $config.TestDirectory
$SkipValidation = $config.SkipValidation
$NoCleanup = $config.NoCleanup
$IncludeSystemPrune = $config.IncludeSystemPrune
$ForceCleanup = $config.ForceCleanup

# Path to the Scripts folder
$scriptPath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "Scripts"

# Start the Tempo test sequence with parameters from config.json
Write-Output "Starting test sequence..."
& "$scriptPath\Start-TempoTest.ps1" -TestDirectory $TestDirectory -SkipValidation:$SkipValidation -NoCleanup:$NoCleanup

# Optional: Additional command to stop and cleanup
Write-Output "Stopping and cleaning up..."
& "$scriptPath\Stop-TempoTest.ps1" -IncludeSystemPrune:$IncludeSystemPrune -Force:$ForceCleanup