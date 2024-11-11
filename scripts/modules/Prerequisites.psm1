function Test-AllPrerequisites {
    [CmdletBinding()]
    param()
    
    Write-Host "`nChecking System Prerequisites" -ForegroundColor Cyan
    $allPassed = $true

    # Docker Check
    try {
        Write-Host "`nDocker:" -ForegroundColor Yellow
        $dockerVersion = docker --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Docker installed: $dockerVersion" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Docker not found" -ForegroundColor Red
            $allPassed = $false
        }
    } catch {
        Write-Host "[ERROR] Docker check failed" -ForegroundColor Red
        $allPassed = $false
    }

    # PowerShell Version
    try {
        Write-Host "`nPowerShell:" -ForegroundColor Yellow
        $psVersion = $PSVersionTable.PSVersion
        if ($psVersion.Major -ge 5) {
            Write-Host "[OK] PowerShell Version: $psVersion" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] PowerShell version too low: $psVersion" -ForegroundColor Red
            $allPassed = $false
        }
    } catch {
        Write-Host "[ERROR] PowerShell check failed" -ForegroundColor Red
        $allPassed = $false
    }

    # Memory Check
    try {
        Write-Host "`nSystem Memory:" -ForegroundColor Yellow
        $computerSystem = Get-WmiObject -Class WIN32_OperatingSystem
        $totalMemoryGB = [math]::Round($computerSystem.TotalVisibleMemorySize / 1MB, 2)
        if ($totalMemoryGB -ge 8) {
            Write-Host "[OK] Memory: $totalMemoryGB GB" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Insufficient memory: $totalMemoryGB GB (8GB minimum)" -ForegroundColor Red
            $allPassed = $false
        }
    } catch {
        Write-Host "[ERROR] Memory check failed" -ForegroundColor Red
        $allPassed = $false
    }

    # Disk Space
    try {
        Write-Host "`nDisk Space:" -ForegroundColor Yellow
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        if ($freeSpaceGB -ge 10) {
            Write-Host "[OK] Free Space: $freeSpaceGB GB" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Low disk space: $freeSpaceGB GB (10GB minimum)" -ForegroundColor Red
            $allPassed = $false
        }
    } catch {
        Write-Host "[ERROR] Disk space check failed" -ForegroundColor Red
        $allPassed = $false
    }

    # Summary
    Write-Host "`nPrerequisites Summary:" -ForegroundColor Cyan
    if ($allPassed) {
        Write-Host "[PASS] All system prerequisites met!" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Some prerequisites not met. Review the items marked [FAIL]" -ForegroundColor Red
    }

    return $allPassed
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()
    
    try {
        $result = docker info 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

Export-ModuleMember -Function @(
    'Test-AllPrerequisites',
    'Test-Prerequisites'
)