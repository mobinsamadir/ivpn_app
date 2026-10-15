# گزارش جامع بهینه‌سازی‌ها و معماری نهایی (Full Optimization & Architecture Report)

این گزارش مرجع کامل تمام بهینه‌سازی‌ها، بازطراحی‌های معماری، رفع باگ‌ها و ارتقاء عملکرد برنامه در کلیه فازها (فاز ۱ تا ۴) است که برای بررسی و بازبینی (Audit & Review) شما و ایجنت همراهتان نگارش شده است.

---

## 📑 فهرست مطالب
1. [خلاصه اجرایی تمام فازها](#خلاصه-اجرایی-تمام-فازها)
2. [فاز ۱: چرخه حیات VPN، مجوزها و رفع نشت DNS](#فاز-۱-چرخه-حیات-vpn-مجوزها-و-رفع-نشت-dns)
3. [فاز ۲: شتاب‌دهی خط لوله تست (Funnel Acceleration & Latency Optimization)](#فاز-۲-شتاب‌دهی-خط-لوله-تست)
4. [فاز ۳: بهینه‌سازی هوشمند حافظه و دیسک (Debounced Disk I/O & Memory Preservation)](#فاز-۳-بهینه‌سازی-هوشمند-حافظه-و-دیسک)
5. [فاز ۴: برندینگ، صفحه اسپلش و بهبود تجربه کاربری (UI/UX & Visual Polish)](#فاز-۴-برندینگ-صفحه-اسپلش-و-بهبود-تجربه-کاربری)
6. [فاز ۵: اتوماسیون انتشار CI/CD بدون تغییر نسخه دستی](#فاز-۵-اتوماسیون-انتشار-cicd-بدون-تغییر-نسخه-دستی)
7. [لیست فایل‌های تغییر یافته و خلاصه تغییرات](#لیست-فایل‌های-تغییر-یافته-و-خلاصه-تغییرات)
8. [تاریخچه کامیت‌های محلی](#تاریخچه-کامیت‌های-محلی)

---

## ۱. خلاصه اجرایی تمام فازها

| فاز | موضوع | دستاورد کلیدی |
|---|---|---|
| **فاز ۱** | مجوزها و پایداری اتصال | حذف روش صوری تست کانفیگ، افزودن کانال مستقیم `requestVpnPermission`، رفع نشت DNS، حذف تزریق اجباری multiplex/TFO، رفع قفل شدن دکمه Connect و پاکسازی کامل سرویس در `onDestroy` و `onTaskRemoved`. |
| **فاز ۲** | سرعت تست (Funnel) | کاهش تأخیرهای مصنوعی راه‌اندازی و بازیافت پروکسی از ۱۳۰۰ میلی‌ثانیه به ۳۰۰ میلی‌ثانیه، افزایش وورکرهای مرحله TCP Ping به ۱۶ و کاهش تایم‌اوت به ۱۵۰۰ میلی‌ثانیه برای حذف آنی سرورهای مرده. |
| **فاز ۳** | منابع، رم و دیسک | پیاده‌سازی Debounce هوشمند در `_saveAllConfigs()` (۱.۵ ثانیه) برای جلوگیری از اسپم شدن ایزولیت‌های پردازش JSON و افت بار دیسک هنگام تست متوالی صدها سرور. |
| **فاز ۴** | برندینگ و UI | صفحه لودینگ برند شده با لوگوی اصلی `assets/icon.png`، انیمیشن نئونی پالس، نمایش نسخه برنامه (`v2.0.0`)، و ارتقای دکمه اتصال با قابلیت لغو/قطع آنی. |
| **فاز ۵** | انتشار خودکار گیت‌هاب | محاسبه خودکار تگ بعدی (`v2.0.1`, `v2.0.2`, ...) بر اساس آخرین ریلیز در ریپازیتوری بدون هیچ دستکاری در `assets/version.json`. |

---

## ۲. فاز ۱: چرخه حیات VPN، مجوزها و رفع نشت DNS

### ۲.۱. جریان مجوز دسترسی VPN (VPN Permission Flow)
- **علت مشکل**: قبلاً دارت برای گرفتن دسترسی متد `testConfig` را با کانفیگ تهی `{}` صدا می‌زد. اگر دسترسی از قبل داده شده بود، این کار باعث خطای `CONFIG_ERROR` یا پینگ -۱ می‌شد، و در صورت رد دسترسی توسط کاربر، کد خطای `VPN_PERMISSION_DENIED` فرستاده می‌شد که با چک دارت (`PERMISSION_DENIED`) همخوانی نداشت.
- **راهکار پیاده‌سازی شده**:
  - اضافه شدن متد `"requestVpnPermission"` به کانال متد در `MainActivity.kt`.
  - اجرای مستقیم `VpnService.prepare(this)` و ذخیره `pendingPermissionResult`.
  - مدیریت رویداد در `onActivityResult` و بازگرداندن پاسخ بولی (`true`/`false`) به دارت بدون نیاز به هیچ کانفیگ جعلی.
  - اصلاح `NativeVpnService.requestVpnPermission()` در دارت برای دریافت این پاسخ به صورت تمیز.

### ۲.۲. رفع قطعی اینترنت پس از اتصال و فیلترینگ DNS
- **علت مشکل**:
  1. در `singbox_config_generator.dart`، قانون DNS بدین صورت نوشته شده بود:
     ```json
     { "outbound": ["any"], "server": "local" }
     ```
     این امر تمام درخواست‌های DNS را به DNS داخلی و محلی (Direct) ارجاع می‌داد که در شبکه‌های دارای سانسور یا مسدودیت، پاسخ‌های DNS پویزن یا تایم‌اوت می‌شدند و مرورگر/برنامه‌ها لود نمی‌شدند.
  2. در زمان اتصال واقعی، هسته به اجبار `multiplex: { protocol: "h2mux" }` و `tcp_fast_open: true` را به کانفیگ می‌چسباند؛ در حالی که در تست‌های موقت، بدون این گزینه‌ها تست می‌شد. سرورهایی که مالتی‌پلکس را پشتیبانی نمی‌کردند، بلافاصله اتصال را ریست می‌کردند (`Connection reset by peer`).
- **راهکار پیاده‌سازی شده**:
  - اصلاح قانون DNS به `{"outbound": ["direct"], "server": "local"}`؛ ترافیک عبوری از پروکسی اکنون به شکل امن از `remote-doh` (Google / Cloudflare DoH) روی بستر پروکسی استفاده می‌کند.
  - حذف کد تزریق اجباری مالتی‌پلکس در `_assembleFinalConfig`.

### ۲.۳. رفع گیر کردن کلید VPN در استاتوس‌بار اندروید
- **علت مشکل**: در زمان خروج یا بسته شدن غیرمنتظره، `vpnInterface?.close()` در بلاک امن فراخوانی نمی‌شد و `stopForeground` با پارامترهای ناقص فراخوانی می‌گردید. اگر کاربر اپلیکیشن را از منوی Recent Apps سوایپ می‌کرد، سرویس مطلع نمی‌شد.
- **راهکار پیاده‌سازی شده**:
  - استفاده از `try-finally` مستقل برای `mainServer?.close()` و `vpnInterface?.close()` در `SingboxVpnService.kt`.
  - استفاده از فلگ استاندارد اندروید ۷+ (`stopForeground(STOP_FOREGROUND_REMOVE)`).
  - پیاده‌سازی متد `onTaskRemoved` در سرویس جهت بستن آنی و آزاد کردن اینترفیس TUN به محض بسته شدن برنامه از برنامه‌های اخیر.

### ۲.۴. رفع قفل شدن دکمه Connect و امکان لغو فوری
- **علت مشکل**: وجود شرط `if (_connectionFlowState != 'idle') return;` در ابتدای `_handleConnection()` مانع از آن می‌شد که کاربر با کلیک روی دکمه در وضعیت `connecting` بتواند فرآیند اتصال را لغو یا متوقف کند.
- **راهکار پیاده‌سازی شده**:
  - بررسی قصد لغو یا قطع اتصال به عنوان اولین اولویت در ابتدای تابع `_handleConnection()`.
  - تضمین ریست شدن وضعیت به `'idle'` در بلاک `finally`.

---

## ۳. فاز ۲: شتاب‌دهی خط لوله تست (Funnel Acceleration)

- **کاهش Delayهای مصنوعی**:
  - در `SingboxVpnService.kt`: تاخیر پاکسازی و بستن سرور تست از `300ms` به `120ms` و تاخیر آمادگی سرور از `200ms` به `80ms` کاهش یافت.
  - در `ephemeral_tester.dart`: تاخیر قبل از راه‌اندازی پروکسی از `500ms` به `120ms` و تاخیر قبل از پروب HTTP از `300ms` به `100ms` کاهش یافت.
  - **نتیجه**: زمان تست هر سرور حدود ۸۰۰ میلی‌ثانیه کاهش یافت که در تست ۲۰ سرور، بیش از ۱۶ ثانیه صرفه‌جویی زمان ایجاد می‌کند.
- **افزایش وورکرهای مرحله ۱ (TCP Ping Concurrency)**:
  - تعداد وورکرهای همزمان سوکت خام دارت در اندروید به ۱۶ و در ویندوز به ۸ افزایش یافت.
  - تایم‌اوت تست سوکت TCP از ۲۰۰۰ میلی‌ثانیه به ۱۵۰۰ میلی‌ثانیه کاهش یافت تا سرورهای مرده بدون اتلاف وقت بلافاصله از صف خارج شوند.

---

## ۴. فاز ۳: بهینه‌سازی هوشمند حافظه و دیسک

- **پیاده‌سازی Debounced Disk I/O در `ConfigManager`**:
  - قبلاً به ازای ثبت شکست یا تغییر متریک هر سرور، تابع `_saveAllConfigs()` یک ایزولیت جدید برای انکود JSON کل سرورها اسپم می‌کرد.
  - متغیر `_saveDebounceTimer` با بازه ۱۵۰۰ میلی‌ثانیه اضافه شد. ذخیره‌سازی‌های متوالی در حین تست‌های سریع دسته‌ای، تجمیع شده و فقط یک‌بار بر روی حافظه پایدار دیسک نوشته می‌شوند.
  - در عملیات‌های بحرانی (مانند حذف یا افزودن دستی کانفیگ)، پارامتر `forceImmediate: true` به کار گرفته می‌شود تا داده بلافاصله ذخیره گردد.

---

## ۵. فاز ۴: برندینگ، صفحه اسپلش و بهبود تجربه کاربری

- **بهینه‌سازی صفحه لودینگ اولیه (`splash_screen.dart`)**:
  - جایگزینی آیکون قفل ساده با لوگوی باکیفیت و رسمی اپلیکیشن (`assets/icon.png`).
  - افکت نئونی، سایه ملایم هماهنگ با تم دارک و حاشیه متالیک مدرن.
  - پیام‌های متغیر چرخان (`Loading servers...`, `Readying connection...`) در طول مقداردهی اولیه.
  - اضافه شدن نمایش شماره نسخه اپلیکیشن (`v2.0.0`) در بخش پایینی به صورت مونو‌اسپیس با کنتراست ملایم.

---

## ۶. فاز ۵: اتوماسیون انتشار CI/CD بدون تغییر نسخه دستی

- **مکانیزم محاسبه تگ در GitHub Actions (`.github/workflows/auto_build_release.yml`)**:
  - استخراج آخرین تگ‌های موجود در ریموت با `git tag -l "v*.*.*"`
  - استخراج نسخه پایه از `assets/version.json` و محاسبه شماره بعدی (Patch Increment).
  - خروجی متغیرهای `version` و `version_code` به جاب‌های ساخت اندروید، ویندوز و انتشار.
- **به‌روزرسانی اسکریپت `tool/update_version.dart`**:
  - پشتیبانی از آرگومان‌های خط فرمان `--version` و `--code` بدون نیاز به تغییر یا کامیت فایل `assets/version.json`.
- **یکپارچه‌سازی و اعتبارسنجی دارایی‌های انتشار (Release Assets)**:
  - تجمیع فلت تمام فایل‌های APK و ZIP و حصول اطمینان از وجود فایل الزامی `iVPN-release.apk` برای آپدیت خودکار درون‌برنامه‌ای.

---

## ۷. لیست فایل‌های تغییر یافته و خلاصه تغییرات

1. [`android/app/src/main/kotlin/com/ivpn_new/MainActivity.kt`](file:///android/app/src/main/kotlin/com/ivpn_new/MainActivity.kt):
   - افزودن هندلر `requestVpnPermission` و مدیریت تمیز `onActivityResult`.
2. [`android/app/src/main/kotlin/com/ivpn_new/SingboxVpnService.kt`](file:///android/app/src/main/kotlin/com/ivpn_new/SingboxVpnService.kt):
   - بهبود `stopVpnInternal`، اضافه کردن `onTaskRemoved`، جلوگیری از Deadlock در `onDestroy`، و کاهش تأخیرهای راه‌اندازی/پاکسازی سرور تستی.
3. [`lib/screens/connection_home_screen.dart`](file:///lib/screens/connection_home_screen.dart):
   - رفع باگ عدم امکان لغو اتصال و ریست تضمینی وضعیت دکمه به `'idle'`.
4. [`lib/screens/splash_screen.dart`](file:///lib/screens/splash_screen.dart):
   - بازطراحی برندینگ با لوگوی رسمی، افکت نئون و نمایش نسخه.
5. [`lib/services/config_manager.dart`](file:///lib/services/config_manager.dart):
   - پیاده‌سازی Debounce برای ذخیره دیسک (`_saveDebounceTimer`).
6. [`lib/services/funnel_service.dart`](file:///lib/services/funnel_service.dart):
   - ارتقای تعداد وورکرهای TCP به ۱۶ و کاهش تایم‌اوت به ۱۵۰۰ms.
7. [`lib/services/native_vpn_service.dart`](file:///lib/services/native_vpn_service.dart):
   - فراخوانی مستقیم متد کانال `requestVpnPermission`.
8. [`lib/services/singbox_config_generator.dart`](file:///lib/services/singbox_config_generator.dart):
   - اصلاح قانون DNS از `any` به `direct` برای جلوگیری از نشت/فیلتر DNS، و حذف مالتی‌پلکس اجباری.
9. [`lib/services/testers/ephemeral_tester.dart`](file:///lib/services/testers/ephemeral_tester.dart):
   - کاهش تأخیرهای متوالی تست از ۵۰۰/۳۰۰ میلی‌ثانیه به ۱۲۰/۱۰۰ میلی‌ثانیه.
10. [`.github/workflows/auto_build_release.yml`](file:///.github/workflows/auto_build_release.yml):
    - محاسبه پویا و خودکار تگ نسخه برای هر ریلیز گیت‌هاب بدون دستکاری `assets/version.json`.
11. [`tool/update_version.dart`](file:///tool/update_version.dart):
    - افزودن سوییچ‌های خط فرمان `--version` و `--code`.

---

## ۸. تاریخچه کامیت‌های محلی (Local Commits)

تمامی تغییرات به صورت محلی و منظم کامیت شده و **هیچ دستوری برای پوش به سرور اجرا نشده است** (پوش توسط خود شما انجام خواهد شد):

```
890b265 perf(pipeline): accelerate funnel testing, debounce config persistence, and polish splash screen
68fd54d docs: add Phase 1 fixes and architecture review report
c90c4ce fix(vpn): resolve permissions, DNS leak, stuck button, and teardown lifecycle
0fb8469 ci(release): auto-increment release tag and build version without modifying version.json
```

هنگامی که مایل به انتشار و شروع بیلد خودکار توسط گیت‌هاب اکشنز بودید، کافی است دستور زیر را اجرا فرمایید:
```bash
git push origin main
```
