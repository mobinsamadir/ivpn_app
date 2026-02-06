# ==================================================
#  IVPN BUILD SCRIPT - English Version
# ==================================================

$PROJECT_ROOT = Get-Location
$BUILD_LOG = "$PROJECT_ROOT\build_log.txt"
$ERROR_LOG = "$PROJECT_ROOT\error_log.txt"

# Clear old logs
if (Test-Path $BUILD_LOG) { Remove-Item $BUILD_LOG -Force }
if (Test-Path $ERROR_LOG) { Remove-Item $ERROR_LOG -Force }

Write-Host "=== Starting IVPN Build Process ===" -ForegroundColor Cyan
Write-Host "Project Path: $PROJECT_ROOT" -ForegroundColor Cyan

# 1. Kill running processes
Write-Host "1. Checking for running processes..." -ForegroundColor Yellow
$processes = Get-Process -Name "ivpn_new", "xray", "sing-box", "flutter" -ErrorAction SilentlyContinue
if ($processes) {
    Write-Host "   Found $($processes.Count) running processes" -ForegroundColor Yellow
    foreach ($proc in $processes) {
        Write-Host "   Killing: $($proc.Name) (PID: $($proc.Id))"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
    Write-Host "   OK: All processes stopped" -ForegroundColor Green
} else {
    Write-Host "   OK: No running processes found" -ForegroundColor Green
}

# 2. Clean build artifacts
Write-Host "2. Cleaning previous builds..." -ForegroundColor Yellow
Remove-Item -Path "$PROJECT_ROOT\build" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$PROJECT_ROOT\windows\build" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$PROJECT_ROOT\.dart_tool" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "   OK: Cleanup complete" -ForegroundColor Green

# 3. Get dependencies
Write-Host "3. Getting Flutter dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -eq 0) {
    Write-Host "   OK: Dependencies retrieved" -ForegroundColor Green
} else {
    Write-Host "   ERROR: Failed to get dependencies" -ForegroundColor Red
    exit 1
}

# 4. Build with Flutter
Write-Host "4. Building with Flutter..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -eq 0) {
    Write-Host "   SUCCESS: Build completed" -ForegroundColor Green
} else {
    Write-Host "   Trying debug build..." -ForegroundColor Yellow
    flutter build windows --debug
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   FAILED: Build failed" -ForegroundColor Red
        exit 1
    }
}

# 5. Check for executable
Write-Host "5. Looking for executable..." -ForegroundColor Yellow
$exePath = "$PROJECT_ROOT\build\windows\runner\Release\ivpn_new.exe"
if (-not (Test-Path $exePath)) {
    $exePath = "$PROJECT_ROOT\build\windows\runner\Debug\ivpn_new.exe"
}

if (Test-Path $exePath) {
    $sizeMB = [math]::Round((Get-Item $exePath).Length / 1MB, 2)
    Write-Host "`n=== BUILD SUCCESSFUL ===" -ForegroundColor Green
    Write-Host "Executable: $exePath" -ForegroundColor White
    Write-Host "Size: ${sizeMB} MB" -ForegroundColor White
    
    # Optional run
    $runApp = Read-Host "`nRun the application? (y/N)"
    if ($runApp -eq 'y') {
        Write-Host "Launching application..." -ForegroundColor Cyan
        Start-Process -FilePath $exePath
    }
} else {
    Write-Host "`n=== BUILD FAILED ===" -ForegroundColor Red
    Write-Host "No executable found" -ForegroundColor Red
}
