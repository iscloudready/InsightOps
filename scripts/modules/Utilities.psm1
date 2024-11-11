# Utilities.psm1

# Color mappings for message types
$script:COLORS = @{
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Info = "Cyan"
    Header = "Magenta"
}

function Write-ColorMessage {
    param (
        [string]$Message,
        [string]$Level = "INFO"  # Use descriptive levels like "INFO", "ERROR", etc.
    )
    
    # Determine color based on level
    $Color = $script:COLORS[$Level] 
    if (-not $Color) { $Color = "White" }  # Default color if none matches

    # Temporarily change console color
    $originalColor = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Message
    $host.UI.RawUI.ForegroundColor = $originalColor

    # Log the message with level
    Log-Message -Message $Message -Level $Level
}

Export-ModuleMember -Function Write-ColorMessage
