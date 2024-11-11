# Prerequisites.psm1
# Purpose: Check and validate all system requirements for InsightOps

function Write-Info { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host $Message -ForegroundColor Red }

# Required versions and configurations
$script:REQUIREMENTS = @{
    DotNetSDK = [Version]"8.0.0"
    PowerShell = [Version]"7.0.0"
    MinDiskSpaceGB = 50
    MinMemoryGB = 16
}

function Test-DotNetSDK {
    [CmdletBinding()]
    param()
    
    try {
        $dotnetVersion = dotnet --version
        $currentVersion = [Version]$dotnetVersion
        if ($currentVersion -ge $script:REQUIREMENTS.DotNetSDK) {
            Write-Success ".NET SDK found: version $currentVersion"
            return $true
        } else {
            Write-Warning ".NET SDK version is outdated (found $currentVersion, requires $($script:REQUIREMENTS.DotNetSDK))."
            return $false
        }
    }
    catch {
        Write-Error ".NET SDK is not installed."
        return $false
    }
}

function Test-DockerInstallation {
    [CmdletBinding()]
    param()
    
    try {
        $dockerVersion = docker --version
        $dockerComposeVersion = docker-compose --version
        $dockerService = Get-Service docker -ErrorAction SilentlyContinue

        if (-not $dockerService) {
            Write-Error "Docker service is not installed"
            return $false
        }

        if ($dockerService.Status -ne 'Running') {
            Write-Warning "Docker service is not running"
            return $false
        }

        Write-Success "Docker is installed: $dockerVersion"
        Write-Success "Docker Compose is installed: $dockerComposeVersion"
        return $true
    }
    catch {
        Write-Error "Docker check failed: $_"
        return $false
    }
}

function Test-Git {
    [CmdletBinding()]
    param()
    
    try {
        $gitVersion = git --version
        Write-Success "Git is installed: $gitVersion"
        return $true
    }
    catch {
        Write-Error "Git is not installed"
        return $false
    }
}

function Test-PowerShellVersion {
    [CmdletBinding()]
    param()
    
    $currentVersion = $PSVersionTable.PSVersion
    if ($currentVersion -ge $script:REQUIREMENTS.PowerShell) {
        Write-Success "PowerShell version $currentVersion is compatible"
        return $true
    }
    else {
        Write-Error "PowerShell version $currentVersion is below required version $($script:REQUIREMENTS.PowerShell)"
        return $false
    }
}

function Test-VSCodeInstallation {
    [CmdletBinding()]
    param()
    
    try {
        $codePath = Get-Command code -ErrorAction Stop
        Write-Success "Visual Studio Code is installed: $($codePath.Version)"
        return $true
    }
    catch {
        Write-Warning "Visual Studio Code is not installed or not in PATH"
        return $false
    }
}

function Test-VisualStudioInstallation {
    [CmdletBinding()]
    param()
    
    try {
        $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $vsWhere) {
            $vsInstallation = & $vsWhere -latest -format json | ConvertFrom-Json
            if ($vsInstallation) {
                Write-Success "Visual Studio is installed: $($vsInstallation.displayName)"
                return $true
            }
        }
        Write-Warning "Visual Studio is not installed"
        return $false
    }
    catch {
        Write-Error "Visual Studio check failed: $_"
        return $false
    }
}

function Test-DiskSpaceAvailability {
    [CmdletBinding()]
    param()
    
    try {
        $drive = Get-PSDrive -Name C
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        
        if ($freeSpaceGB -ge $script:REQUIREMENTS.MinDiskSpaceGB) {
            Write-Success "Sufficient disk space available: ${freeSpaceGB}GB"
            return $true
        }
        else {
            Write-Warning "Insufficient disk space: ${freeSpaceGB}GB (required: $($script:REQUIREMENTS.MinDiskSpaceGB)GB)"
            return $false
        }
    }
    catch {
        Write-Error "Disk space check failed: $_"
        return $false
    }
}

function Test-SystemMemoryAvailability {
    [CmdletBinding()]
    param()
    
    try {
        $totalMemoryGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
        
        if ($totalMemoryGB -ge $script:REQUIREMENTS.MinMemoryGB) {
            Write-Success "Sufficient system memory: ${totalMemoryGB}GB"
            return $true
        }
        else {
            Write-Warning "Insufficient system memory: ${totalMemoryGB}GB (required: $($script:REQUIREMENTS.MinMemoryGB)GB)"
            return $false
        }
    }
    catch {
        Write-Error "Memory check failed: $_"
        return $false
    }
}

function Test-AllPrerequisites {
    [CmdletBinding()]
    param()
    
    Write-Information "Checking system prerequisites for InsightOps..."

    $checks = @{
        "Docker" = Test-DockerInstallation
        ".NET SDK" = Test-DotNetSDK
        "PowerShell Version" = Test-PowerShellVersion
        "Visual Studio Code" = Test-VSCodeInstallation
        "Visual Studio" = Test-VisualStudioInstallation
        "Git" = Test-Git
        "Disk Space" = Test-DiskSpaceAvailability
        "System Memory" = Test-SystemMemoryAvailability
    }

    $results = @()
    $allPassed = $true

    foreach ($check in $checks.GetEnumerator()) {
        $result = $check.Value
        $status = if ($result) { "[PASS]" } else { "[FAIL]" }
        $results += [PSCustomObject]@{
            Check = $check.Key
            Status = $status
            Passed = $result
        }
        if (-not $result) { $allPassed = $false }
    }

    # Display results in a formatted table
    $results | Format-Table -AutoSize

    if ($allPassed) {
        Write-Success "All prerequisites are met!"
    }
    else {
        Write-Warning "Some prerequisites need attention. Please review the results above."
    }

    return $allPassed
}

# Export module members
Export-ModuleMember -Function @(
    'Test-AllPrerequisites',
    'Test-DotNetSDK',
    'Test-DockerInstallation',
    'Test-Git',
    'Test-PowerShellVersion',
    'Test-VSCodeInstallation',
    'Test-VisualStudioInstallation',
    'Test-DiskSpaceAvailability',
    'Test-SystemMemoryAvailability'
)