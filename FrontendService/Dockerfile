# Base stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
USER root
WORKDIR /app
#EXPOSE 80
EXPOSE 5010

# Install required tools
RUN apt-get update \
    && apt-get install -y wget curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 999 docker \
    && groupadd -g 1001 appgroup \
    && useradd -u 1001 -g appgroup -G docker -s /bin/bash -m appuser \
    && chown -R appuser:appgroup /app

# After creating the appuser
RUN groupadd -g 999 docker && \
    usermod -aG docker appuser

# Make sure docker socket is accessible
RUN chmod 666 /var/run/docker.sock

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy all csproj files first for better layer caching
COPY ["InsightOps.Observability/Observability.csproj", "InsightOps.Observability/"]
COPY ["FrontendService/FrontendService.csproj", "FrontendService/"]

# Restore NuGet packages
RUN dotnet restore "InsightOps.Observability/Observability.csproj" && \
    dotnet restore "FrontendService/FrontendService.csproj"

# Copy everything else
COPY ["InsightOps.Observability/", "InsightOps.Observability/"]
COPY ["FrontendService/", "FrontendService/"]

# Build the Frontend project
WORKDIR "/src/FrontendService"
RUN dotnet build "FrontendService.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "FrontendService.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Final stage
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Create keys directory with proper permissions
RUN mkdir -p /app/Keys && \
    chown -R appuser:appgroup /app/Keys && \
    chmod 755 /app/Keys

USER appuser
ENV ASPNETCORE_ENVIRONMENT=Docker
ENTRYPOINT ["dotnet", "FrontendService.dll"]