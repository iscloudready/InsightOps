# Base image with ASP.NET runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 80

# Install curl for health checks
RUN apt-get update && apt-get install -y curl iputils-ping && rm -rf /var/lib/apt/lists/*

# Build image with .NET SDK
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["InventoryService.csproj", "./"]
RUN dotnet restore "InventoryService.csproj"
COPY . .
RUN dotnet build "InventoryService.csproj" -c Release -o /app/build

# Publish image for optimized release
FROM build AS publish
RUN dotnet publish "InventoryService.csproj" -c Release -o /app/publish

# Final runtime image
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
RUN apt-get update && apt-get install -y curl iputils-ping && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["dotnet", "InventoryService.dll"]