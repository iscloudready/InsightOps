# Base stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
USER root
WORKDIR /app
EXPOSE 80
EXPOSE 5010

# Install required tools
RUN apt-get update \
    && apt-get install -y wget curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 1001 appgroup \
    && useradd -u 1001 -g appgroup -s /bin/bash -m appuser \
    && chown -R appuser:appgroup /app

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Clear NuGet cache and restore dependencies
RUN dotnet nuget locals all --clear
COPY ["FrontendService.csproj", "./"]
RUN dotnet restore "FrontendService.csproj" --verbosity detailed || (echo "Restore failed. Check dependencies." && exit 1)

# Copy source files and configuration files
COPY . .
COPY appsettings.json ./appsettings.json
COPY appsettings.Development.json ./appsettings.Development.json
COPY appsettings.Docker.json ./appsettings.Docker.json

# Build the application
RUN dotnet build "FrontendService.csproj" -c Release -o /app/build --verbosity detailed || (echo "Build failed. Check errors above." && exit 1)

# Publish stage
FROM build AS publish
RUN dotnet publish "FrontendService.csproj" -c Release -o /app/publish /p:UseAppHost=false --verbosity detailed || (echo "Publish failed. Check errors above." && exit 1)

# Final stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Copy published output to final container
COPY --from=publish /app/publish .

# Create keys directory with proper permissions
RUN mkdir -p /app/Keys && \
    chown -R appuser:appgroup /app/Keys && \
    chmod 755 /app/Keys

USER appuser
ENV ASPNETCORE_ENVIRONMENT=Docker
ENTRYPOINT ["dotnet", "FrontendService.dll"]
