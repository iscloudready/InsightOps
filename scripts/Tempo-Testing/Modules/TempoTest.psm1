# TempoTest.psm1

# Parameterized variables for flexibility
$DockerImage = "grafana/tempo:latest"      # Docker image, configurable
$ConfigPath = "D:\\tempo-test\\tempo.yaml" # Path to the configuration file
$ContainerName = "test_tempo"              # Container name
$TestDirectory = "D:\\tempo-test"          # Default test directory path
$ProjectPattern = "tempo"                  # Pattern for identifying project-specific resources

# Logging function for output
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp : $Message" -ForegroundColor $Color
}

# Function to clean Docker resources
function Clean-DockerResources {
    Write-Log "Cleaning Docker resources..." -Color Yellow

    # Stop and remove container if it exists
    $container = docker ps -a -q -f name=$ContainerName
    if ($container) {
        Write-Log "Removing existing container..." -Color Yellow
        docker rm -f $ContainerName 2>&1 | Out-Null
    }

    # Remove test volume if it exists
    $volume = docker volume ls -q -f name="${ProjectPattern}_data"
    if ($volume) {
        Write-Log "Removing existing volume..." -Color Yellow
        docker volume rm -f "${ProjectPattern}_data" 2>&1 | Out-Null
    }

    Write-Log "Docker resources cleaned" -Color Green
}

# Function to set up the test environment
function Start-TempoTestEnvironment {
    [CmdletBinding()]
    param (
        [string]$TestDirectory = $TestDirectory
    )

    # Create test directory
    if (Test-Path $TestDirectory) {
        Remove-Item -Path $TestDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TestDirectory -Force | Out-Null
    Write-Log "Created test directory: $TestDirectory" -Color Green

    # Create configuration file
    $config = @"
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

storage:
  trace:
    backend: local
    local:
      path: /tmp/blocks
    wal:
      path: /tmp/wal

metrics_generator:
  storage:
    path: /tmp/generator
"@

    Set-Content -Path "$TestDirectory\\tempo.yaml" -Value $config -Encoding UTF8
    Write-Log "Configuration file created at $TestDirectory\\tempo.yaml" -Color Green

    return $TestDirectory
}

# Function to check and pull Docker image if not available
function Ensure-DockerImageAvailable {
    param (
        [string]$ImageName = $DockerImage
    )

    Write-Log "Checking for Docker image: $ImageName" -Color Cyan
    $imageExists = docker images -q $ImageName

    if (-not $imageExists) {
        Write-Log "Image not found. Pulling $ImageName..." -Color Yellow
        docker pull $ImageName
        Write-Log "Docker image $ImageName pulled successfully." -Color Green
    } else {
        Write-Log "Docker image $ImageName is already available locally." -Color Green
    }
}

# Function to start the Tempo container
function Start-TempoContainer {
    [CmdletBinding()]
    param (
        [string]$TestDirectory = $TestDirectory
    )

    try {
        # Ensure Docker image is available
        Ensure-DockerImageAvailable -ImageName $DockerImage

        # Create dedicated volume
        Write-Log "Creating Docker volume..." -Color Yellow
        docker volume create "${ProjectPattern}_data" | Out-Null

        # Start container with validated parameters
        Write-Log "Starting Tempo container..." -Color Yellow
        docker run -d `
            --name $ContainerName `
            -v "${TestDirectory}/tempo.yaml:/etc/tempo.yaml" `
            -v "${ProjectPattern}_data:/tmp" `
            -p 3200:3200 `
            -p 4317:4317 `
            -p 4318:4318 `
            $DockerImage `
            "-config.file=/etc/tempo.yaml" | Out-Null

        Write-Log "Container started, waiting for initialization..." -Color Yellow
        Start-Sleep -Seconds 10

        # Check container status
        $status = docker inspect --format '{{.State.Status}}' $ContainerName
        Write-Log "Container status: $status" -Color Cyan

        if ($status -ne "running") {
            $logs = docker logs $ContainerName 2>&1
            throw "Container not running. Logs:`n$logs"
        }

        # Test endpoint for readiness
        Write-Log "Testing container endpoint readiness..." -Color Yellow
        $maxAttempts = 6
        $attempt = 1
        while ($attempt -le $maxAttempts) {
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:3200/ready" -Method GET -TimeoutSec 5
                if ($response.StatusCode -eq 200) {
                    Write-Log "Tempo container is ready and responding!" -Color Green
                    return $true
                }
            }
            catch {
                Write-Log "Attempt $attempt of $maxAttempts..." -Color Yellow
                if ($attempt -eq $maxAttempts) {
                    $logs = docker logs $ContainerName 2>&1
                    Write-Log "Container logs:`n$logs" -Color Yellow
                    throw "Failed to connect to Tempo container after $maxAttempts attempts"
                }
            }
            $attempt++
            Start-Sleep -Seconds 5
        }
    }
    catch {
        Write-Log "Error: $_" -Color Red
        return $false
    }
}

# Export functions for module use
Export-ModuleMember -Function @(
    'Write-Log',
    'Clean-DockerResources',
    'Start-TempoTestEnvironment',
    'Start-TempoContainer'
)