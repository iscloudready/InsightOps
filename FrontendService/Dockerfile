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

# Copy shared projects first
COPY ["../InsightOps.Observability/Observability.csproj", "../InsightOps.Observability/"]
COPY ["FrontendService.csproj", "./"]

# Restore packages with detailed logging
RUN dotnet restore "FrontendService.csproj" --verbosity detailed > /tmp/restore.log 2>&1 || (cat /tmp/restore.log && exit 1)

# Copy remaining files
COPY . .
COPY ["../InsightOps.Observability/", "../InsightOps.Observability/"]

# Build with detailed logging
RUN dotnet build "FrontendService.csproj" -c Release -o /app/build --verbosity detailed > /tmp/build.log 2>&1 || (cat /tmp/build.log && exit 1)

# Publish stage
FROM build AS publish
RUN dotnet publish "FrontendService.csproj" -c Release -o /app/publish /p:UseAppHost=false --verbosity detailed > /tmp/publish.log 2>&1 || (cat /tmp/publish.log && exit 1)

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