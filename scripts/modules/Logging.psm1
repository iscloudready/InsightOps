# Logging.psm1
# Purpose: Centralized logging functionality for InsightOps

# Initialize paths
$script:DEFAULT_LOG_PATH = Join-Path (Split-Path -Parent $PSScriptRoot) "logs"
$script:LOG_FILE = Join-Path $script:DEFAULT_LOG_PATH "insightops.log"
$script:MAX_LOG_SIZE_MB = 10

# Message severity levels
$script:LOG_LEVELS = @{
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    SUCCESS = "SUCCESS"
    DEBUG = "DEBUG"
}

function Initialize-Logging {
    [CmdletBinding()]
    param()
    
    try {
        # Create logs directory if it doesn't exist
        if (-not (Test-Path $script:DEFAULT_LOG_PATH)) {
            New-Item -ItemType Directory -Path $script:DEFAULT_LOG_PATH -Force | Out-Null
            Write-Host "Created logs directory: $script:DEFAULT_LOG_PATH"
        }

        # Create log file if it doesn't exist
        if (-not (Test-Path $script:LOG_FILE)) {
            New-Item -ItemType File -Path $script:LOG_FILE -Force | Out-Null
            Write-Host "Created log file: $script:LOG_FILE"
        }

        # Test write access
        Add-Content -Path $script:LOG_FILE -Value "Log initialized $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ErrorAction Continue
        return $true
    }
    catch {
        Write-Error "Failed to initialize logging: $_"
        return $false
    }
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory = $false)]
        [string]$Source = "InsightOps"
    )

    try {
        # Ensure logging is initialized
        if (-not (Test-Path $script:LOG_FILE)) {
            Initialize-Logging | Out-Null
        }

        # Create timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Format message
        $logMessage = "$timestamp [$Level] [$Source] - $Message"
        
        # Write to log file
        Add-Content -Path $script:LOG_FILE -Value $logMessage -ErrorAction Continue
        
        # Also write to console with appropriate color
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "INFO" { "White" }
            "DEBUG" { "Gray" }
            default { "White" }
        }
        
        Write-Host $logMessage -ForegroundColor $color
    }
    catch {
        Write-Error "Failed to write log message: $_"
    }
}

function Remove-OldLogs {
    [CmdletBinding()]
    param(
        [int]$DaysToKeep = 30
    )
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        Get-ChildItem -Path $script:DEFAULT_LOG_PATH -Filter "*.log.*" |
            Where-Object { $_.LastWriteTime -lt $cutoffDate } |
            Remove-Item -Force
    }
    catch {
        Write-Error "Failed to clean old logs: $_"
    }
}

# Convenience functions using approved verbs
function Write-Information { param([string]$Message) Write-Log -Message $Message -Level "INFO" }
function Write-Warning { param([string]$Message) Write-Log -Message $Message -Level "WARNING" }
function Write-Error { param([string]$Message) Write-Log -Message $Message -Level "ERROR" }
function Write-Success { param([string]$Message) Write-Log -Message $Message -Level "SUCCESS" }
function Write-Debug { param([string]$Message) Write-Log -Message $Message -Level "DEBUG" }

# Export module members using approved verbs
Export-ModuleMember -Function @(
    'Initialize-Logging',
    'Write-Log',
    'Remove-OldLogs',
    'Write-Information',
    'Write-Warning',
    'Write-Error',
    'Write-Success',	
    'Write-Debug'
) -Variable @(
    'LOG_LEVELS',
    'DEFAULT_LOG_PATH',
    'LOG_FILE'
)