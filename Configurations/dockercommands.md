# Quick commands without using the script
# Start services in background
docker-compose up -d --build

# View logs in real-time
docker-compose logs -f

# Stop all services
docker-compose down

# Remove all containers and volumes
docker-compose down -v

# Show running containers
docker ps

# Show all containers (including stopped)
docker ps -a

# Remove all stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes
docker volume prune

# Show container resources usage
docker stats

# Restart a specific service
docker-compose restart service_name

# Rebuild a specific service
docker-compose up -d --no-deps --build service_name

# Enter a container's shell
docker exec -it container_name bash

# View container logs
docker logs container_name

# Follow container logs
docker logs -f container_name

# Check container health
docker inspect container_name

# Show container IP address
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' container_name