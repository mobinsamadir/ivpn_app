# run_with_logs.ps1
param(
    [switch]$Admin = $true
)

$logDir = "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$transcriptLog = "$logDir\transcript_$timestamp.log"
$consoleLog = "$logDir\console_$timestamp.log"

Write-Host "=== Starting IVPN with full logging ===" -ForegroundColor Cyan
Write-Host "Transcript log: $transcriptLog" -ForegroundColor Yellow
Write-Host "Console log: $consoleLog" -ForegroundColor Yellow

# شروع ضبط همه چیز
Start-Transcript -Path $transcriptLog -Append

# اگر نیاز به ادمین باشه
if ($Admin) {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-NOT $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Restarting with Administrator privileges..." -ForegroundColor Yellow
        Stop-Transcript
        $scriptPath = $MyInvocation.MyCommand.Path
        Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command `"cd '$PSScriptRoot'; & '$scriptPath' -Admin:`$true`""
        exit
    }
}

# اجرای manual_build و redirect خروجی به فایل
Write-Host "`n=== Running build script ===" -ForegroundColor Green

try {
    # اجرا و گرفتن خروجی
    & .\manual_build.ps1 2>&1 | Tee-Object -FilePath $consoleLog
    
    Write-Host "`n=== Build completed ===" -ForegroundColor Green
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
} finally {
    Stop-Transcript
    
    Write-Host "`n=== Log files created: ===" -ForegroundColor Cyan
    Get-ChildItem $logDir | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | Format-Table Name, LastWriteTime, Length
    
    # نمایش آخرین خطوط لاگ
    Write-Host "`n=== Last 20 lines of console log ===" -ForegroundColor Yellow
    if (Test-Path $consoleLog) {
        Get-Content $consoleLog -Tail 20
    }
    
    # باز کردن پوشه لاگ‌ها
    Invoke-Item $logDir
}