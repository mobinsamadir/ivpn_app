# گزارش جامع بررسی معماری، الگوریتم‌ها و تجربه کاربری (Comprehensive Audit Report)

این گزارش شامل کالبدشکافی عمیق معماری فعلی پروژه، الگوریتم‌های شبکه‌سازی، مدیریت حافظه، و برنامه‌ریزی هدفمند برای بهبود پایداری و رابط کاربری است.

## ۱. مستندسازی دقیق نحوه کارکرد فعلی برنامه و الگوریتم‌ها (How the App Currently Works)

### الگوریتم کشف و تست کانفیگ‌ها (Discovery & Testing Algorithm)
- **شروع تست:** پس از باز شدن برنامه، متد `initAppSequence` (در `connection_home_screen.dart`) اجرا می‌شود و لیست کانفیگ‌ها از طریق `configGistService` دریافت و به `ConfigManager` داده می‌شود. سپس `testAllServers()` فراخوانی می‌شود که در نهایت `EphemeralTester.testConfigs()` را اجرا می‌کند.
- **تخصیص پورت:** در `ephemeral_tester.dart`، از `PortAllocator` برای دریافت پورت SOCKS (مثلاً `11000`) استفاده می‌شود و پورت HTTP یک عدد بالاتر (`11001`) تعیین می‌شود. این اطلاعات برای ساخت JSON (توسط `_generateConfigWrapper`) استفاده می‌شود.
- **اجرای پراکسی در سمت Native:** متد `NativeVpnService.startTestProxy` فراخوانی می‌شود و در `MainActivity.kt`/`SingboxVpnService.kt` JSON دریافت می‌شود. مشکل اینجاست که در `SingboxVpnService` تنها پورت SOCKS از JSON استخراج و ساخته می‌شود و `httpPort` برای ساخت پراکسی HTTP به Libbox داده نمی‌شود.
- **پروب HTTP (HTTP Probe):** بعد از راه‌اندازی، `ephemeral_tester.dart` از طریق `HttpClient` و ست کردن پروکسی HTTP روی `127.0.0.1:11001` درخواست تست ارسال می‌کند، که با خطای `Connection reset by peer` مواجه می‌شود (زیرا پراکسی روی این پورت وجود ندارد).
- **Grace Period و Watchdog:** در `connection_home_screen.dart`، یک تایمر ۸ ثانیه‌ای به عنوان `grace period` وجود دارد. همزمان در `ConfigManager` یک `Strict Watchdog` در متد `_startWatchdog` وجود دارد که در صورت طولانی شدن تست‌ها کانفیگ‌ها را Invalid می‌کند.

### الگوریتم رتبه‌بندی و حافظه (Scoring, Tiering & Persistence Memory)
- **حافظه معتبر (Valid Cache):** `ConfigManager` نتایج موفق را در لیستی به نام `validatedConfigs` نگه می‌دارد و بر اساس پینگ (`latency`) سورت می‌کند.
- **ذخیره‌سازی (Persistence):** متدهای ذخیره‌سازی از کلاس `StorageInterface` (بر پایه `shared_preferences`) استفاده می‌کنند تا لیست کانفیگ‌ها را به صورت JSON نگهداری کنند. اما تاریخچه دقیق (مثل پینگ آخرین تست) پس از راه‌اندازی مجدد اپلیکیشن ممکن است به درستی Restore یا اولویت‌بندی نشود (متد `saveConfigs`).
- **انتخاب بهترین سرور:** متد `getBestConfig()` سعی می‌کند بهترین سرور را انتخاب کند. اولویت آن: سروری که قبلاً به عنوان `lastConnected` انتخاب شده و معتبر است، سپس اولین سرور در لیست `validatedConfigs` (کمترین پینگ).

### ماشین وضعیت اتصال و رفتارهای خودکار (Connection State Machine & Fallbacks)
- زمانی که کاربر وارد برنامه می‌شود، `HomeScreen` وارد وضعیت `auto_testing` می‌شود.
- اگر `Discovery grace period` تمام شود و سرور `valid` پیدا نشود، برنامه تلاش می‌کند با استفاده از **Fallback مستقیم** به یک کانفیگ تست‌نشده متصل شود (متد `_connectToBestServer`). اینجاست که `Pre-flight check inconclusive` در `ConfigManager` رخ داده و مستقیماً متد اتصال Native فراخوانی می‌شود. از آنجا که کانفیگ خراب است، سیستم عامل تونل VPN را می‌سازد اما ترافیک Route نمی‌شود و با خطای `Active ping failed` پس از چند ثانیه قطع می‌شود.

### سیستم اعلان‌ها (Notification & Alert Mechanism)
- در حال حاضر در `splash_screen.dart` متد `Permission.notification.request()` فراخوانی می‌شود اما هیچ اثری از `flutter_local_notifications` یا مدیریت Notification واقعی (مانند ایجاد Channel و نمایش پیغام در Background/Foreground) در `ConfigManager` یا `ConnectionHomeScreen` وجود ندارد. پیام‌ها در سطح UI با `SnackBar` (مثلاً خطای اینترنت یا لود نشدن لیست) به صورت خام نمایش داده می‌شوند.

## ۲. طراحی الگوریتم هدف (Target Algorithm Design based on Existing Code)

برای اصلاح ساختار با کمترین تغییر در معماری اصلی:
- **تخصیص پورت‌ها در Tester:** به جای درخواست از Kotlin برای ساخت HTTP Proxy مفقود شده، می‌توانیم در سمت Dart و Kotlin از یک Inbound یکپارچه (مثل Tun یا Mixed) استفاده کنیم، یا اینکه در `SingboxVpnService`، آرایه `inbounds` دقیقاً به صورت خام (بدون بازنویسی یا فیلتر SOCKS) به `Libbox` پاس داده شود تا پراکسی HTTP نیز فعال شود.
- **صف اولویت‌بندی‌شده هوشمند (Smart Memory Queue):** در `ConfigManager`، لیست سرورها برای تست در ابتدای برنامه به این صورت مرتب شوند: ۱) شناسه آخرین اتصال موفق ۲) سرورهای `valid` قبلی ذخیره شده در دیتابیس لوکال (SharedPreferences) بر اساس پینگ ۳) سرورهای جدید تست‌نشده ۴) سرورهای خراب قبلی (فقط به عنوان Fallback).
- **منع اتصال خودکار:** حذف رفتار Fallback در اتمام `Grace period`. اگر هیچ سروری تایید نشد، State روی `idle` برود و کاربر را از طریق UI مطلع کند، و از اتصال به سرور تست‌نشده جداً خودداری شود.
- **سیستم اعلان:** اضافه‌کردن متد در `ConfigManager` که پس از موفقیت تست اولین سرور با پینگ زیر یک Threshold (مثلاً ۳۰۰ میلی‌ثانیه)، در صورتی که برنامه در Background است یک Notification سیستم (از طریق یک Notification Service ساده) یا در Foreground یک دیالوگ یا Badge نمایش دهد: "سرور مناسب یافت شد. برای اتصال کلیک کنید".

## ۳. لیست جامع مشکلات فنی، منطقی و امنیتی (Technical & Architectural Issues)

- [ ] **TECH-01** `[CRITICAL]` - **Race Condition در Android MethodChannel Result:**
  - مدیریت ناصحیح بازگشت Result در `startActivityForResult` در فایل `MainActivity.kt` که باعث معلق ماندن Futures و فریز شدن اپلیکیشن می‌شود.
- [ ] **TECH-02** `[HIGH]` - **استفاده بی‌رویه از `compute` برای داده‌های خرد:**
  - تحمیل Overhead بالای ایجاد Isolate برای متدهای Parse کوچک در `config_manager.dart` و `ephemeral_tester.dart`.
- [ ] **TECH-03** `[HIGH]` - **استفاده نادرست از `setState` به جای Local State:**
  - در صفحاتی مانند `ConnectionHomeScreen` تغییر متغیرهای جزئی باعث Rebuild سنگین ویجت تری می‌شود.
- [ ] **TECH-04** `[CRITICAL]` - **اتصال خطرناک به سرورهای تاییدنشده (Watchdog Fallback):**
  - در صورت اتمام `Grace period` در `connection_home_screen.dart` (خط ۱۲۸۵) یا وقوع `Pre-flight check inconclusive` در `ConfigManager` (خط ۱۲۳۳)، کلاینت به سرور تست‌نشده وصل شده و باعث مسدود شدن ارتباط شبکه و Timeouts می‌شود.
- [ ] **TECH-05** `[HIGH]` - **قفل شدن State روی `requesting_permission`:**
  - در نتیجه عدم دریافت پاسخ موفق یا خطا از Native، ماشین وضعیت اتصال در UI (خط ۱۱۶۹) در حالت دریافت پرمیشن گیر کرده و کلیک‌های بعدی نادیده گرفته می‌شود.
- [ ] **TECH-06** `[CRITICAL]` - **باگ `Connection reset by peer` در تست پراکسی:**
  - تنظیمات `httpPort` ارسال شده از سمت Dart، در `SingboxVpnService` اندروید نادیده گرفته شده و در نتیجه `Libbox` تنها روی `socksPort` باز می‌شود، که باعث شکست تمام تست‌های HTTP Probe در `127.0.0.1:11001` می‌گردد.
- [ ] **TECH-07** `[MEDIUM]` - **نشت حافظه در Timer ها و Stream ها:**
  - در کلاس `NativeVpnService` چندین Stream Broadcast وجود دارد که در متد `dispose` بسته‌بندی کاملی ندارند یا باگ‌های مربوط به Event Channel های بسته نشده در Android ممکن است منجر به Memory Leak شوند.

## ۴. لیست جامع بهبودهای UI/UX (UI/UX Improvement Actions)

- [ ] **UX-01** `[HIGH]` - **عدم پشتیبانی از RTL در Layout ها:**
  - در `connection_home_screen.dart` و `settings_screen.dart` حاشیه‌بندی‌ها به صورت Hardcode شده (`Left/Right`) هستند که در زبان‌های راست‌چین رابط کاربری را به هم می‌ریزد.
- [ ] **UX-02** `[MEDIUM]` - **گزارش‌دهی نامفهوم خطا در `ConfigCard`:**
  - وضعیت‌های عدم موفقیت (شکست تست یا Timeout) تنها با رنگ‌ها نشان داده می‌شوند و آیکون یا Tooltip مشخصی برای آگاه‌سازی کاربر درباره دلیل خرابی ندارند.
- [ ] **UX-03** `[MEDIUM]` - **طراحی متکی به رنگ برای دسترس‌پذیری (Accessibility):**
  - مقادیر Ping در `ConfigCard` برای افراد کوررنگ قابل تشخیص نیست؛ نیاز به برچسب‌های متنی یا آیکونیک در کنار رنگ‌های سبز/زرد/قرمز می‌باشد.
- [ ] **UX-04** `[LOW]` - **نبود وضعیت Empty State برای لیست سرورها:**
  - اگر هیچ کانفیگی توسط `ConfigGistService` واکشی نشود یا لود لیست خطا بخورد، هیچ تصویر Placeholder مناسبی با امکان Try Again نمایش داده نمی‌شود.
