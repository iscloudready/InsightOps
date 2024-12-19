# Base stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
USER root
WORKDIR /app
#EXPOSE 80

# Install required tools
RUN apt-get update && \
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 999 docker && \
    groupadd -g 1001 appgroup && \
    useradd -u 1001 -g appgroup -G docker -s /bin/bash -m appuser && \
    mkdir -p /app/Keys && \
    chown -R appuser:docker /app && \
    chmod 755 /app/Keys && \
    chmod 777 /var/run && \
    chmod 666 /var/run/docker.sock && \
    chmod -R 755 /var/run/docker && \
    chmod 777 /tmp

# After installing Docker CLI
ENV PATH="/usr/bin:${PATH}"

EXPOSE 5010

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