# Test sing-box HTTP proxy with curl
Write-Host "🔍 Testing sing-box HTTP Proxy" -ForegroundColor Cyan

# Port from test config
$httpPort = 20809

Write-Host "`n1️⃣ Testing with httpbin.org..." -ForegroundColor Yellow
try {
    $result1 = curl.exe -x "http://127.0.0.1:$httpPort" "http://httpbin.org/get" --connect-timeout 10
    Write-Host "✅ httpbin.org: SUCCESS" -ForegroundColor Green
    Write-Host $result1
}
catch {
    Write-Host "❌ httpbin.org: FAILED - $_" -ForegroundColor Red
}

Write-Host "`n2️⃣ Testing with gstatic.com..." -ForegroundColor Yellow
try {
    $result2 = curl.exe -x "http://127.0.0.1:$httpPort" "http://www.gstatic.com/generate_204" --connect-timeout 10 -v
    Write-Host "✅ gstatic.com: SUCCESS" -ForegroundColor Green
}
catch {
    Write-Host "❌ gstatic.com: FAILED - $_" -ForegroundColor Red
}

Write-Host "`n3️⃣ Testing with google.com..." -ForegroundColor Yellow
try {
    $result3 = curl.exe --proxy "http://127.0.0.1:$httpPort" "http://www.google.com" --connect-timeout 10
    Write-Host "✅ google.com: SUCCESS" -ForegroundColor Green
}
catch {
    Write-Host "❌ google.com: FAILED - $_" -ForegroundColor Red
}

Write-Host "`n✅ Proxy test complete" -ForegroundColor Cyan
