# Speed Test Debugging Guide

## ✅ Changes Applied

### 1. **Updated Test URLs (HTTP-Only)**

**Why**: HTTPS URLs fail through HTTP proxy (port 89)

**Old (Failed)**:

- https://cachefly.cachefly.net/...
- https://speed.hetzner.de/...

**New (Working)**:

- http://speedtest.tele2.net/10MB.zip
- http://ipv4.download.thinkbroadband.com/10MB.zip
- http://proof.ovh.net/files/10Mb.dat

### 2. **Increased Timeouts**

- **AdaptiveSpeedTester**: 5s → 30s connection timeout
- **SpeedTestService**: 30s → 60s send/receive timeout
- **Added**: Follow redirects (max 5)

### 3. **File Size Update**

- Changed from 5MB to 10MB for more accurate speed measurement
- Updated from 40 Mbit to 80 Mbit in calculations

## 🔍 Previous Error Analysis

From logs:

```
Connection to api.ipify.org:89 - CLOSED
Connection to speedtest.tole2.net:89 - read/write on closed pipe
Final speed: 0.00 Mbps
```

**Root Causes**:

1. Port 89 is the HTTP proxy port (correct)
2. HTTPS URLs can't work through HTTP proxy
3. Connection timeout too short (5s)
4. Some servers don't respond well to proxy

## ✅ How to Test

### 1. Run the App

```powershell
cd c:\Users\Mobin-pc\ivpn_new
.\manual_build.ps1
```

### 2. Watch Logs in Real-Time

```powershell
# In separate terminal
.\view_logs.ps1
# Choose option 3 (Live tail)
```

### 3. Run Speed Test

- Click the Speed Test button in UI
- Watch for these log messages:
  ```
  [INFO] ===== SPEED TEST STARTED =====
  [INFO] Network connectivity: OK
  [INFO] HTTP GET http://speedtest.tele2.net/10MB.zip
  [INFO] HTTP Response [200] ...
  [INFO] Speed calculated: XX.XX Mbps
  ```

## 🐛 If Still Failing

### Check These in Logs:

**1. Proxy Configuration**
Look for: `Configuring proxy for ... {'proxy': 'PROXY 127.0.0.1:89'}`

- If missing: Proxy not configured
- Fix: Call `configureProxy()` before test

**2. Network Connectivity**
Look for: `Network connectivity: OK` or `FAILED`

- If FAILED: No internet connection
- If OK but test fails: Proxy/VPN issue

**3. HTTP Response**
Look for: `HTTP Response [200]` or `[XXX]`

- 200: Success, check if bytes received
- 4XX/5XX: Server error, try fallback URL
- Connection timeout: Increase timeout further

**4. Bytes Received**
Look for: `bytesReceived: XXXX`

- If 0: Download failed completely
- If > 0 but speed = 0: Timing issue

## 📝 Quick Fixes

### Fix 1: Ensure Proxy is Configured

In `HomeProvider.handleSpeedTest()`:

```dart
// Get VPN's HTTP proxy port
final httpPort = await _windowsVpnService.getHttpPort();
// Configure before testing
_speedTestService.configureProxy('127.0.0.1', httpPort);
// Now run test
final speed = await _speedTestService.testDownloadSpeed();
```

### Fix 2: Test Without VPN First

Temporarily disable proxy to verify network works:

```dart
// In SpeedTestService, comment out proxy config
// _dio.httpClientAdapter = ... // COMMENTED
```

### Fix 3: Add More Fallback URLs

Edit `lib/services/speed_test_service.dart`:

```dart
static const List<String> _testUrls = [
  'http://speedtest.tele2.net/10MB.zip',
  'http://ipv4.download.thinkbroadband.com/10MB.zip',
  'http://proof.ovh.net/files/10Mb.dat',
  'http://ftp.acc.umu.se/mirror/wikimedia.org/other/static/images/project-logos/enwiki-2x.png', // Small test
];
```

## 📊 Expected Log Output

### Successful Test:

```
[INFO ] ===== SPEED TEST STARTED =====
[DEBUG] Verifying network connectivity...
[INFO ] Network connectivity: OK
[INFO ] Attempting speed test with: http://speedtest.tele2.net/10MB.zip
[INFO ] HTTP GET http://speedtest.tele2.net/10MB.zip
[INFO ] HTTP Response [200] http://speedtest.tele2.net/10MB.zip
  └─ {"type":"network_response","url":"...","statusCode":200,"body":{"bytesReceived":10485760},"durationMs":2341}
[INFO ] Speed calculated: 35.76 Mbps
  └─ {"durationSec":2.341,"fileSizeMbits":80.0,"bytesReceived":10485760}
[INFO ] ===== SPEED TEST COMPLETED: 35.76 Mbps =====
```

### Failed Test (with retry):

```
[ERROR] Speed test error for http://speedtest.tele2.net/10MB.zip
  └─ {"error":"Connection timeout","elapsedMs":30000}
[INFO ] Attempting speed test with: http://ipv4.download.thinkbroadband.com/10MB.zip
[INFO ] HTTP Response [200] ...
[INFO ] Speed calculated: 42.15 Mbps
```
