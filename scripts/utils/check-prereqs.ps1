# Prerequisites Checker for InsightOps
param (
    [switch]$Detailed = $false
)

function Write-CheckResult($check, $result, $details) {
    $icon = if ($result) { "✅" } else { "❌" }
    $color = if ($result) { "Green" } else { "Red" }
    Write-Host "$icon $check" -ForegroundColor $color
    if ($Detailed -and $details) {
        Write-Host "   $details" -ForegroundColor Gray
    }
    return $result
}

function Test-DockerInstallation {
    try {
        $dockerVersion = docker --version
        $dockerRunning = docker info 2>$null
        $isRunning = $null -ne $dockerRunning

        if ($isRunning) {
            Write-CheckResult "Docker" $true "$dockerVersion"
        } else {
            Write-CheckResult "Docker" $false "Docker is installed but not running"
        }
        return $isRunning
    }
    catch {
        Write-CheckResult "Docker" $false "Docker is not installed"
        return $false
    }
}

function Test-DotNetSDK {
    try {
        $dotnetVersion = dotnet --version
        $required = [Version]"8.0.0"
        $current = [Version]$dotnetVersion
        $isValid = $current -ge $required

        Write-CheckResult ".NET SDK" $isValid "Found version $current (Required: $required)"
        return $isValid
    }
    catch {
        Write-CheckResult ".NET SDK" $false ".NET SDK is not installed"
        return $false
    }
}

function Test-PowerShell {
    $version = $PSVersionTable.PSVersion
    $required = [Version]"7.0.0"
    $isValid = $version -ge $required

    Write-CheckResult "PowerShell" $isValid "Found version $version (Required: $required)"
    return $isValid
}

function Test-VSCode {
    try {
        $code = Get-Command code -ErrorAction SilentlyContinue
        $hasCode = $null -ne $code

        Write-CheckResult "Visual Studio Code" $hasCode "VS Code is installed"
        return $hasCode
    }
    catch {
        Write-CheckResult "Visual Studio Code" $false "VS Code is not installed"
        return $false
    }
}

function Test-VisualStudio {
    $vsPath = "${env:ProgramFiles}\Microsoft Visual Studio\2022"
    $hasVS = Test-Path $vsPath

    Write-CheckResult "Visual Studio 2022" $hasVS
    return $hasVS
}

function Test-GitInstallation {
    try {
        $gitVersion = git --version
        Write-CheckResult "Git" $true "$gitVersion"
        return $true
    }
    catch {
        Write-CheckResult "Git" $false "Git is not installed"
        return $false
    }
}

function Test-DiskSpace {
    $drive = Get-PSDrive C
    $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
    $requiredGB = 50
    $hasSpace = $freeSpaceGB -gt $requiredGB

    Write-CheckResult "Disk Space" $hasSpace "Free space: ${freeSpaceGB}GB (Required: ${requiredGB}GB)"
    return $hasSpace
}

function Test-Memory {
    $totalMemoryGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    $requiredGB = 16
    $hasMemory = $totalMemoryGB -gt $requiredGB

    Write-CheckResult "System Memory" $hasMemory "Total RAM: ${totalMemoryGB}GB (Required: ${requiredGB}GB)"
    return $hasMemory
}

# Main Check
Write-Host "`nChecking InsightOps Prerequisites..." -ForegroundColor Cyan

$checks = @(
    (Test-DockerInstallation),
    (Test-DotNetSDK),
    (Test-PowerShell),
    (Test-VSCode),
    (Test-VisualStudio),
    (Test-GitInstallation),
    (Test-DiskSpace),
    (Test-Memory)
)

$allPassed = ($checks -notcontains $false)

Write-Host "`nSummary:" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "All prerequisites are met! ✨" -ForegroundColor Green
} else {
    Write-Host "Some prerequisites are missing. Please install required components. ⚠️" -ForegroundColor Yellow
}

return $allPassed