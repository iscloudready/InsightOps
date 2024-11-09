# PowerShell script for Docker management in Windows

# Colors for better readability
$Red = [System.ConsoleColor]::Red
$Green = [System.ConsoleColor]::Green
$Yellow = [System.ConsoleColor]::Yellow

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
    Set-Location -Path ".\Configurations"
    docker-compose up --build -d
    Set-Location -Path ".."
}

# Function to stop services
function Stop-Services {
    Print-Header "Stopping Services"
    Set-Location -Path ".\Configurations"
    docker-compose down
    Set-Location -Path ".."
}

# Function to show container status
function Show-Status {
    Print-Header "Container Status"
    docker-compose ps
}

# Function to show container logs
function Show-Logs($containerName) {
    if ([string]::IsNullOrEmpty($containerName)) {
        Print-Header "Showing logs for all containers"
        docker-compose logs
    }
    else {
        Print-Header "Showing logs for $containerName"
        docker-compose logs $containerName
    }
}

# Function to show container stats
function Show-Stats {
    Print-Header "Container Stats"
    docker stats --no-stream
}

# Function to show running containers
function Show-Containers {
    Print-Header "Running Containers"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Function to show Docker images
function Show-Images {
    Print-Header "Docker Images"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
}

# Function to show Docker volumes
function Show-Volumes {
    Print-Header "Docker Volumes"
    docker volume ls
}

# Function to show Docker networks
function Show-Networks {
    Print-Header "Docker Networks"
    docker network ls
}

# Function to clean up Docker system
function Clean-DockerSystem {
    Print-Header "Cleaning Docker System"
    Write-Host "Removing unused containers..."
    docker container prune -f
    Write-Host "Removing unused images..."
    docker image prune -f
    Write-Host "Removing unused volumes..."
    docker volume prune -f
    Write-Host "Removing unused networks..."
    docker network prune -f
}

# Function to restart a specific service
function Restart-Service($serviceName) {
    if ([string]::IsNullOrEmpty($serviceName)) {
        Write-Host "Error: Please specify a service name" -ForegroundColor Red
        return
    }
    Print-Header "Restarting service: $serviceName"
    Set-Location -Path ".\Configurations"
    docker-compose restart $serviceName
    Set-Location -Path ".."
}

# Function to rebuild a specific service
function Rebuild-Service($serviceName) {
    if ([string]::IsNullOrEmpty($serviceName)) {
        Write-Host "Error: Please specify a service name" -ForegroundColor Red
        return
    }
    Print-Header "Rebuilding service: $serviceName"
    Set-Location -Path ".\Configurations"
    docker-compose up -d --no-deps --build $serviceName
    Set-Location -Path ".."
}

# Function to show menu
function Show-Menu {
    Write-Host "`nDocker Management Script" -ForegroundColor Green
    Write-Host "1. Start services"
    Write-Host "2. Stop services"
    Write-Host "3. Show container status"
    Write-Host "4. Show container logs"
    Write-Host "5. Show container stats"
    Write-Host "6. Show running containers"
    Write-Host "7. Show Docker images"
    Write-Host "8. Show Docker volumes"
    Write-Host "9. Show Docker networks"
    Write-Host "10. Clean Docker system"
    Write-Host "11. Restart specific service"
    Write-Host "12. Rebuild specific service"
    Write-Host "0. Exit"
}

# Quick Commands Reference (for VSCode terminal)
function Show-QuickCommands {
    Print-Header "Quick Docker Commands Reference"
    Write-Host @"
Common Docker Commands:
----------------------
cd Configurations
docker-compose up --build -d     # Start all services
docker-compose down              # Stop all services
docker ps                        # List running containers
docker ps -a                     # List all containers
docker logs container_name       # View container logs
docker exec -it container_name sh # Enter container shell

Service Names in your setup:
---------------------------
postgres
frontend
api_gateway
order_service
inventory_service
prometheus
loki
tempo
grafana

Examples:
---------
docker logs order_service        # View order service logs
docker restart frontend         # Restart frontend service
docker exec -it postgres sh     # Enter postgres container

URLs after startup:
------------------
Frontend:          http://localhost:5000
API Gateway:       http://localhost:5001
Order Service:     http://localhost:5002
Inventory Service: http://localhost:5003
Grafana:          http://localhost:3000
Prometheus:       http://localhost:9090
"@
}

# Main script
if (-not (Check-Docker)) {
    exit 1
}

# Show the quick commands reference first
Show-QuickCommands

# Main loop
while ($true) {
    Show-Menu
    $choice = Read-Host "Enter your choice (0-12)"
    
    switch ($choice) {
        0 { 
            Write-Host "Exiting..."
            exit 
        }
        1 { Start-Services }
        2 { Stop-Services }
        3 { Show-Status }
        4 {
            $containerName = Read-Host "Enter container name (press Enter for all)"
            Show-Logs $containerName
        }
        5 { Show-Stats }
        6 { Show-Containers }
        7 { Show-Images }
        8 { Show-Volumes }
        9 { Show-Networks }
        10 { Clean-DockerSystem }
        11 {
            $serviceName = Read-Host "Enter service name"
            Restart-Service $serviceName
        }
        12 {
            $serviceName = Read-Host "Enter service name"
            Rebuild-Service $serviceName
        }
        default { Write-Host "Invalid option" -ForegroundColor Red }
    }
    
    Write-Host "`nPress Enter to continue..."
    Read-Host
}