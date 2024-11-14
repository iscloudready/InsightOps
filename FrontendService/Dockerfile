# Base image with ASP.NET runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 80

# Install curl for health checks
RUN apt-get update && apt-get install -y curl iputils-ping && rm -rf /var/lib/apt/lists/*

# Build image with .NET SDK
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["FrontendService.csproj", "./"]
RUN dotnet restore "FrontendService.csproj"
COPY . .
RUN dotnet build "FrontendService.csproj" -c Release -o /app/build

# Publish image for optimized release
FROM build AS publish
RUN dotnet publish "FrontendService.csproj" -c Release -o /app/publish

# Final runtime image
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
RUN apt-get update && apt-get install -y curl iputils-ping && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["dotnet", "FrontendService.dll"]