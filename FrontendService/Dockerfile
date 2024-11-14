# FrontendService Dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 80
RUN apt-get update \
    && apt-get install -y curl iputils-ping \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["FrontendService.csproj", "./"]
RUN dotnet restore "FrontendService.csproj"
COPY . .
RUN dotnet build "FrontendService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "FrontendService.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
HEALTHCHECK CMD curl -f http://localhost:80/health || exit 1
ENTRYPOINT ["dotnet", "FrontendService.dll"]