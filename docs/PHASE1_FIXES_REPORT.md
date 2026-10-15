# گزارش جامع تغییرات و بهینه‌سازی‌های فاز ۱ (Phase 1 Fixes Report)

این مستند جهت بازبینی (Code Review) دقیق شما و Agent همراهتان تهیه شده است و تمام تغییرات اعمال شده، علت وقوع مشکلات (Root Causes)، معماری جدید و نحوه تست و تأیید آن‌ها را توضیح می‌دهد.

---

## 📌 خلاصه دستاوردها (Executive Summary)

در این فاز، ۵ مشکل حیاتی که منجر به قطعی ترافیک، مسدود شدن دکمه اتصال، ماندن آیکون کلید VPN در استاتوس‌بار اندروید، خطای مجوز دسترسی و ناهماهنگی نسخه‌گذاری خودکار در گیت‌هاب می‌شدند، به طور ریشه‌ای برطرف گردیدند:

1. **مدیریت تمیز و استاندارد مجوز VPN اندروید (`requestVpnPermission`)**:
   - حذف روش غیراستاندارد اجرای کانفیگ صوری `'{}'` و جایگزینی با متد مستقیم کانال نیتیو با بازگشت بولی (`Future<bool>`).
2. **رفع عدم عبور ترافیک و خطای DNS در حالت متصل**:
   - اصلاح قانون DNS در هسته Sing-box که قبلاً به اشتباه `outbound: ["any"]` را به DNS لوکال هدایت می‌کرد و باعث فیلتر/پویزن شدن درخواست‌های دامنه می‌شد.
   - حذف تزریق اجباری پروتکل مالتی‌پلکس (`h2mux`) و `tcp_fast_open` در زمان اتصال، که باعث قطع شدن فوری سرورهایی که از مالتی‌پلکس پشتیبانی نمی‌کردند می‌شد.
3. **رفع قفل شدن دکمه اتصال و امکان لغو فوری (Cancel)**:
   - امکان قطع یا لغو اتصال در هر لحظه (حتی زمان `connecting` یا `requesting_permission`) بدون گیر کردن دکمه در حالت خاکستری یا وضعیت معلق.
4. **پاکسازی کامل سرویس اندروید و رفع گیر کردن کلید VPN در استاتوس‌بار**:
   - بستن امن اینترفیس TUN و سرور در بلاک‌های `try-finally`، فراخوانی `stopForeground(STOP_FOREGROUND_REMOVE)` و هندل کردن رویداد `onTaskRemoved` (بسته شدن اپ از لیست برنامه‌های اخیر).
5. **سیستم انتشار و نسخه‌گذاری خودکار گیت‌هاب بدون دستکاری `assets/version.json`**:
   - محاسبه داینامیک برچسب بعدی گیت بر اساس تگ‌های ریموت گیت‌هاب (`v2.0.1`, `v2.0.2`, ...) و به‌روزرسانی کد و نسخه در زمان بیلد توسط ابزار CLI.

---

## 🛠 جزئیات فنی تغییرات فایل‌ها

### ۱. اصلاح مجوز نیتیو در اندروید
**فایل‌های تغییر یافته:**
- [`android/app/src/main/kotlin/com/ivpn_new/MainActivity.kt`](file:///android/app/src/main/kotlin/com/ivpn_new/MainActivity.kt)
- [`lib/services/native_vpn_service.dart`](file:///lib/services/native_vpn_service.dart)

#### مشکل قبلی:
- تابع `requestVpnPermission()` در دارت متد `testConfig` را با کانفیگ خالی `'{}'` صدا می‌زد. اگر کاربر قبلاً دسترسی داده بود، هسته با خطای `CONFIG_ERROR` مواجه می‌شد؛ و اگر کاربر رد می‌کرد، کد خطای نیتیو `VPN_PERMISSION_DENIED` بود در حالی که دارت دنبال `PERMISSION_DENIED` می‌گشت و باعث سردرگمی لوپ مجوز می‌شد.

#### تغییر اعمال شده:
- افزودن هندلر متد `"requestVpnPermission"` در `MainActivity.kt`:
  - صدا زدن `VpnService.prepare(this)`
  - در صورت نیاز به دیالوگ سیستم‌عامل، نگه‌داری متغیر `pendingPermissionResult` و صدا زدن `startActivityForResult`
  - در متد `onActivityResult`، به محض دریافت پاسخ کاربر، نتیجه `true`/`false` بلافاصله به دارت تحویل داده می‌شود.
- در `native_vpn_service.dart`، تابع `requestVpnPermission()` مستقیماً متد `requestVpnPermission` را فراخوانی کرده و مقدار بولی تمیز دریافت می‌کند.

---

### ۲. رفع مشکل قطعی اینترنت و نشت/فیلتر DNS
**فایل تغییر یافته:**
- [`lib/services/singbox_config_generator.dart`](file:///lib/services/singbox_config_generator.dart)

#### مشکل قبلی:
1. در تابع `_buildDns`، قانون DNS بدین صورت نوشته شده بود:
   ```json
   { "outbound": ["any"], "server": "local" }
   ```
   این قانون باعث می‌شد **تمام** درخواست‌های DNS کلاینت (حتی ترافیک پروکسی) به DNS لوکال و دایرکت هدایت شوند! در شبکه‌های تحت فیلترینگ، این درخواست‌ها پویزن شده یا تایم‌اوت می‌شدند و در نتیجه با وجود برقراری تانل، هیچ سایتی باز نمی‌شد.
2. در انتهای تولید کانفیگ (`_assembleFinalConfig`)، برای حالت لایو قطعه زیر به اجبار به کانفیگ خروجی چسبانده می‌شد:
   ```dart
   proxyOutbound["multiplex"] = {
     "enabled": true,
     "protocol": "h2mux",
     ...
   };
   proxyOutbound["tcp_fast_open"] = true;
   ```
   چون سرور در مرحله تست بدون مالتی‌پلکس تست شده بود و پاس می‌شد، اما موقع اتصال واقعی به اجبار `h2mux` و TFO دریافت می‌کرد، ارتباط TCP ریست می‌شد (`Connection reset by peer`)!

#### تغییر اعمال شده:
1. در `_buildDns`، قانون DNS به `outbound: ["direct"]` تغییر یافت:
   ```dart
   {
     "outbound": ["direct"],
     "server": "local",
   }
   ```
   اکنون فقط ترافیک دایرکت از DNS لوکال استفاده می‌کند و کلیه درخواست‌های عبوری از پروکسی مستقیماً از طریق `remote-doh` (Google DoH / Cloudflare DoH) روی بستر امن پروکسی حل می‌شوند.
2. کد تزریق اجباری مالتی‌پلکس حذف شد تا دقیقاً همان رفتاری که در تست موقت پاسخ داده است، در اتصال لایو نیز اعمال گردد.

---

### ۳. رفع قفل شدن دکمه و امکان لغو اتصال (Cancel / Disconnect)
**فایل تغییر یافته:**
- [`lib/screens/connection_home_screen.dart`](file:///lib/screens/connection_home_screen.dart)

#### مشکل قبلی:
- در متد `_handleConnection()`، ابتدای تابع یک گارد سخت‌گیرانه قرار داشت:
  ```dart
  if (_connectionFlowState != 'idle') return;
  ```
  هنگامی که کاربر روی اتصال می‌زد، `_connectionFlowState` روی `'connecting'` تنظیم می‌شد. اگر کاربر در میانه اتصال مجدداً روی دکمه کلیک می‌کرد تا لغو کند، به دلیل برقرار بودن شرط بالا، تابع بلافاصله خارج می‌شد و امکان Cancel وجود نداشت. دکمه همچنین اگر خطایی رخ می‌داد در برخی سناریوها از حالت معلق خارج نمی‌شد.

#### تغییر اعمال شده:
- جابجایی شرط لغو/قطع ارتباط به ابتدای تابع:
  ```dart
  final status = _configManager.connectionStatus.toLowerCase();
  final bool isConnectingOrConnected = _configManager.isConnected ||
      status.contains('connecting') ||
      _connectionFlowState == 'connecting' ||
      _connectionFlowState == 'requesting_permission';

  if (isConnectingOrConnected) {
    _connectionFlowState = 'disconnecting';
    _wasVpnConnected = false;
    try {
      await _configManager.stopAllOperations();
    } finally {
      _connectionFlowState = 'idle';
    }
    return;
  }
  ```
- دکمه اتصال اکنون در هر فازی فوراً پاسخگو بوده و در صورت لمس مجدد، عملیات را به سرعت لغو کرده و به وضعیت `'idle'` بازمی‌گردد.

---

### ۴. چرخه حیات تمیز سرویس VPN و رفع ماندن آیکون کلید در اندروید
**فایل تغییر یافته:**
- [`android/app/src/main/kotlin/com/ivpn_new/SingboxVpnService.kt`](file:///android/app/src/main/kotlin/com/ivpn_new/SingboxVpnService.kt)

#### مشکل قبلی:
- هنگام قطع اتصال یا بستن ناگهانی برنامه، اینترفیس TUN (`vpnInterface`) یا سرور `mainServer` ممکن بود باز بمانند.
- `onDestroy` با متد `runBlocking` روی میوتکس قفل می‌کرد که باعث ANR یا کرش می‌شد.
- اگر کاربر برنامه را با سنسور یا سوایپ از منوی برنامه‌های اخیر (Recent Apps) می‌بست، تسک بسته نمی‌شد و کلید VPN تا ریستارت گوشی در نوار اعلان گیر می‌کرد.

#### تغییر اعمال شده:
- پاکسازی منابع در `stopVpnInternal` در بلوک‌های مستقل `try-finally`:
  ```kotlin
  try { mainServer?.close() } finally { mainServer = null }
  try { vpnInterface?.close() } finally { vpnInterface = null }
  ```
- استفاده از فلگ مدرن `stopForeground(STOP_FOREGROUND_REMOVE)` متناسب با نسخه اندروید برای حذف قطعی نوتیفیکیشن.
- اضافه شدن اورراید متد `onTaskRemoved`:
  ```kotlin
  override fun onTaskRemoved(rootIntent: Intent?) {
      super.onTaskRemoved(rootIntent)
      stopVpnInternal()
  }
  ```
- رفع Deadlock در `onDestroy` و اطمینان از خروج ایمن سرویس.

---

### ۵. اتوماسیون انتشار و نگارش خودکار بدون دستکاری `version.json`
**فایل‌های تغییر یافته:**
- [`.github/workflows/auto_build_release.yml`](file:///.github/workflows/auto_build_release.yml)
- [`tool/update_version.dart`](file:///tool/update_version.dart)

#### ساختار پیاده‌سازی شده:
- فایل `assets/version.json` کاملاً Read-Only باقی ماند و تنها برای آپدیت درون‌برنامه‌ای دستی توسط شما کنترل می‌شود.
- اسکریپت `tool/update_version.dart` پارامترهای اختیاری `--version <x.y.z>` و `--code <number>` را برای بیلد‌های CI دریافت می‌کند.
- جاب `filter` در ورک‌فلو گیت‌هاب تمام تگ‌های موجود ریپازیتوری را فچ کرده، بالاترین تگ ریلیز شده (مثلاً `v2.0.0`) را پیدا می‌کند و به صورت خودکار نسخه بعدی (`v2.0.1`, `v2.0.2`, ...) را خروجی می‌دهد و به جاب‌های بیلد و انتشار پاس می‌دهد.
- آرتیفکت‌های APK و ZIP به صورت فلت در یک دایرکتوری تجمیع شده و فایل الزامی `iVPN-release.apk` تأیید و ضمیمه ریلیز گیت‌هاب می‌شود.

---

## 🔍 وضعیت کامیت‌های محلی (Local Commits)

هیچ کدی به صورت خودکار push نشده است. تغییرات فوق در دو کامیت تمیز و ساختاریافته به صورت محلی ثبت شده‌اند:

1. `0fb8469`: `ci(release): auto-increment release tag and build version without modifying version.json`
2. `c90c4ce`: `fix(vpn): resolve permissions, DNS leak, stuck button, and teardown lifecycle`

شما می‌توانید با اجرای دستور زیر در زمان دلخواه، این تغییرات را به ریپازیتوری ارسال فرمایید:
```bash
git push origin main
```
