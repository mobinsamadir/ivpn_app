# PowerShell build script for Flutter project
Write-Host "=== Flutter Project Build Script ==="
Write-Host "Timestamp: $(Get-Date)"

# Clean
Write-Host "1. Cleaning project..."
flutter clean

# Get dependencies
Write-Host "2. Getting dependencies..."
flutter pub get

# Analyze
Write-Host "3. Analyzing code..."
flutter analyze . 2>$null

# Build Android
Write-Host "4. Building Android..."
flutter build apk --release

# Build Windows
Write-Host "5. Building Windows..."
flutter build windows --release

Write-Host "=== Build Complete ==="
Write-Host "Android APK: build/app/outputs/flutter-apk/app-release.apk"
Write-Host "Windows: build/windows/runner/Release/"