# Verify-Modules.ps1
# Purpose: Verify module loading and function availability

$ErrorActionPreference = "Stop"

# Define paths
$script:BASE_PATH = $PSScriptRoot
$script:MODULE_PATH = Join-Path $BASE_PATH "Modules"

function Test-ModuleLoading {
    param (
        [string]$ModuleName
    )
    
    try {
        $modulePath = Join-Path $script:MODULE_PATH "$ModuleName.psm1"
        
        # Try to import module
        Import-Module $modulePath -Force -DisableNameChecking
        
        # Verify module is loaded
        $module = Get-Module $ModuleName
        if (-not $module) {
            Write-Host "Failed to verify module loading: $ModuleName" -ForegroundColor Red
            return $false
        }
        
        # Get exported functions
        $functions = $module.ExportedFunctions.Keys
        Write-Host "Successfully loaded module: $ModuleName" -ForegroundColor Green
        Write-Host "Exported functions: $($functions -join ', ')" -ForegroundColor Cyan
        
        return $true
    }
    catch {
        Write-Host "Error loading module $ModuleName : $_" -ForegroundColor Red
        return $false
    }
}

# Test each module
$modules = @(
    'Logging',
    'Utilities',
    'Core',
    'Prerequisites',
    'EnvironmentSetup',
    'DockerOperations'
)

$results = @()
foreach ($module in $modules) {
    $result = Test-ModuleLoading $module
    $results += [PSCustomObject]@{
        Module = $module
        Loaded = $result
    }
}

# Display results
Write-Host "`nModule Loading Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize