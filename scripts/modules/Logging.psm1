# Logging.psm1

# Path to log file
$script:LogFile = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "InsightOps_Logs.txt"

# Set maximum log size for rotation (e.g., 5 MB)
$script:MaxLogSizeMB = 5

function Write-LogEntry {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )

    # Generate timestamped log entry
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "$timestamp [$Level] - $Message"

    # Rotate log if necessary
    Backup-LogFileIfNecessary

    try {
        # Write to log file and console
        Add-Content -Path $LogFile -Value $logEntry
        Write-Host $logEntry
    } catch {
        Write-Host "Error writing to log file: $_" -ForegroundColor Red
    }
}

function Backup-LogFileIfNecessary {
    if (Test-Path $LogFile) {
        $fileSizeMB = (Get-Item $LogFile).Length / 1MB
        if ($fileSizeMB -ge $script:MaxLogSizeMB) {
            $timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
            $backupLog = "$LogFile.$timestamp.bak"
            Move-Item -Path $LogFile -Destination $backupLog
            Write-Host "Log rotated: $backupLog" -ForegroundColor Yellow
        }
    }
}

Export-ModuleMember -Function Write-LogEntry
