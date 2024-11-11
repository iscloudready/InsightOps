# InsightOps Initialization Script with Enhanced Structure and Logging
param (
    [switch]$Development = $true,
    [switch]$ForceRecreate = $false
)

# Paths
$rootDir = "InsightOps"
$logFile = Join-Path $rootDir "logs\InsightOps_InitLog.txt"
$grafanaDir = Join-Path $rootDir "Configurations\grafana"

# Logging Function
function Log-Message {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "$timestamp [$Level] - $Message"
    Add-Content -Path $logFile -Value $logEntry
    Write-Host $logEntry
}

# Color Output Functions
function Write-ColorOutput {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White
    )
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Host $Message
    $host.UI.RawUI.ForegroundColor = $fc
    Log-Message $Message $Level
}

function Write-Success { Write-ColorOutput -Message $args -ForegroundColor Green -Level "SUCCESS" }
function Write-Info { Write-ColorOutput -Message $args -ForegroundColor Cyan -Level "INFO" }
function Write-Warning { Write-ColorOutput -Message $args -ForegroundColor Yellow -Level "WARNING" }
function Write-Error { Write-ColorOutput -Message $args -ForegroundColor Red -Level "ERROR" }

# Directory Structure Setup
function Setup-DirectoryStructure {
    Write-Info "Setting up directory structure..."

    $directories = @(
        "$rootDir\Scripts",
        "$rootDir\Scripts\Modules",
        "$rootDir\Configurations",
        "$rootDir\Configurations\grafana",
        "$rootDir\Configurations\prometheus",
        "$rootDir\Configurations\loki",
        "$rootDir\Configurations\tempo",
        "$rootDir\logs"
    )

    $scriptFiles = @(
        "$rootDir\Scripts\docker-commands.ps1",
        "$rootDir\Scripts\bootstrap-docker-commands.ps1",
        "$rootDir\Scripts\Core.ps1",
        "$rootDir\Scripts\check-prereqs.ps1",
        "$rootDir\Scripts\setup-environment.ps1",
        "$rootDir\Scripts\cleanup.ps1",
        "$rootDir\Scripts\Modules\Prerequisites.psm1",
        "$rootDir\Scripts\Modules\DockerOperations.psm1",
        "$rootDir\Scripts\Modules\EnvironmentSetup.psm1",
        "$rootDir\Scripts\Modules\Utilities.psm1",
        "$rootDir\Scripts\Modules\Logging.psm1",
        "$rootDir\Scripts\main.ps1"
    )

    foreach ($directory in $directories) {
        if (-not (Test-Path -Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Write-Success "Created directory: $directory"
        }
    }

    foreach ($file in $scriptFiles) {
        if (-not (Test-Path -Path $file)) {
            New-Item -ItemType File -Path $file -Force | Out-Null
            Write-Success "Created placeholder file: $file"
        }
    }

    Write-Info "Directory structure setup complete."
}

# Check Prerequisites
function Check-Prerequisites {
    Write-Info "Checking prerequisites..."
    try {
        docker info > $null 2>&1
        Write-Success "Docker is running"
    }
    catch {
        Write-Error "Docker is not running or not installed"
        exit 1
    }

    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        Write-Success ".NET SDK is installed"
    } else {
        Write-Error ".NET SDK is not installed"
        exit 1
    }

    # PowerShell Version Check
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Success "PowerShell version is compatible"
    } else {
        Write-Error "PowerShell 7 or higher is required"
        exit 1
    }
}

# Other Initialization Functions
function Create-ConfigurationFiles {
    Write-Info "Creating configuration files..."

    # Datasources Configuration
    $datasourcesConfig = @"
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://insightops_prometheus:9090
    isDefault: true
  - name: Loki
    type: loki
    access: proxy
    url: http://insightops_loki:3100
  - name: Tempo
    type: tempo
    access: proxy
    url: http://insightops_tempo:4317
"@
    Set-Content -Path (Join-Path $grafanaDir "provisioning\datasources\datasources.yaml") -Value $datasourcesConfig
    Write-Success "Created Grafana datasources configuration"

    # Prometheus Configuration
    $prometheusConfig = @"
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
"@
    Set-Content -Path "$rootDir\Configurations\prometheus\prometheus.yml" -Value $prometheusConfig
    Write-Success "Created Prometheus configuration"

    # Loki Configuration
    $lokiConfig = @"
auth_enabled: false
server:
  http_listen_port: 3100
ingester:
  chunk_idle_period: 5m
schema_config:
  configs:
    - from: 2020-05-15
      store: boltdb
storage_config:
  boltdb:
    directory: /tmp/loki/index
"@
    Set-Content -Path "$rootDir\Configurations\loki\loki-config.yaml" -Value $lokiConfig
    Write-Success "Created Loki configuration"

    # Tempo Configuration
    $tempoConfig = @"
server:
  http_listen_port: 3200
storage:
  trace:
    backend: local
"@
    Set-Content -Path "$rootDir\Configurations\tempo\tempo.yaml" -Value $tempoConfig
    Write-Success "Created Tempo configuration"
}

# Main Execution
try {
    Log-Message "Starting InsightOps initialization..."
    Setup-DirectoryStructure  # Set up folders and placeholders first
    Check-Prerequisites       # Run prerequisite checks
    Create-ConfigurationFiles # Create config files
    Write-Success "InsightOps initialization completed successfully!"
}
catch {
    Write-Error "An error occurred: $_"
    Log-Message "An error occurred: $_" -Level "ERROR"
    exit 1
}
