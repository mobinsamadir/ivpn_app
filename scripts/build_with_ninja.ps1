# build_with_ninja.ps1
Write-Host "=== Building with Ninja (bypasses VS issues) ===" -ForegroundColor Cyan

cd C:\Users\Mobin-pc\ivpn_new

# Clean
flutter clean
Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\windows\build -ErrorAction SilentlyContinue

# Get dependencies
flutter pub get

# Check if Ninja is installed
$ninjaPath = Get-Command ninja -ErrorAction SilentlyContinue
if (-not $ninjaPath) {
    Write-Host "Ninja is not installed. Installing via winget..." -ForegroundColor Yellow
    winget install -e --id Kitware.Ninja
}

# Set environment to use Ninja
$env:CMAKE_GENERATOR = "Ninja"
$env:CMAKEKE_BUILD_TYPE = "Release"

# Build
Write-Host "Building with Ninja..." -ForegroundColor Yellow
flutter build windows --release

# Check result
if (Test-Path ".\build\windows\runner\Release\ivpn_new.exe") {
    Write-Host " Build successful with Ninja!" -ForegroundColor Green
} else {
    Write-Host " Build failed" -ForegroundColor Red
}
