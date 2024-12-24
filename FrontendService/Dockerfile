# Base stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
USER root
WORKDIR /app

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
    mkdir -p /app/Keys && \
    mkdir -p /var/run/docker && \
    chmod -R 777 /app/Keys && \
    chmod -R 777 /var/run/docker

ENV PATH="/usr/bin:${PATH}"
EXPOSE 80

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ["InsightOps.Observability/Observability.csproj", "InsightOps.Observability/"]
COPY ["FrontendService/FrontendService.csproj", "FrontendService/"]
RUN dotnet restore "InsightOps.Observability/Observability.csproj" && \
    dotnet restore "FrontendService/FrontendService.csproj"

COPY ["InsightOps.Observability/", "InsightOps.Observability/"]
COPY ["FrontendService/", "FrontendService/"]
WORKDIR "/src/FrontendService"
RUN dotnet build "FrontendService.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "FrontendService.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Final stage
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Set permissions for mounted volumes
RUN mkdir -p /app/Keys && \
    chmod -R 777 /app/Keys && \
    mkdir -p /var/run/docker && \
    chmod -R 777 /var/run/docker

USER root
ENV ASPNETCORE_ENVIRONMENT=Docker
ENTRYPOINT ["dotnet", "FrontendService.dll"]