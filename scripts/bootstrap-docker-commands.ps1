$ps7Path = @(
    "${env:ProgramFiles}\PowerShell\7\pwsh.exe",
    "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
    "$env:LocalAppData\Microsoft\PowerShell\7\pwsh.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $ps7Path) {
    Write-Host "PowerShell 7 is required but not found. Would you like to install it? (Y/N)" -ForegroundColor Yellow
    $response = Read-Host
    if ($response -eq 'Y') {
        Write-Host "Installing PowerShell 7..."
        winget install --id Microsoft.Powershell --source winget
        Write-Host "Please restart your terminal and run the script again." -ForegroundColor Green
    }
    else {
        Write-Host "PowerShell 7 is required to run this script." -ForegroundColor Red
    }
    exit 1
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Switching to PowerShell 7..."
    Start-Process -FilePath $ps7Path -ArgumentList "-File `"$PSScriptRoot\docker-commands.ps1`"" -NoNewWindow -Wait
    exit $LASTEXITCODE
}
else {
    & "$PSScriptRoot\docker-commands.ps1"
}