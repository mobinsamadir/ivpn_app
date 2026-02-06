# ==========================================
#  IVPN Launcher Script for Visual Studio 18
# ==========================================

Write-Host ">>> 1. Configuring Environment for VS 2026 (v18)..." -ForegroundColor Cyan

# اجبار فلاتر به استفاده از جنریتور ۲۰۲۲
$env:CMAKE_GENERATOR = "Visual Studio 17 2022"

# استفاده از ابزار بیلد ۲۰۱۹ (که نصب کردیم) برای سازگاری
$env:CMAKE_GENERATOR_TOOLSET = "v142"

# آدرس‌دهی مستقیم به نسخه ۱۸ (که فلاتر پیدایش نمی‌کرد)
$env:CMAKE_GENERATOR_INSTANCE = "C:\Program Files\Microsoft Visual Studio\18\Community"

Write-Host ">>> 2. Environment Variables Set Successfully!" -ForegroundColor Green
Write-Host "    - Generator: $env:CMAKE_GENERATOR"
Write-Host "    - Toolset:   $env:CMAKE_GENERATOR_TOOLSET"
Write-Host "    - Instance:  $env:CMAKE_GENERATOR_INSTANCE"

Write-Host "`n>>> 3. Launching Flutter..." -ForegroundColor Yellow
# اجرای دستور اصلی فلاتر
flutter run -d windows -v

# نگه‌داشتن پنجره در صورت بروز خطا
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ Error occurred. Press Enter to exit." -ForegroundColor Red
    Read-Host
}