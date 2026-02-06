$ErrorActionPreference = "Stop"

Write-Host "🔧 Debugging VMess Config..." -ForegroundColor Yellow

# Kill any existing sing-box processes
Get-Process -Name "sing-box" -ErrorAction SilentlyContinue | Stop-Process -Force

# VMess config based on sing-box v1.12 schema
$config = @'
{
  "log": {
    "level": "debug",
    "output": "stderr",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "http",
      "tag": "http-in",
      "listen": "127.0.0.1",
      "listen_port": 53180,
      "sniff": false
    }
  ],
  "outbounds": [
    {
      "type": "vmess",
      "tag": "vmess-out",
      "server": "85.195.101.122",
      "server_port": 40878,
      "uuid": "f3d4167e-b15e-4e46-82e9-9286ef93fda7",
      "security": "auto",
      "alter_id": 0
    }
  ],
  "route": {
    "auto_detect_interface": true
  }
}
'@

# Write config without BOM
[System.IO.File]::WriteAllText("vmess_test.json", $config, [System.Text.UTF8Encoding]::new($false))

Write-Host "✅ VMess config generated" -ForegroundColor Green
Write-Host "📂 Config file: vmess_test.json" -ForegroundColor Cyan

# Run sing-box with timeout
Write-Host "`n▶️ Starting sing-box..." -ForegroundColor Cyan
$process = Start-Process -FilePath ".\assets\executables\windows\sing-box.exe" `
    -ArgumentList "run", "-c", "vmess_test.json" `
    -NoNewWindow `
    -RedirectStandardError "vmess_stderr.log" `
    -RedirectStandardOutput "vmess_stdout.log" `
    -PassThru

# Wait and then kill
Start-Sleep -Seconds 5
if (!$process.HasExited) {
    $process.Kill()
    Write-Host "⚠️ Process killed after 5 seconds" -ForegroundColor Yellow
}
else {
    Write-Host "🚨 Process exited early (code: $($process.ExitCode))" -ForegroundColor Red
}

# Display logs
Write-Host "`n=== STDERR ===" -ForegroundColor Red
if (Test-Path "vmess_stderr.log") {
    Get-Content "vmess_stderr.log"
}
else {
    Write-Host "(No stderr output)" -ForegroundColor Gray
}

Write-Host "`n=== STDOUT ===" -ForegroundColor Green
if (Test-Path "vmess_stdout.log") {
    Get-Content "vmess_stdout.log"
}
else {
    Write-Host "(No stdout output)" -ForegroundColor Gray
}

Write-Host "`n✅ Debug complete. Check logs above for errors." -ForegroundColor Cyan
