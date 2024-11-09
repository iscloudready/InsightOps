#!/bin/bash

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}\n"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running or not installed${NC}"
        exit 1
    fi
}

# Function to start services
start_services() {
    print_header "Starting Services"
    cd Configurations
    docker-compose up --build -d
    cd ..
}

# Function to stop services
stop_services() {
    print_header "Stopping Services"
    cd Configurations
    docker-compose down
    cd ..
}

# Function to show container status
show_status() {
    print_header "Container Status"
    docker-compose ps
}

# Function to show container logs
show_logs() {
    if [ -z "$1" ]; then
        print_header "Showing logs for all containers"
        docker-compose logs
    else
        print_header "Showing logs for $1"
        docker-compose logs "$1"
    fi
}

# Function to show container stats
show_stats() {
    print_header "Container Stats"
    docker stats --no-stream
}

# Function to show running containers
show_containers() {
    print_header "Running Containers"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Function to show Docker images
show_images() {
    print_header "Docker Images"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
}

# Function to show Docker volumes
show_volumes() {
    print_header "Docker Volumes"
    docker volume ls
}

# Function to show Docker networks
show_networks() {
    print_header "Docker Networks"
    docker network ls
}

# Function to clean up Docker system
clean_system() {
    print_header "Cleaning Docker System"
    echo "Removing unused containers..."
    docker container prune -f
    echo "Removing unused images..."
    docker image prune -f
    echo "Removing unused volumes..."
    docker volume prune -f
    echo "Removing unused networks..."
    docker network prune -f
}

# Function to restart a specific service
restart_service() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify a service name${NC}"
        return 1
    fi
    print_header "Restarting service: $1"
    cd Configurations
    docker-compose restart "$1"
    cd ..
}

# Function to rebuild a specific service
rebuild_service() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify a service name${NC}"
        return 1
    fi
    print_header "Rebuilding service: $1"
    cd Configurations
    docker-compose up -d --no-deps --build "$1"
    cd ..
}

# Function to show environment variables of a container
show_env() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify a container name${NC}"
        return 1
    fi
    print_header "Environment variables for: $1"
    docker exec "$1" env
}

# Function to enter a container shell
enter_container() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please specify a container name${NC}"
        return 1
    fi
    print_header "Entering container: $1"
    docker exec -it "$1" /bin/bash || docker exec -it "$1" /bin/sh
}

# Main menu
show_menu() {
    echo -e "\n${GREEN}Docker Management Script${NC}"
    echo "1. Start services"
    echo "2. Stop services"
    echo "3. Show container status"
    echo "4. Show container logs"
    echo "5. Show container stats"
    echo "6. Show running containers"
    echo "7. Show Docker images"
    echo "8. Show Docker volumes"
    echo "9. Show Docker networks"
    echo "10. Clean Docker system"
    echo "11. Restart specific service"
    echo "12. Rebuild specific service"
    echo "13. Show container environment variables"
    echo "14. Enter container shell"
    echo "0. Exit"
}

# Check if Docker is running
check_docker

# Main loop
while true; do
    show_menu
    read -p "Enter your choice (0-14): " choice

    case $choice in
        0)
            echo "Exiting..."
            exit 0
            ;;
        1)
            start_services
            ;;
        2)
            stop_services
            ;;
        3)
            show_status
            ;;
        4)
            read -p "Enter container name (press Enter for all): " container_name
            show_logs "$container_name"
            ;;
        5)
            show_stats
            ;;
        6)
            show_containers
            ;;
        7)
            show_images
            ;;
        8)
            show_volumes
            ;;
        9)
            show_networks
            ;;
        10)
            clean_system
            ;;
        11)
            read -p "Enter service name: " service_name
            restart_service "$service_name"
            ;;
        12)
            read -p "Enter service name: " service_name
            rebuild_service "$service_name"
            ;;
        13)
            read -p "Enter container name: " container_name
            show_env "$container_name"
            ;;
        14)
            read -p "Enter container name: " container_name
            enter_container "$container_name"
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac

    read -p "Press Enter to continue..."
done