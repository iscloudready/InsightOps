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
    
    $allPassed = $true
    Write-Host "`nChecking System Prerequisites..." -ForegroundColor Cyan

    # Docker Check
    try {
        Write-Host "`nChecking Docker:" -ForegroundColor Yellow
        $dockerVersion = docker --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Docker installed: $dockerVersion" -ForegroundColor Green
        } 
        else {
            Write-Host "  ✗ Docker not installed" -ForegroundColor Red
            $allPassed = $false
        }
    } 
    catch {
        Write-Host "  ✗ Docker check failed: $_" -ForegroundColor Red
        $allPassed = $false
    }

    # PowerShell Version Check
    try {
        Write-Host "`nChecking PowerShell:" -ForegroundColor Yellow
        $psVersion = $PSVersionTable.PSVersion
        Write-Host "  ✓ PowerShell Version: $psVersion" -ForegroundColor Green
    } 
    catch {
        Write-Host "  ✗ PowerShell check failed: $_" -ForegroundColor Red
        $allPassed = $false
    }

    # Disk Space Check
    try {
        Write-Host "`nChecking Disk Space:" -ForegroundColor Yellow
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        Write-Host "  ✓ Free Space: ${freeSpaceGB}GB" -ForegroundColor Green
    } 
    catch {
        Write-Host "  ✗ Disk check failed: $_" -ForegroundColor Red
        $allPassed = $false
    }

    # Summary
    Write-Host "`nPrerequisites Check Summary:" -ForegroundColor Cyan
    if ($allPassed) {
        Write-Host "All prerequisites met!" -ForegroundColor Green
    } 
    else {
        Write-Host "Some prerequisites need attention." -ForegroundColor Yellow
    }

    return $allPassed
}

function Test-Prerequisites {
    [CmdletBinding()]
    param([switch]$Quiet)
    
    try {
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
        if (-not $Quiet) {
            Write-Host "Docker is not running." -ForegroundColor Red
        }
        return $false
    } 
    catch {
        if (-not $Quiet) {
            Write-Host "Prerequisites check failed." -ForegroundColor Red
        }
        return $false
    }
}

function _Test-AllPrerequisites {
    [CmdletBinding()]
    param()
    
    Write-Host "`nChecking System Prerequisites..." -ForegroundColor Cyan
    $allPassed = $true
    $results = @()

    # Check Docker Installation and Service
    try {
        Write-Host "`nChecking Docker:" -ForegroundColor Yellow
        $dockerVersion = docker --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Docker installed: $dockerVersion" -ForegroundColor Green
            
            # Check if Docker service is running
            $dockerInfo = docker info 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Docker service is running" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Docker service is not running" -ForegroundColor Red
                Write-Host "    → Start Docker Desktop or run 'net start docker'" -ForegroundColor Yellow
                $allPassed = $false
            }
        }
        else {
            Write-Host "  ✗ Docker is not installed" -ForegroundColor Red
            Write-Host "    → Download and install Docker Desktop from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Error checking Docker: $_" -ForegroundColor Red
        Write-Host "    → Ensure Docker is installed and properly configured" -ForegroundColor Yellow
        $allPassed = $false
    }

    # Check .NET SDK
    try {
        Write-Host "`nChecking .NET SDK:" -ForegroundColor Yellow
        $dotnetVersion = dotnet --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ .NET SDK: $dotnetVersion" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ .NET SDK not found" -ForegroundColor Red
            Write-Host "    → Download from: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Error checking .NET SDK" -ForegroundColor Red
        $allPassed = $false
    }

    # Check PowerShell Version
    Write-Host "`nChecking PowerShell:" -ForegroundColor Yellow
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Write-Host "  ✓ PowerShell Version: $psVersion" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ PowerShell version $psVersion is below recommended version 5.0" -ForegroundColor Red
        Write-Host "    → Update PowerShell from: https://github.com/PowerShell/PowerShell" -ForegroundColor Yellow
        $allPassed = $false
    }

    # Check Available Memory
    try {
        Write-Host "`nChecking System Resources:" -ForegroundColor Yellow
        $computerSystem = Get-WmiObject -Class WIN32_OperatingSystem
        $memory = [math]::Round($computerSystem.TotalVisibleMemorySize / 1MB, 2)
        if ($memory -ge 8) {
            Write-Host "  ✓ Memory: ${memory}GB Available" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ Insufficient memory: ${memory}GB (Minimum 8GB recommended)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Error checking system memory" -ForegroundColor Red
        $allPassed = $false
    }

    # Check Disk Space
    try {
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        if ($freeSpaceGB -ge 10) {
            Write-Host "  ✓ Disk Space: ${freeSpaceGB}GB Free" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ Insufficient disk space: ${freeSpaceGB}GB (Minimum 10GB recommended)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    catch {
        Write-Host "  ✗ Error checking disk space" -ForegroundColor Red
        $allPassed = $false
    }

    # Check Required Ports
    try {
        Write-Host "`nChecking Required Ports:" -ForegroundColor Yellow
        $portsToCheck = @(
            @{Port = 5010; Service = "Frontend"},
            @{Port = 5011; Service = "API Gateway"},
            @{Port = 5012; Service = "Order Service"},
            @{Port = 5013; Service = "Inventory Service"},
            @{Port = 3001; Service = "Grafana"},
            @{Port = 9091; Service = "Prometheus"},
            @{Port = 3101; Service = "Loki"},
            @{Port = 4317; Service = "Tempo"}
        )

        foreach ($portCheck in $portsToCheck) {
            $testResult = Test-NetConnection -ComputerName localhost -Port $portCheck.Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if (-not $testResult.TcpTestSucceeded) {
                Write-Host "  ✓ Port $($portCheck.Port) available for $($portCheck.Service)" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Port $($portCheck.Port) is in use (Required for $($portCheck.Service))" -ForegroundColor Red
                $allPassed = $false
            }
        }
    }
    catch {
        Write-Host "  ✗ Error checking ports" -ForegroundColor Red
        $allPassed = $false
    }

    # Final Summary
    Write-Host "`nPrerequisites Check Summary:" -ForegroundColor Cyan
    if ($allPassed) {
        Write-Host "All prerequisites met! System is ready for InsightOps." -ForegroundColor Green
    }
    else {
        Write-Host "Some prerequisites need attention. Please address the items marked with ✗" -ForegroundColor Yellow
        Write-Host "Run this check again after making the necessary changes." -ForegroundColor Yellow
    }

    return $allPassed
}

function _Test-Prerequisites {
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )
    
    try {
        # Quick check for Docker
        $dockerRunning = $false
        try {
            $dockerInfo = docker info 2>&1
            $dockerRunning = ($LASTEXITCODE -eq 0)
        }
        catch {
            $dockerRunning = $false
        }

        if (-not $dockerRunning) {
            if (-not $Quiet) {
                Write-Host "Docker is not running. Please start Docker Desktop." -ForegroundColor Red
                Write-Host "After starting Docker, try again." -ForegroundColor Yellow
            }
            return $false
        }

        # Quick check for configuration
        if (-not (Test-Configuration)) {
            if (-not $Quiet) {
                Write-Host "Configuration check failed. Run 'Initialize Environment' first." -ForegroundColor Red
            }
            return $false
        }

        return $true
    }
    catch {
        if (-not $Quiet) {
            Write-Host "Prerequisite check failed: $_" -ForegroundColor Red
        }
        return $false
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Test-AllPrerequisites',
    'Test-Prerequisites'
    'Test-DotNetSDK',
    'Test-DockerInstallation',
    'Test-Git',
    'Test-PowerShellVersion',
    'Test-VSCodeInstallation',
    'Test-VisualStudioInstallation',
    'Test-DiskSpaceAvailability',
    'Test-SystemMemoryAvailability'
)