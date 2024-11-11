# bootstrap-docker-commands.ps1
# Ensures PowerShell 7 and checks for system prerequisites via check-prereqs.ps1

# Ensure PowerShell 7 is used
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $ps7Path = @(
        "${env:ProgramFiles}\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
        "$env:LocalAppData\Microsoft\PowerShell\7\pwsh.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($ps7Path) {
        Write-Host "Switching to PowerShell 7..."
        Start-Process -FilePath $ps7Path -ArgumentList "-File `"$PSCommandPath`"" -NoNewWindow -Wait
        exit
    } else {
        Write-Host "PowerShell 7 not found. Continuing with PowerShell $($PSVersionTable.PSVersion)..." -ForegroundColor Yellow
    }
}

# Run check-prereqs.ps1 for prerequisite checks
& "$PSScriptRoot\check-prereqs.ps1" @PSBoundParameters
