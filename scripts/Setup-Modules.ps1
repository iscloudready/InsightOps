# Setup-Modules.ps1
# Purpose: Set up the module environment and ensure all prerequisites are met

$ErrorActionPreference = "Stop"

# Define paths
$script:BASE_PATH = $PSScriptRoot
$script:MODULE_PATH = Join-Path $BASE_PATH "Modules"
$script:LOGS_PATH = Join-Path (Split-Path $BASE_PATH -Parent) "logs"
$script:CONFIG_PATH = Join-Path (Split-Path $BASE_PATH -Parent) "Configurations"

function Initialize-Environment {
    # Create necessary directories
    $directories = @(
        $script:MODULE_PATH,
        $script:LOGS_PATH,
        $script:CONFIG_PATH
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "Created directory: $dir" -ForegroundColor Green
        }
    }
}

function Test-PowerShellVersion {
    $minVersion = [Version]"5.1"
    $currentVersion = $PSVersionTable.PSVersion
    
    if ($currentVersion -lt $minVersion) {
        Write-Host "PowerShell version $currentVersion is below minimum required version $minVersion" -ForegroundColor Red
        return $false
    }
    
    Write-Host "PowerShell version $currentVersion is compatible" -ForegroundColor Green
    return $true
}

# Initialize environment
Write-Host "Initializing environment..." -ForegroundColor Cyan
Initialize-Environment

# Check PowerShell version
if (-not (Test-PowerShellVersion)) {
    Write-Host "Environment setup failed - PowerShell version requirement not met" -ForegroundColor Red
    exit 1
}

Write-Host "Environment setup completed successfully" -ForegroundColor Green

# Run module validation
Write-Host "`nValidating modules..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "Validate-Modules.ps1")