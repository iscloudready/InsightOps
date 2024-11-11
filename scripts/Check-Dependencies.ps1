# Check-Dependencies.ps1
# Purpose: Verify module dependencies and circular references

function Test-ModuleDependencies {
    param (
        [string]$ModulePath
    )

    $content = Get-Content $ModulePath -Raw
    if ($content -match 'using\s+module') {
        Write-Host "WARNING: Found 'using module' statement in $ModulePath" -ForegroundColor Yellow
        return $false
    }
    return $true
}

$modulePath = Join-Path $PSScriptRoot "Modules"
Get-ChildItem -Path $modulePath -Filter "*.psm1" | ForEach-Object {
    Write-Host "Checking $($_.Name)..." -ForegroundColor Cyan
    Test-ModuleDependencies $_.FullName
}