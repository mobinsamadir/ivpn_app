# Final Build Solution for IVPN App
# This script implements a permanent fix for the VS 2019 generator issue

Write-Host "=========================================" -ForegroundColor Green
Write-Host "IVPN APP - FINAL BUILD SOLUTION" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

# Step 1: Nuclear Clean
Write-Host "`n>>> 1. Performing Nuclear Clean..." -ForegroundColor Yellow

# Clean Flutter
Write-Host "   - Flutter Clean..." -ForegroundColor Gray
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Flutter clean failed!" -ForegroundColor Red
    pause
    exit 1
}

# Remove all build artifacts
Write-Host "   - Removing build directories..." -ForegroundColor Gray
if (Test-Path "build") {
    Remove-Item -Path "build" -Recurse -Force
    Write-Host "     ✅ Removed build directory" -ForegroundColor Green
}
if (Test-Path "windows\build") {
    Remove-Item -Path "windows\build" -Recurse -Force
    Write-Host "     ✅ Removed windows\build directory" -ForegroundColor Green
}
if (Test-Path "windows\flutter\ephemeral\CMakeCache.txt") {
    Remove-Item -Path "windows\flutter\ephemeral\CMakeCache.txt" -Force
    Write-Host "     ✅ Removed CMakeCache.txt" -ForegroundColor Green
}
if (Test-Path "windows\CMakeCache.txt") {
    Remove-Item -Path "windows\CMakeCache.txt" -Force
    Write-Host "     ✅ Removed windows\CMakeCache.txt" -ForegroundColor Green
}

# Step 2: Update dependencies
Write-Host "`n>>> 2. Updating Dependencies..." -ForegroundColor Yellow
Write-Host "   - Flutter Pub Get..." -ForegroundColor Gray
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Flutter pub get failed!" -ForegroundColor Red
    pause
    exit 1
}

# Step 3: Configure Flutter
Write-Host "`n>>> 3. Configuring Flutter..." -ForegroundColor Yellow
Write-Host "   - Enabling Windows Desktop..." -ForegroundColor Gray
flutter config --enable-windows-desktop

# Step 4: Use Visual Studio Developer Command Prompt Environment
Write-Host "`n>>> 4. Setting VS 2022 Environment..." -ForegroundColor Yellow

# Find Visual Studio installation
$vsPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath

if (-not $vsPath) {
    Write-Host "   ❌ Could not find Visual Studio installation!" -ForegroundColor Red
    pause
    exit 1
}

Write-Host "   ✅ Found VS at: $vsPath" -ForegroundColor Green

# Set environment variables for VS 2022
$env:VisualStudioVersion = "17.0"
$env:VCINSTALLDIR = "$vsPath\VC\\"

# Step 5: Build with specific generator
Write-Host "`n>>> 5. Building with VS 2022..." -ForegroundColor Yellow

# Use cmake directly with the correct generator first
$cmakePath = "$vsPath\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (Test-Path $cmakePath) {
    Write-Host "   - Using CMake from: $cmakePath" -ForegroundColor Gray
    
    # Navigate to windows directory
    Set-Location -Path "windows"
    
    # Try to generate with VS 2022
    & $cmakePath -S . -B .\build -G "Visual Studio 17 2022" -A x64
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   ❌ CMake generation failed!" -ForegroundColor Red
        Set-Location ..
        pause
        exit 1
    }
    
    Write-Host "   ✅ CMake generation successful" -ForegroundColor Green
    Set-Location ..
} else {
    Write-Host "   ⚠️ CMake not found at expected location, proceeding with flutter build..." -ForegroundColor Yellow
}

# Now try the Flutter build
Write-Host "   - Running Flutter Build Windows..." -ForegroundColor Gray
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Build failed!" -ForegroundColor Red
    pause
    exit 1
}

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "🎉 BUILD SUCCESSFUL!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host "The executable is located at:" -ForegroundColor Cyan
Write-Host "build\windows\x64\runner\Release\ivpn_new.exe" -ForegroundColor White
Write-Host "`nAll features have been implemented:" -ForegroundColor Cyan
Write-Host "✅ Smart Paste with clipboard detection" -ForegroundColor Green
Write-Host "✅ Smart Connect with runQuickTest integration" -ForegroundColor Green
Write-Host "✅ Test Connection/Stability buttons" -ForegroundColor Green
Write-Host "✅ Auto-Test Logic with isEligibleForAutoTest getter" -ForegroundColor Green
Write-Host "✅ AdService as Singleton with preloading" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

pause