# PowerShell script to build with Visual Studio 2026 environment
Write-Host "Setting up Visual Studio 2026 environment for build..." -ForegroundColor Green

# Find the latest Visual Studio installation
$vsPath = & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath

if (-not $vsPath) {
    Write-Host "ERROR: Could not find Visual Studio installation" -ForegroundColor Red
    exit 1
}

Write-Host "Found Visual Studio at: $vsPath" -ForegroundColor Green

# Set environment variables for VS 2026
$env:VCINSTALLDIR = "$vsPath\VC\\"
$env:VisualStudioVersion = "18.0"
$env:WindowsSDKVersion = "10.0"

# Set CMAKE_GENERATOR explicitly
$env:CMAKE_GENERATOR = "Visual Studio 17 2022"
$env:CMAKE_SYSTEM_VERSION = "10.0"

Write-Host "Environment variables set:" -ForegroundColor Green
Write-Host "  CMAKE_GENERATOR = $($env:CMAKE_GENERATOR)" -ForegroundColor Yellow

# Clean previous build attempts
Write-Host "`nCleaning previous build artifacts..." -ForegroundColor Green
flutter clean

# Remove any cached CMake files
if (Test-Path "windows\flutter\ephemeral\CMakeCache.txt") {
    Remove-Item "windows\flutter\ephemeral\CMakeCache.txt" -Force
    Write-Host "Removed windows\flutter\ephemeral\CMakeCache.txt" -ForegroundColor Yellow
}

if (Test-Path "windows\CMakeCache.txt") {
    Remove-Item "windows\CMakeCache.txt" -Force
    Write-Host "Removed windows\CMakeCache.txt" -ForegroundColor Yellow
}

# Get dependencies
Write-Host "`nGetting dependencies..." -ForegroundColor Green
flutter pub get

# Now try the build
Write-Host "`nStarting build with VS 2026 environment..." -ForegroundColor Green
$buildResult = flutter build windows --release

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n=========================================" -ForegroundColor Green
    Write-Host "BUILD SUCCESSFUL!" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host "Executable location: build\windows\x64\runner\Release\ivpn_new.exe" -ForegroundColor Yellow
} else {
    Write-Host "`n=========================================" -ForegroundColor Red
    Write-Host "BUILD FAILED!" -ForegroundColor Red
    Write-Host "=========================================" -ForegroundColor Red
    exit $LASTEXITCODE
}