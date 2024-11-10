# PowerShell script for Docker management in Visual Studio 2022

# Colors for better readability
$Red = [System.ConsoleColor]::Red
$Green = [System.ConsoleColor]::Green
$Yellow = [System.ConsoleColor]::Yellow

# Current location - should be in the Configurations folder
$scriptPath = $PSScriptRoot
$solutionRoot = Split-Path (Split-Path $scriptPath -Parent) -Parent

# Function to print section headers
function Print-Header($title) {
    Write-Host "`n=== $title ===" -ForegroundColor Yellow
}

# Function to check if Docker is running
function Check-Docker {
    try {
        docker info > $null 2>&1
        return $true
    }
    catch {
        Write-Host "Error: Docker is not running or not installed" -ForegroundColor Red
        return $false
    }
}

# Function to start services
function Start-Services {
    Print-Header "Starting Services"
    try {
        # Using current directory's docker-compose.yml
        docker-compose up --build -d
        Write-Host "Services started successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Error starting services: $_" -ForegroundColor Red
    }
}

# Function to stop services
function Stop-Services {
    Print-Header "Stopping Services"
    try {
        docker-compose down
        Write-Host "Services stopped successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Error stopping services: $_" -ForegroundColor Red
    }
}

# Function to show container status
function Show-Status {
    Print-Header "Container Status"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Function to show container logs
function Show-Logs($containerName) {
    if ([string]::IsNullOrEmpty($containerName)) {
        Print-Header "Showing logs for all containers"
        docker-compose logs
    }
    else {
        Print-Header "Showing logs for $containerName"
        docker logs $containerName -f --tail 100
    }
}

# Function to show container stats
function Show-Stats {
    Print-Header "Container Stats"
    docker stats --no-stream
}

# Function to clean up Docker system
function Clean-DockerSystem {
    Print-Header "Cleaning Docker System"
    Write-Host "This will remove all unused containers, images, and volumes. Continue? (y/n)" -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -eq 'y') {
        docker-compose down
        docker system prune -af --volumes
        Write-Host "Docker system cleaned successfully" -ForegroundColor Green
    }
}

# Function to rebuild a specific service
function Rebuild-Service($serviceName) {
    if ([string]::IsNullOrEmpty($serviceName)) {
        Write-Host "Error: Please specify a service name" -ForegroundColor Red
        return
    }
    Print-Header "Rebuilding service: $serviceName"
    docker-compose up -d --no-deps --build $serviceName
}

# Function to show quick reference
function Show-QuickReference {
    Print-Header "Quick Reference Guide"
    Write-Host @"
Available Services:
------------------
frontend          - Frontend Service (http://localhost:5000)
api_gateway       - API Gateway (http://localhost:5001)
order_service     - Order Service (http://localhost:5002)
inventory_service - Inventory Service (http://localhost:5003)
postgres          - PostgreSQL Database (localhost:5432)
prometheus       - Prometheus (http://localhost:9090)
loki             - Loki (http://localhost:3100)
tempo            - Tempo (http://localhost:4317)

Database Connection:
------------------
Host: localhost
Port: 5432
Database: demo_db
Username: demo_user
Password: demo_password

Common Commands:
--------------
docker ps                    # List running containers
docker logs [service]        # View service logs
docker-compose up --build -d # Start all services
docker-compose down         # Stop all services
"@
}

# Main menu
function Show-Menu {
    Write-Host "`nDocker Management Script" -ForegroundColor Green
    Write-Host "1. Start all services"
    Write-Host "2. Stop all services"
    Write-Host "3. Show container status"
    Write-Host "4. Show container logs"
    Write-Host "5. Show container stats"
    Write-Host "6. Rebuild specific service"
    Write-Host "7. Clean Docker system"
    Write-Host "8. Show quick reference"
    Write-Host "0. Exit"
}

# Check if Docker is running
if (-not (Check-Docker)) {
    exit 1
}

# Show the quick reference guide at startup
Show-QuickReference

# Main loop
while ($true) {
    Show-Menu
    $choice = Read-Host "`nEnter your choice (0-8)"
    
    switch ($choice) {
        0 { 
            Write-Host "Exiting..."
            exit 
        }
        1 { Start-Services }
        2 { Stop-Services }
        3 { Show-Status }
        4 {
            Write-Host "Available services: frontend, api_gateway, order_service, inventory_service, postgres, prometheus, loki, tempo"
            $containerName = Read-Host "Enter container name (press Enter for all)"
            Show-Logs $containerName
        }
        5 { Show-Stats }
        6 {
            Write-Host "Available services: frontend, api_gateway, order_service, inventory_service"
            $serviceName = Read-Host "Enter service name to rebuild"
            Rebuild-Service $serviceName
        }
        7 { Clean-DockerSystem }
        8 { Show-QuickReference }
        default { Write-Host "Invalid option" -ForegroundColor Red }
    }
    
    Write-Host "`nPress Enter to continue..."
    Read-Host
}