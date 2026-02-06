# Manual test script for adaptive speed test
Write-Host "=== Adaptive Speed Test Diagnostic ==="
Write-Host "1. Building project..."
.\manual_build.ps1 -Clean:$false

Write-Host "`n2. Running diagnostic tests..."
flutter test test/diagnostic/adaptive_diagnostic.dart --verbose

Write-Host "`n3. Checking logs..."
if (Test-Path ".\logs") {
    Get-ChildItem ".\logs" -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content -Tail 20
}

Write-Host "`n=== Diagnostic Complete ==="
