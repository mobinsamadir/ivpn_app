$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Sing-box Debugger..." -ForegroundColor Green

# 1. Define Paths
$binPath = ".\assets\executables\windows\sing-box.exe"
$configPath = "debug_config.json"

if (-not (Test-Path $binPath)) {
  Write-Error "❌ Binary not found at $binPath"
}

# 2. Generate Minimal Debug Config
$configJson = @'
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
    },
    {
        "type": "socks",
        "tag": "socks-in",
        "listen": "127.0.0.1",
        "listen_port": 53181,
        "sniff": false
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
     "auto_detect_interface": true
  }
}
'@

# 🚨 CRITICAL FIX: Write UTF-8 NO BOM
[System.IO.File]::WriteAllText($configPath, $configJson, [System.Text.UTF8Encoding]::new($false))
Write-Host "✅ Config generated (UTF8 No-BOM) at $configPath" -ForegroundColor Green

# 3. Kill existing zombies
Write-Host "🧹 Killing old processes..." -ForegroundColor Yellow
try {
  Stop-Process -Name "sing-box" -Force -ErrorAction SilentlyContinue
}
catch {}

# 4. Run Sing-box
Write-Host "▶️ Running Sing-box (Press Ctrl+C to stop)..." -ForegroundColor Cyan
Write-Host "   Target: 127.0.0.1:53180 (HTTP)"
Write-Host "----------------------------------------"

& $binPath run -c $configPath
