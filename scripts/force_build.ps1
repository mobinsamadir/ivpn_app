# Force build with Visual Studio 2022
Write-Host "=========================================" -ForegroundColor Green
Write-Host "IVPN Force Build with Visual Studio 2022" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

# Clean previous build artifacts
Write-Host "`nStep 1: Cleaning previous build artifacts..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "Flutter clean failed!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Remove any cached CMake files
Write-Host "`nStep 2: Removing cached CMake files..." -ForegroundColor Yellow
$pathsToRemove = @(
    "windows\flutter\ephemeral\CMakeCache.txt",
    "windows\CMakeCache.txt",
    "windows\runner\x64",
    "windows\runner\Debug",
    "windows\runner\Release",
    "windows\runner\Profile",
    "windows\build",
    "build"
)

foreach ($path in $pathsToRemove) {
    if (Test-Path $path) {
        Write-Host "Removing $path" -ForegroundColor Cyan
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Upgrade dependencies
Write-Host "`nStep 3: Upgrading dependencies..." -ForegroundColor Yellow
flutter pub upgrade
if ($LASTEXITCODE -ne 0) {
    Write-Host "Flutter pub upgrade failed!" -ForegroundColor Red
    # Continue anyway as this sometimes fails due to version constraints
}

# Get dependencies
Write-Host "`nStep 4: Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "Flutter pub get failed!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Configure Flutter
Write-Host "`nStep 5: Configuring Flutter..." -ForegroundColor Yellow
flutter config --enable-windows-desktop

# Set environment variable for CMake generator
$env:CMAKE_GENERATOR = "Visual Studio 17 2022"
$env:FLUTTER_ENGINE_REPO_OVERRIDE = ""

Write-Host "`nStep 6: Building Windows application..." -ForegroundColor Yellow
Write-Host "Using CMAKE_GENERATOR: $env:CMAKE_GENERATOR" -ForegroundColor Cyan

# Try to build with specific generator
$buildArgs = @("build", "windows", "--release", "-v")
Start-Process -FilePath "flutter.exe" -ArgumentList $buildArgs -Wait -NoNewWindow -PassThru

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
} else {
    Write-Host "`n=========================================" -ForegroundColor Green
    Write-Host "Build completed successfully!" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Green
}