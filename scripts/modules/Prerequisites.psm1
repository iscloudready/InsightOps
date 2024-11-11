# Module: Prerequisites.psm1

# Module for checking and ensuring prerequisites for InsightOps

# Function to write output in color
function Write-OutputColored {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "$timestamp [$Level] - $Message"
    Write-Host $logEntry
}

function Write-SuccessMessage { Write-OutputColored -Message $_ -Level "SUCCESS" }
function Write-InfoMessage { Write-OutputColored -Message $_ -Level "INFO" }
function Write-WarningMessage { Write-OutputColored -Message $_ -Level "WARNING" }
function Write-ErrorMessage { Write-OutputColored -Message $_ -Level "ERROR" }

# Check Docker Installation and Status
function Test-Docker {
    try {
        $dockerVersion = docker --version
        $dockerRunning = docker info 2>$null
        if ($dockerRunning) {
            Write-SuccessMessage "Docker is running - $dockerVersion"
            return $true
        } else {
            Write-WarningMessage "Docker is installed but not running."
            return $false
        }
    }
    catch {
        Write-ErrorMessage "Docker is not installed."
        return $false
    }
}

# Check .NET SDK Installation
function Test-DotNetSDK {
    try {
        $dotnetVersion = dotnet --version
        $requiredVersion = [Version]"8.0.0"
        $currentVersion = [Version]$dotnetVersion
        if ($currentVersion -ge $requiredVersion) {
            Write-SuccessMessage ".NET SDK found: version $currentVersion"
            return $true
        } else {
            Write-WarningMessage ".NET SDK version is outdated (found $currentVersion, requires $requiredVersion)."
            return $false
        }
    }
    catch {
        Write-ErrorMessage ".NET SDK is not installed."
        return $false
    }
}

# Check PowerShell Version
function Test-PowerShellVersion {
    $requiredVersion = [Version]"7.0.0"
    if ($PSVersionTable.PSVersion -ge $requiredVersion) {
        Write-SuccessMessage "PowerShell version is compatible (found $($PSVersionTable.PSVersion))."
        return $true
    } else {
        Write-ErrorMessage "PowerShell version is below required (found $($PSVersionTable.PSVersion), requires $requiredVersion)."
        return $false
    }
}

# Check Visual Studio Code Installation
function Test-VSCodeInstallation {
    try {
        $vscodePath = Get-Command code -ErrorAction SilentlyContinue
        if ($vscodePath) {
            Write-SuccessMessage "Visual Studio Code is installed."
            return $true
        } else {
            Write-WarningMessage "Visual Studio Code is not installed."
            return $false
        }
    }
    catch {
        Write-ErrorMessage "Visual Studio Code is not installed."
        return $false
    }
}

# Check Visual Studio Installation
function Test-VisualStudioInstallation {
    $vsPath = "${env:ProgramFiles}\Microsoft Visual Studio\2022"
    if (Test-Path -Path $vsPath) {
        Write-SuccessMessage "Visual Studio 2022 is installed."
        return $true
    } else {
        Write-WarningMessage "Visual Studio 2022 is not installed."
        return $false
    }
}

# Check Git Installation
function Test-Git {
    try {
        $gitVersion = git --version
        Write-SuccessMessage "Git is installed - $gitVersion"
        return $true
    }
    catch {
        Write-ErrorMessage "Git is not installed."
        return $false
    }
}

# Check Disk Space
function Test-DiskSpaceAvailability {
    $requiredSpaceGB = 50
    $driveInfo = Get-PSDrive -Name C
    $freeSpaceGB = [math]::Round($driveInfo.Free / 1GB, 2)
    if ($freeSpaceGB -gt $requiredSpaceGB) {
        Write-SuccessMessage "Sufficient disk space available: ${freeSpaceGB}GB"
        return $true
    } else {
        Write-WarningMessage "Insufficient disk space: only ${freeSpaceGB}GB available (requires $requiredSpaceGB GB)."
        return $false
    }
}

# Check System Memory
function Test-SystemMemoryAvailability {
    $requiredMemoryGB = 16
    $totalMemoryGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    if ($totalMemoryGB -ge $requiredMemoryGB) {
        Write-SuccessMessage "Sufficient system memory available: ${totalMemoryGB}GB"
        return $true
    } else {
        Write-WarningMessage "Insufficient system memory: only ${totalMemoryGB}GB available (requires $requiredMemoryGB GB)."
        return $false
    }
}

# Main function to run all checks and summarize results
function Test-AllPrerequisites {
    Write-InfoMessage "Checking system prerequisites for InsightOps..."

    # Perform each check
    $checkResults = @{
        "Docker" = Test-Docker
        ".NET SDK" = Test-DotNetSDK
        "PowerShell Version" = Test-PowerShellVersion
        "Visual Studio Code" = Test-VSCodeInstallation
        "Visual Studio" = Test-VisualStudioInstallation
        "Git" = Test-Git
        "Disk Space" = Test-DiskSpaceAvailability
        "System Memory" = Test-SystemMemoryAvailability
    }

    # Evaluate overall status
    $allPassed = $true
    foreach ($result in $checkResults.Values) {
        if (-not $result) { $allPassed = $false }
    }

    if ($allPassed) {
        Write-SuccessMessage "All prerequisites are met!"
    } else {
        Write-WarningMessage "Some prerequisites are missing or need attention."
    }
}

# Export functions for module use
Export-ModuleMember -Function Test-AllPrerequisites
