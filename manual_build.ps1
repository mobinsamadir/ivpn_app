# ==================================================
#  IVPN SMART BUILD SCRIPT (Auto-Kill & Log Tailing)
# ==================================================
# ==================================================
#  IVPN SMART BUILD SCRIPT (Auto-Kill & Log Tailing)
# ==================================================

$VS_PATH = "C:\Program Files\Microsoft Visual Studio\18\Community"
$CMAKE_EXE = "$VS_PATH\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$PROJECT_ROOT = Get-Location
$EXE_PATH = "$PROJECT_ROOT\build\windows\x64\runner\Debug\ivpn_new.exe"
$LOG_PATH = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "vpn_debug.log"

# --- 1. KILL ZOMBIE PROCESSES ---
Write-Host ">>> 1. Checking for running instances..." -ForegroundColor Cyan
$Processes = Get-Process -Name "ivpn_new", "xray" -ErrorAction SilentlyContinue
if ($Processes) {
    Write-Host "   WARNING: Found running processes. Killing them now..." -ForegroundColor Yellow
    Stop-Process -Name "ivpn_new" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "xray" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2 # Wait for Windows to release file locks
    Write-Host "   OK: Processes terminated." -ForegroundColor Green
}
else {
    Write-Host "   OK: No instances running." -ForegroundColor Green
}

# --- 2. CLEANUP (Smart Rebuild) ---
$CleanChoice = Read-Host ">>> 2. Clean build? (y/N)"
if ($CleanChoice -eq 'y') {
    Write-Host ">>> Cleaning old build files..." -ForegroundColor Cyan
    Remove-Item -Path "build" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "   OK: Cleaned." -ForegroundColor Green
}
else {
    Write-Host ">>> Skipping cleanup. Performing incremental build..." -ForegroundColor Gray
}

# --- 3. FLUTTER PUB GET ---
Write-Host ">>> 3. Updating Flutter Packages..." -ForegroundColor Cyan
$pubResult = flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL: Flutter pub get failed!" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit $LASTEXITCODE
}
Write-Host "OK: Flutter packages updated successfully." -ForegroundColor Green

# --- 4. CMAKE GENERATION ---
Write-Host ">>> 4. Generating Build Files (Force VS 2022 + x64 + v142 toolset)..." -ForegroundColor Yellow
if (!(Test-Path "build\windows\x64")) {
    New-Item -ItemType Directory -Force -Path "build\windows\x64" | Out-Null
}
Set-Location -Path "windows"
$cmakeResult = & $CMAKE_EXE -S . -B ..\build\windows\x64 -G "Visual Studio 17 2022" -A x64 -T v142
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL: CMake Generation Failed!" -ForegroundColor Red
    Set-Location -Path ".."
    Read-Host "Press Enter to exit..."
    exit $LASTEXITCODE
}
Write-Host "OK: CMake generation completed successfully." -ForegroundColor Green

# --- 5. COMPILATION ---
Write-Host ">>> 5. Compiling Project..." -ForegroundColor Yellow
$buildResult = & $CMAKE_EXE --build ..\build\windows\x64 --config Debug --target INSTALL

if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL: Compilation Failed!" -ForegroundColor Red
    Set-Location -Path ".."
    Read-Host "Press Enter to exit..."
    exit $LASTEXITCODE
}
Write-Host "OK: Compilation completed successfully." -ForegroundColor Green

# --- 6. INJECT ENGINE ---
Write-Host ">>> 6. Injecting VPN Engine (Sing-box)..." -ForegroundColor Magenta
$EngineSource = "$PROJECT_ROOT\assets\executables\windows\sing-box.exe"
$EngineDestDir = "$PROJECT_ROOT\build\windows\x64\runner\Debug\data\flutter_assets\assets\executables\windows"
$ExeDestDir = "$PROJECT_ROOT\build\windows\x64\runner\Debug"

if (!(Test-Path $EngineDestDir)) {
    New-Item -ItemType Directory -Force -Path $EngineDestDir | Out-Null
}

Copy-Item -Path $EngineSource -Destination "$ExeDestDir\sing-box.exe" -Force -ErrorAction SilentlyContinue
Copy-Item -Path $EngineSource -Destination "$EngineDestDir\sing-box.exe" -Force -ErrorAction SilentlyContinue

# Copy Geo-Assets (.db files)
$GeoAssets = Get-ChildItem -Path "$PROJECT_ROOT\assets\executables\windows\*.db" -ErrorAction SilentlyContinue
if ($GeoAssets) {
    Copy-Item -Path $GeoAssets.FullName -Destination $ExeDestDir -Force
    Copy-Item -Path $GeoAssets.FullName -Destination $EngineDestDir -Force
    Write-Host "OK: Geo-Assets (.db) injected successfully." -ForegroundColor Green
}

Write-Host "OK: Engine injected successfully."

# --- 7. RUN & LOG TAILING ---
Write-Host ">>> 7. Launching VPN Client & Tailing Logs..." -ForegroundColor Green
Set-Location -Path $PROJECT_ROOT

# Update executable path to match actual build output
$EXE_PATH = "$PROJECT_ROOT\build\windows\x64\runner\Debug\ivpn_new.exe"

# Verify executable exists before attempting to run
if (!(Test-Path $EXE_PATH)) {
    Write-Host "FAIL: Executable not found at: $EXE_PATH" -ForegroundColor Red
    Write-Host "INFO: Looking for executable in build directory..." -ForegroundColor Yellow

    # Look for executable in common Flutter Windows build locations
    $possiblePaths = @(
        "$PROJECT_ROOT\build\windows\x64\runner\Debug\ivpn_new.exe",
        "$PROJECT_ROOT\build\windows\runner\Debug\ivpn_new.exe",
        "$PROJECT_ROOT\build\windows\x64\runner\Profile\ivpn_new.exe",
        "$PROJECT_ROOT\build\windows\x64\runner\Release\ivpn_new.exe",
        "$PROJECT_ROOT\build\windows\runner\Profile\ivpn_new.exe",
        "$PROJECT_ROOT\build\windows\runner\Release\ivpn_new.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $EXE_PATH = $path
            Write-Host "OK: Found executable at: $path" -ForegroundColor Green
            break
        }
    }

    if (!(Test-Path $EXE_PATH)) {
        Write-Host "FAIL: No executable found in any expected location!" -ForegroundColor Red
        Read-Host "Press Enter to exit..."
        exit 1
    }
}

# Initialize log file if it doesn't exist
if (!(Test-Path $LOG_PATH)) {
    New-Item -Path $LOG_PATH -ItemType File -Force | Out-Null
}
Add-Content -Path $LOG_PATH -Value "`n--- SESSION START: $(Get-Date) ---`n"

$AppProcess = Start-Process -FilePath $EXE_PATH -PassThru
Write-Host ">>> Tailing logs from: $LOG_PATH" -ForegroundColor Gray
Write-Host ">>> (Press Ctrl+C to stop script, or close app to exit)`n" -ForegroundColor DarkGray

$lastPos = (Get-Item $LOG_PATH).Length

while (!$AppProcess.HasExited) {
    if (Test-Path $LOG_PATH) {
        $fileSize = (Get-Item $LOG_PATH).Length
        if ($fileSize -gt $lastPos) {
            $stream = [System.IO.File]::Open($LOG_PATH, 'Open', 'Read', 'ReadWrite')
            $stream.Seek($lastPos, 'Begin') | Out-Null
            $reader = New-Object System.IO.StreamReader($stream)
            while (!$reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ($line -like "*ERROR*" -or $line -like "*FAIL*") {
                    Write-Host $line -ForegroundColor Red
                }
                elseif ($line -like "*SUCCESS*" -or $line -like "*CONNECTED*") {
                    Write-Host $line -ForegroundColor Green
                }
                elseif ($line -like "*Sing-box*" -or $line -like "*START*") {
                    Write-Host $line -ForegroundColor Cyan
                }
                else {
                    Write-Host $line
                }
            }
            $lastPos = $stream.Position
            $reader.Close()
            $stream.Close()
        }
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "`n>>> App process terminated. Exiting build script." -ForegroundColor Yellow