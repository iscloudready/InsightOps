# main.ps1

# Import core and other modules
Import-Module "$PSScriptRoot\Modules\Core.psm1"  # Updated to .psm1
Import-Module "$PSScriptRoot\Modules\Logging.psm1"
Import-Module "$PSScriptRoot\Modules\Utilities.psm1"
Import-Module "$PSScriptRoot\Modules\Prerequisites.psm1"
Import-Module "$PSScriptRoot\Modules\EnvironmentSetup.psm1"
Import-Module "$PSScriptRoot\Modules\DockerOperations.psm1"

# Initialize required directories with error handling
try {
    Initialize-RequiredDirectories  # From Core.psm1
} catch {
    Write-ColorMessage "Failed to initialize required directories: $_" $COLORS.Error
    Log-Message "Failed to initialize required directories: $_" -Level "ERROR"
    exit 1
}

# Main Execution Loop
try {
    Log-Message "Starting InsightOps Docker Management..."

    # Check prerequisites
    if (-not (Check-Prerequisites)) {
        Write-ColorMessage "Prerequisites check failed. Please install required components." $COLORS.Error
        exit 1
    }

    # Main menu loop
    while ($true) {
        Show-Menu
        $choice = Read-Host "`nEnter your choice (0-20)"
        
        switch ($choice) {
            0 { 
                Write-ColorMessage "Exiting InsightOps Docker Management..." $COLORS.Info
                break 
            }
            1 { Start-Services }
            2 { Stop-Services }
            3 { Show-ContainerStatus }
            4 { 
                Write-ColorMessage "Displaying container logs..." $COLORS.Info
                Show-Logs
            }
            5 { docker stats }
            6 {
                Write-ColorMessage "Enter the service to rebuild:" $COLORS.Info
                $serviceName = Read-Host "Service name"
                Rebuild-Service $serviceName
            }
            7 { Clean-DockerSystem }
            8 { Show-QuickReference }
            9 { Open-ServiceUrls }
            10 { Check-ServiceHealth }
            11 { Show-ResourceUsage }
            12 { Initialize-Environment }
            13 { Check-Prerequisites }
            14 { Run-CleanupTasks }
            15 { View-SystemMetrics }
            16 { Export-ContainerLogs }
            17 { Backup-Configuration }
            18 { Test-Configuration }
            19 { Test-NetworkConnectivity }
            20 { Initialize-RequiredDirectories }
            default { Write-ColorMessage "Invalid option" $COLORS.Warning }
        }

        if ($choice -ne 0) {
            Write-Host "`nPress Enter to continue..."
            Read-Host
        }
    }
}
catch {
    Write-Error "An error occurred: $_"
    Log-Message "An error occurred: $_" -Level "ERROR"
    exit 1
}
