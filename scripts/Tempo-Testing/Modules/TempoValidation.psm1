# TempoValidation.psm1

# Parameterized variables for flexibility
$DockerImage = "grafana/tempo:latest"       # Docker image name, can be adjusted as needed
$ConfigPath = "D:\\tempo-test\\tempo.yaml"  # Path to the configuration file
$ContainerName = "test_tempo"               # Container name

# Logging function for consistent log formatting
function Write-ValidationLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp : $Message" -ForegroundColor $Color
}

# Function to check if Docker is running and accessible
function Test-DockerAvailability {
    try {
        $result = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ValidationLog "Docker is running and accessible." -Color Green
            return $true
        } else {
            Write-ValidationLog "Docker is installed but not responding. Please ensure Docker is started." -Color Yellow
            return $false
        }
    }
    catch {
        Write-ValidationLog "Docker CLI not found or inaccessible. Please install Docker or check your PATH environment variable." -Color Red
        return $false
    }
}

# Function to validate Docker containers by project pattern
function Check-ProjectContainers {
    param (
        [string]$ProjectPattern = "tempo"  # Allows pattern matching for container validation
    )

    if (-not (Test-DockerAvailability)) {
        Write-ValidationLog "Skipping container validation due to Docker inaccessibility." -Color Red
        return $false
    }

    try {
        $containers = docker ps --format "{{.Names}}" | Where-Object { $_ -like "*$ProjectPattern*" }
        if ($containers) {
            Write-ValidationLog "Found containers matching pattern *$ProjectPattern*: $containers" -Color Green
            return $true
        } else {
            Write-ValidationLog "No running containers found matching pattern: *$ProjectPattern*" -Color Yellow
            return $false
        }
    }
    catch {
        Write-ValidationLog "Error during container validation: $_" -Color Red
        return $false
    }
}

# Function to validate Docker volumes by project pattern
function Check-ProjectVolumes {
    param (
        [string]$ProjectPattern = "tempo"  # Allows pattern matching for volume validation
    )

    if (-not (Test-DockerAvailability)) {
        Write-ValidationLog "Skipping volume validation due to Docker inaccessibility." -Color Red
        return $false
    }

    try {
        $volumes = docker volume ls --format "{{.Name}}" | Where-Object { $_ -like "*$ProjectPattern*" }
        if ($volumes) {
            Write-ValidationLog "Found volumes matching pattern *$ProjectPattern*: $volumes" -Color Green
            return $true
        } else {
            Write-ValidationLog "No volumes found matching pattern: *$ProjectPattern*" -Color Yellow
            return $false
        }
    }
    catch {
        Write-ValidationLog "Error during volume validation: $_" -Color Red
        return $false
    }
}

# Function to validate Docker networks by project pattern
function Check-ProjectNetworks {
    param (
        [string]$ProjectPattern = "tempo"  # Allows pattern matching for network validation
    )

    if (-not (Test-DockerAvailability)) {
        Write-ValidationLog "Skipping network validation due to Docker inaccessibility." -Color Red
        return $false
    }

    try {
        $networks = docker network ls --format "{{.Name}}" | Where-Object { $_ -like "*$ProjectPattern*" }
        if ($networks) {
            Write-ValidationLog "Found networks matching pattern *$ProjectPattern*: $networks" -Color Green
            return $true
        } else {
            Write-ValidationLog "No networks found matching pattern: *$ProjectPattern*" -Color Yellow
            return $false
        }
    }
    catch {
        Write-ValidationLog "Error during network validation: $_" -Color Red
        return $false
    }
}

# Function to validate Docker environment and resources
function Validate-DockerEnvironment {
    Write-ValidationLog "Starting Docker environment validation..." -Color Cyan

    # Check if Docker is running and accessible
    if (-not (Test-DockerAvailability)) {
        Write-ValidationLog "Docker environment validation failed due to Docker inaccessibility." -Color Red
        return $false
    }

    # Validate containers, volumes, and networks
    $containersValid = Check-ProjectContainers -ProjectPattern "tempo"
    $volumesValid = Check-ProjectVolumes -ProjectPattern "tempo"
    $networksValid = Check-ProjectNetworks -ProjectPattern "tempo"

    if ($containersValid -and $volumesValid -and $networksValid) {
        Write-ValidationLog "Docker environment validation completed successfully." -Color Green
        return $true
    } else {
        Write-ValidationLog "Docker environment validation encountered issues." -Color Red
        return $false
    }
}

# Function to validate Tempo configuration
function Test-TempoConfiguration {
    param (
        [string]$ConfigPath = $ConfigPath,
        [string]$ContainerName = $ContainerName
    )

    Write-ValidationLog "Validating configuration in $ConfigPath for container $ContainerName..." -Color Cyan
    if (Test-Path $ConfigPath) {
        $configContent = Get-Content -Path $ConfigPath -Raw
        if ($configContent -match "backend:\s*(local|s3|gcs|boltdb|azure)") {
            Write-ValidationLog "Supported backend found in configuration." -Color Green
            return $true
        } else {
            Write-ValidationLog "Configuration backend is unsupported or missing." -Color Red
            return $false
        }
    } else {
        Write-ValidationLog "Configuration file $ConfigPath not found." -Color Red
        return $false
    }
}

# Export functions for module use
Export-ModuleMember -Function @(
    'Write-ValidationLog',
    'Test-DockerAvailability',
    'Check-ProjectContainers',
    'Check-ProjectVolumes',
    'Check-ProjectNetworks',
    'Validate-DockerEnvironment',
    'Test-TempoConfiguration'
)