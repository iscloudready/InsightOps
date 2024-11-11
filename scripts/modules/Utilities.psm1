# Utilities.psm1
# Purpose: Common utility functions for InsightOps

# Console color configurations
$script:CONSOLE_COLORS = @{
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Info = "Cyan"
    Debug = "Gray"
    Header = "Magenta"
    Default = "White"
}

function Show-QuickReference {
    [CmdletBinding()]
    param()
    
    Write-Host @"
Quick Reference Guide
====================
Docker Commands:
- Start services:  docker-compose up -d
- Stop services:   docker-compose down
- View logs:       docker-compose logs [service]
- Check status:    docker-compose ps
- Clean up:        docker system prune

Service URLs:
- Grafana:         http://localhost:3001
- Frontend:        http://localhost:5010
- API Gateway:     http://localhost:5011
- Order Service:   http://localhost:5012
- Inventory:       http://localhost:5013
- Prometheus:      http://localhost:9091
- Loki:           http://localhost:3101
- Tempo:          http://localhost:4317

Common Operations:
1. Start all:      Option 1
2. View status:    Option 3
3. Check health:   Option 10
4. View logs:      Option 4
5. Clean up:       Option 7
"@ -ForegroundColor Cyan
}

function Open-ServiceUrls {
    [CmdletBinding()]
    param()
    
    $urls = @(
        "http://localhost:3001",  # Grafana
        "http://localhost:5010",  # Frontend
        "http://localhost:5011"   # API Gateway
    )

    foreach ($url in $urls) {
        try {
            Start-Process $url
            Write-Information "Opened $url"
        }
        catch {
            Write-Error "Failed to open $url : $_"
        }
    }
}

function Write-FormattedMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Color = $script:CONSOLE_COLORS.Default,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoNewline
    )
    
    try {
        if ($NoNewline) {
            Write-Host $Message -ForegroundColor $Color -NoNewline
        }
        else {
            Write-Host $Message -ForegroundColor $Color
        }
    }
    catch {
        Write-Error "Failed to write formatted message: $_"
    }
}

function Format-Size {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [long]$Bytes
    )
    
    try {
        if ($Bytes -gt 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
        if ($Bytes -gt 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
        if ($Bytes -gt 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
        if ($Bytes -gt 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
        return "$Bytes Bytes"
    }
    catch {
        Write-Error "Failed to format size: $_"
        return "$Bytes Bytes"
    }
}

function Test-IsAdmin {
    [CmdletBinding()]
    param()
    
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-Error "Failed to check admin privileges: $_"
        return $false
    }
}

function Get-SystemInfo {
    [CmdletBinding()]
    param()
    
    try {
        return @{
            PowerShellVersion = $PSVersionTable.PSVersion
            OS = [System.Environment]::OSVersion
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            IsAdmin = Test-IsAdmin
        }
    }
    catch {
        Write-Error "Failed to get system info: $_"
        return $null
    }
}

function Invoke-WithRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$DelaySeconds = 5
    )
    
    $attempts = 0
    $error = $null
    
    do {
        $attempts++
        try {
            return & $ScriptBlock
        }
        catch {
            $error = $_
            if ($attempts -lt $MaxAttempts) {
                Write-Warning "Attempt $attempts of $MaxAttempts failed. Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    } while ($attempts -lt $MaxAttempts)
    
    Write-Error "All $MaxAttempts attempts failed. Last error: $error"
    throw $error
}

# Export only the functions we want to make available
Export-ModuleMember -Function @(
	'Open-ServiceUrls',
	'Show-QuickReference',
    'Write-FormattedMessage',
    'Format-Size',
    'Test-IsAdmin',
    'Get-SystemInfo',
    'Invoke-WithRetry'
) -Variable @(
    'CONSOLE_COLORS'
)