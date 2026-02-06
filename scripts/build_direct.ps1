Write-Host "=== IVPN Direct Build Script ===" -ForegroundColor Cyan

# 1. Clean (redundant but safe)
flutter clean
Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\windows\build -ErrorAction SilentlyContinue

# 2. Get dependencies
Write-Host "Getting dependencies..." -ForegroundColor Yellow
flutter pub get

# 3. Check environment
Write-Host "Checking environment..." -ForegroundColor Yellow
flutter doctor -v | Select-String -Pattern "Visual Studio|CMake|Windows"

# 4. Build using Flutter directly (bypasses manual_build.ps1 CMake issues)
Write-Host "Building with Flutter..." -ForegroundColor Yellow
flutter build windows --release --verbose

# 5. Verify
$exePath = ".\build\windows\runner\Release\ivpn_new.exe"
if (Test-Path $exePath) {
    Write-Host "`n✅ BUILD SUCCESSFUL!" -ForegroundColor Green
    Write-Host "Executable: $exePath" -ForegroundColor Green
    $sizeMB = [math]::Round((Get-Item $exePath).Length / 1MB, 2)
    Write-Host "Size: ${sizeMB} MB" -ForegroundColor Green
    
    # Also check for other build files
    Write-Host "`nBuild artifacts:" -ForegroundColor Cyan
    Get-ChildItem ".\build\windows\runner\Release\" | Format-Table Name, Length
} else {
    Write-Host "`n❌ Release build failed, trying debug..." -ForegroundColor Red
    flutter build windows --debug
    
    $debugExe = ".\build\windows\runner\Debug\ivpn_new.exe"
    if (Test-Path $debugExe) {
        Write-Host "✅ Debug build successful: $debugExe" -ForegroundColor Green
    } else {
        Write-Host "❌ Both release and debug builds failed" -ForegroundColor Red
    }
}

Write-Host "`n=== Build process complete ===" -ForegroundColor Cyan