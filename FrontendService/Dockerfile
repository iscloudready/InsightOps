# FrontendService Dockerfile
# Base stage for running the application
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
ARG BUILD_CONFIGURATION=Release
USER root
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

# Install curl and wget for resource fetching and health checks
RUN apt-get update \
    && apt-get install -y wget curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch to a non-root user after installing necessary packages for security
RUN useradd -m appuser && chown -R appuser /app
USER appuser

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["FrontendService.csproj", "."]
RUN dotnet restore "./FrontendService.csproj"
COPY . .
WORKDIR "/src/."
RUN dotnet build "./FrontendService.csproj" -c $BUILD_CONFIGURATION -o /app/build

# Publish stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./FrontendService.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# Final stage for running the application
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "FrontendService.dll"]
