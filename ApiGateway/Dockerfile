# Base stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
USER root
WORKDIR /app
EXPOSE 80
EXPOSE 7237

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

# Copy csproj files first
COPY ["InsightOps.Observability/Observability.csproj", "InsightOps.Observability/"]
COPY ["ApiGateway/ApiGateway.csproj", "ApiGateway/"]

# Restore NuGet packages
RUN dotnet restore "InsightOps.Observability/Observability.csproj" && \
    dotnet restore "ApiGateway/ApiGateway.csproj"

# Copy everything else
COPY ["InsightOps.Observability/", "InsightOps.Observability/"]
COPY ["ApiGateway/", "ApiGateway/"]

# Build the project
WORKDIR "/src/ApiGateway"
RUN dotnet build "ApiGateway.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "ApiGateway.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Final stage
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
USER appuser
ENV ASPNETCORE_ENVIRONMENT=Docker
ENTRYPOINT ["dotnet", "ApiGateway.dll"]