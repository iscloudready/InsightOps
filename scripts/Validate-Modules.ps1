# Validate-Modules.ps1
# Purpose: Validate all required modules before running main script

# Define root paths
$script:BASE_PATH = $PSScriptRoot
$script:MODULE_PATH = Join-Path $BASE_PATH "Modules"
$script:LOGS_PATH = Join-Path (Split-Path $BASE_PATH -Parent) "logs"

function Test-ModuleValidity {
    param (
        [string]$ModulePath
    )
    
    try {
        # Test if file exists
        if (-not (Test-Path $ModulePath)) {
            return @{
                Valid = $false
                Error = "File not found: $ModulePath"
            }
        }

        # Read module content
        $moduleContent = Get-Content $ModulePath -Raw -ErrorAction Stop
        
        # Basic syntax check
        $null = [ScriptBlock]::Create($moduleContent)
        
        return @{
            Valid = $true
            Error = $null
        }
    }
    catch {
        return @{
            Valid = $false
            Error = "Validation error: $($_.Exception.Message)"
        }
    }
}

function Initialize-ModuleStructure {
    # Create Modules directory if it doesn't exist
    if (-not (Test-Path $script:MODULE_PATH)) {
        New-Item -ItemType Directory -Path $script:MODULE_PATH -Force | Out-Null
        Write-Host "Created Modules directory: $script:MODULE_PATH" -ForegroundColor Yellow
    }

    # Create logs directory if it doesn't exist
    if (-not (Test-Path $script:LOGS_PATH)) {
        New-Item -ItemType Directory -Path $script:LOGS_PATH -Force | Out-Null
        Write-Host "Created logs directory: $script:LOGS_PATH" -ForegroundColor Yellow
    }
}

# Initialize directory structure
Initialize-ModuleStructure

# Define required modules and their dependencies
$moduleDefinitions = @(
    @{
        Name = "Logging"
        Required = $true
        Dependencies = @()
    },
    @{
        Name = "Utilities"
        Required = $true
        Dependencies = @("Logging")
    },
    @{
        Name = "Core"
        Required = $true
        Dependencies = @("Logging", "Utilities")
    },
    @{
        Name = "Prerequisites"
        Required = $true
        Dependencies = @("Logging", "Utilities", "Core")
    },
    @{
        Name = "EnvironmentSetup"
        Required = $true
        Dependencies = @("Logging", "Utilities", "Core")
    },
    @{
        Name = "DockerOperations"
        Required = $true
        Dependencies = @("Logging", "Utilities", "Core")
    }
)

$results = @()
$allValid = $true

foreach ($moduleDef in $moduleDefinitions) {
    $moduleName = "$($moduleDef.Name).psm1"
    $fullPath = Join-Path $script:MODULE_PATH $moduleName
    $result = Test-ModuleValidity $fullPath
    
    # Check dependencies
    $dependencyErrors = @()
    foreach ($dep in $moduleDef.Dependencies) {
        $depPath = Join-Path $script:MODULE_PATH "$dep.psm1"
        if (-not (Test-Path $depPath)) {
            $dependencyErrors += "Missing dependency: $dep"
        }
    }
    
    $results += [PSCustomObject]@{
        Module = $moduleDef.Name
        Path = $fullPath
        Valid = $result.Valid -and $dependencyErrors.Count -eq 0
        Required = $moduleDef.Required
        Error = if ($result.Error) { $result.Error } elseif ($dependencyErrors) { $dependencyErrors -join "; " } else { $null }
    }
    
    if (-not $result.Valid -and $moduleDef.Required) {
        $allValid = $false
    }
}

# Display results
Write-Host "`nModule Validation Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize

# Display detailed errors for failed modules
$failedModules = $results | Where-Object { -not $_.Valid }
if ($failedModules) {
    Write-Host "`nDetailed Errors:" -ForegroundColor Red
    foreach ($module in $failedModules) {
        Write-Host "`nModule: $($module.Module)" -ForegroundColor Yellow
        Write-Host "Error: $($module.Error)" -ForegroundColor Red
    }
}

if (-not $allValid) {
    Write-Host "`nSome required modules failed validation. Please fix the errors before running main.ps1" -ForegroundColor Red
    exit 1
}

Write-Host "`nAll required modules passed validation" -ForegroundColor Green