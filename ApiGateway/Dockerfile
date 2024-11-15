# ApiGateway Dockerfile
# Base stage for running the application
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
ARG BUILD_CONFIGURATION=Release
USER root
WORKDIR /app
EXPOSE 80  # HTTP port
EXPOSE 7237  # Custom port (if required)

# Install curl and wget for resource fetching and health checks
RUN apt-get update \
    && apt-get install -y wget curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch to a non-root user after installing necessary packages for security
RUN useradd -m -u 1001 -g 1001 appuser && chown -R appuser /app
USER appuser

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["ApiGateway.csproj", "."]
RUN dotnet restore "./ApiGateway.csproj"
COPY . .
WORKDIR "/src/."
RUN dotnet build "./ApiGateway.csproj" -c $BUILD_CONFIGURATION -o /app/build

# Publish stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./ApiGateway.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# Final stage for running the application
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENV ASPNETCORE_ENVIRONMENT=Docker
ENTRYPOINT ["dotnet", "ApiGateway.dll"]