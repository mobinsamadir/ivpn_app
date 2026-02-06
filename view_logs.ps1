# view_logs.ps1
# Script to view speed test logs in real-time

Write-Host "=== IVPN Speed Test Log Viewer ===" -ForegroundColor Cyan

$docsPath = [Environment]::GetFolderPath('MyDocuments')
$logPattern = "vpn_log_*.jsonl"
$logFiles = Get-ChildItem -Path $docsPath -Filter $logPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

if ($logFiles.Count -eq 0) {
    Write-Host "No log files found in: $docsPath" -ForegroundColor Yellow
    Write-Host "Run the app first to generate logs." -ForegroundColor Yellow
    exit
}

$latestLog = $logFiles[0]
Write-Host "Latest log file: $($latestLog.Name)" -ForegroundColor Green
Write-Host "Location: $($latestLog.FullName)" -ForegroundColor Gray
Write-Host ""

# Display options
Write-Host "[1] View last 50 lines" -ForegroundColor White
Write-Host "[2] View speed test entries only" -ForegroundColor White
Write-Host "[3] Tail log (live updates)" -ForegroundColor White
Write-Host "[4] View all ERROR entries" -ForegroundColor White
$choice = Read-Host "Choose option (1-4)"

switch ($choice) {
    "1" {
        Write-Host "`n=== Last 50 Lines ===" -ForegroundColor Cyan
        Get-Content $latestLog.FullName -Tail 50 | ForEach-Object {
            $json = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json) {
                $color = switch ($json.level) {
                    "ERROR" { "Red" }
                    "WARN" { "Yellow" }
                    "INFO" { "Green" }
                    "DEBUG" { "Cyan" }
                    default { "White" }
                }
                Write-Host "[$($json.level)] $($json.message)" -ForegroundColor $color
            }
        }
    }
    "2" {
        Write-Host "`n=== Speed Test Entries ===" -ForegroundColor Cyan
        Get-Content $latestLog.FullName | ForEach-Object {
            $json = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json -and $json.message -match "speed|SPEED|Mbps|download") {
                Write-Host "[$($json.timestamp)] $($json.message)" -ForegroundColor Green
            }
        }
    }
    "3" {
        Write-Host "`n=== Tailing Log (Press Ctrl+C to stop) ===" -ForegroundColor Cyan
        Get-Content $latestLog.FullName -Wait -Tail 10 | ForEach-Object {
            $json = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json) {
                $color = switch ($json.level) {
                    "ERROR" { "Red" }
                    "WARN" { "Yellow" }
                    "INFO" { "Green" }
                    "DEBUG" { "Cyan" }
                    default { "White" }
                }
                Write-Host "[$($json.level)] $($json.message)" -ForegroundColor $color
            }
        }
    }
    "4" {
        Write-Host "`n=== ERROR Entries ===" -ForegroundColor Red
        Get-Content $latestLog.FullName | ForEach-Object {
            $json = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json -and $json.level -eq "ERROR") {
                Write-Host "[$($json.timestamp)] $($json.message)" -ForegroundColor Red
                if ($json.metadata) {
                    Write-Host "  Details: $($json.metadata | ConvertTo-Json -Compress)" -ForegroundColor Gray
                }
            }
        }
    }
    default {
        Write-Host "Invalid choice" -ForegroundColor Red
    }
}

Write-Host "`nLog file location: $($latestLog.FullName)" -ForegroundColor Gray
