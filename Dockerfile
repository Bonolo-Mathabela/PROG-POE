# syntax=docker/dockerfile:1
# =====================================================================
#  RaceDay MVC - multi-stage Docker build
#  Build:  docker build -t raceday-mvc .
#  Run:    docker run -d -p 8080:8080 --name raceday-mvc raceday-mvc
#  Open:   http://localhost:8080
#  The container calls the RaceDay API running on the host machine
#  (http://host.docker.internal:5027 by default).
# =====================================================================

# ---------- Stage 1: restore, build and publish with the full SDK ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy only the project file first so the NuGet restore layer is cached
# and is only re-run when dependencies change.
COPY RaceDay_MVC/RaceDay_MVC.csproj RaceDay_MVC/
RUN dotnet restore RaceDay_MVC/RaceDay_MVC.csproj

# Copy the rest of the MVC source and publish a Release build.
COPY RaceDay_MVC/ RaceDay_MVC/
RUN dotnet publish RaceDay_MVC/RaceDay_MVC.csproj \
        --configuration Release \
        --no-restore \
        --output /app/publish \
        /p:UseAppHost=false

# ---------- Stage 2: small runtime-only image ----------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

# Kestrel listens on 8080 inside the container. The API address can be
# overridden at run time with -e ApiSettings__BaseUrl=...
ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    ApiSettings__BaseUrl=http://host.docker.internal:5027

EXPOSE 8080

COPY --from=build /app/publish .

# Run as the built-in non-root "app" user (security best practice).
USER $APP_UID

ENTRYPOINT ["dotnet", "RaceDay_MVC.dll"]
