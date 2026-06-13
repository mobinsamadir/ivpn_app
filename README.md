# پروژه iVPN

یک کلاینت VPN با عملکرد بالا و نوشته شده با فریم‌ورک فلاتر (Flutter).

## شروع به کار

این پروژه نقطه شروعی برای یک اپلیکیشن فلاتر است.
اگر این اولین پروژه فلاتر شماست، منابع زیر می‌توانند به شما کمک کنند:

- [آموزش: نوشتن اولین اپلیکیشن فلاتر](https://docs.flutter.dev/get-started/codelab)
- [کتاب آشپزی: نمونه کدهای کاربردی فلاتر](https://docs.flutter.dev/cookbook)

برای راهنمایی بیشتر در زمینه توسعه با فلاتر، به [مستندات آنلاین](https://docs.flutter.dev/) مراجعه کنید که شامل آموزش‌ها، نمونه کدها، راهنمای توسعه موبایل و مرجع کامل API است.

---

## منابع خارجی و سرویس‌های مورد استفاده در برنامه

این برنامه برای کنترل نسخه‌ها، دریافت کانفیگ‌ها، نمایش تبلیغات و نیازمندی‌های بیلد از منابع خارجی مختلفی استفاده می‌کند که در ادامه به طور کامل لیست شده‌اند:

### ۱. سیستم کنترل نسخه و آپدیت برنامه
- **فایل تنظیمات آپدیت:** برنامه برای بررسی نسخه‌های جدید، تغییرات نسخه (Release Notes) و لینک دانلود مستقیم از یک فایل JSON در Gist گیت‌هاب استفاده می‌کند.
  - **آدرس:** `https://gist.githubusercontent.com/mobinsamadir/1f91132e6d919d2dec5085a90c47ed4a/raw/7a8a456296fdf33ad4dd4d7a447dbfce0e966adb/version.json`

### ۲. بارگذاری کانفیگ‌های VPN (Subscriptions)
کانفیگ‌های سرور به صورت خودکار از مخازن (Mirrors) زیر دریافت می‌شوند:
- **میرور اول (اصلی):** `https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/refs/heads/main/servers.txt`
- **میرور دوم (پشتیبان):** `https://gist.githubusercontent.com/mobinsamadir/687a7ef199d6eaf6d1912e36151a9327/raw/servers.txt`
- **سورس مرجع خارجی (منابع اضافی):** `https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt`

### ۳. بارگذاری تبلیغات
برای مدیریت و لود تبلیغات درون برنامه‌ای از تنظیمات داینامیک استفاده می‌شود:
- **فایل تنظیمات تبلیغات (JSON Base64 Encoded):** تنظیمات تبلیغات، زمان‌بندی و فعال/غیرفعال بودن بخش‌های مختلف از Gist دریافت می‌شود.
  - **آدرس (دیکد شده):** `https://gist.githubusercontent.com/mobinsamadir/037cdab8b8713e1c5a52d815539f5638/raw/086833a97d236d9cf57d427c46c2268904244a7e/ad_config.json`
- **سرویس تبلیغاتی جایگزین (Fallback):** در صورتی که فایل تنظیمات در دسترس نباشد، برنامه از یک iframe تبلیغاتی به عنوان جایگزین امن (Fallback) استفاده می‌کند.
  - **آدرس سرویس:** `https://acceptable.a-ads.com/2426527/?size=Adaptive`

### ۴. نیازمندی‌های کامپایل و هسته (Build Dependencies)
در زمان کامپایل و ساخت فایل نصبی (APK/Windows)، برنامه فایل‌های باینری و کتابخانه‌های هسته را از منابع زیر دانلود می‌کند:
- **هسته Sing-box برای اندروید (Libbox):** `https://raw.githubusercontent.com/singbox-android/libbox/refs/heads/main/libbox.aar`
- **رابط کاربری ترمینال (Terminal View):** `https://jitpack.io/com/github/termux/termux-app/terminal-view/v0.118.3/terminal-view-v0.118.3.aar`
- **امولاتور ترمینال (Terminal Emulator):** `https://jitpack.io/com/github/termux/termux-app/terminal-emulator/v0.118.3/terminal-emulator-v0.118.3.aar`
- **هسته Sing-box برای ویندوز:** `https://github.com/SagerNet/sing-box/releases/download/v1.10.1/sing-box-1.10.1-windows-amd64.zip`
- **دیتابیس GeoIP (مسیریابی آی‌پی‌ها):** `https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db`
- **دیتابیس Geosite (مسیریابی دامنه‌ها):** `https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db`

---

## راهنمای فایل‌های مهم پروژه

| فایل | هدف | لینک گیت‌هاب |
|---|---|---|
| `android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt` | سرویس محلی (Native) در اندروید برای مدیریت روتینگ و تونلینگ VPN | [SingboxVpnService.kt](https://github.com/mobinsamadir/ivpn_app/blob/main/android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt) |
| `android/app/src/main/kotlin/com/example/ivpn_new/MainActivity.kt` | نقطه ورود اصلی اپلیکیشن اندروید و مدیریت Event Channelها | [MainActivity.kt](https://github.com/mobinsamadir/ivpn_app/blob/main/android/app/src/main/kotlin/com/example/ivpn_new/MainActivity.kt) |
| `lib/screens/connection_home_screen.dart` | رابط کاربری اصلی برای اتصال به VPN و نمایش آمار | [connection_home_screen.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/screens/connection_home_screen.dart) |
| `lib/services/config_manager.dart` | مدیریت کانفیگ‌ها، لیست‌های سیاه (Blacklists) و دیتای سرورها | [config_manager.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/config_manager.dart) |
| `lib/services/funnel_service.dart` | سرویس مربوط به تست مرحله‌ای سرورها (تست TCP، HTTP و سرعت) | [funnel_service.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/funnel_service.dart) |
| `lib/services/native_vpn_service.dart` | پل ارتباطی (Bridge) دارت برای تعامل با سرویس Native VPN | [native_vpn_service.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/native_vpn_service.dart) |
| `.github/workflows/main_pipeline.yml` | تنظیمات خط لوله (CI/CD Pipeline) برای بیلد خودکار | [main_pipeline.yml](https://github.com/mobinsamadir/ivpn_app/blob/main/.github/workflows/main_pipeline.yml) |
| `lib/services/config_gist_service.dart` | مدیریت لینک‌های سابسکریپشن و آپدیت کانفیگ‌ها | [config_gist_service.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/config_gist_service.dart) |
| `lib/services/ad_manager_service.dart` | کنترل فایل تنظیمات تبلیغات و ذخیره‌سازی کش | [ad_manager_service.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/ad_manager_service.dart) |
