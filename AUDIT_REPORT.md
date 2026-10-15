# گزارش بررسی معماری و تجربه کاربری (Audit Report)

## ۱. خلاصه وضعیت و استک شناسایی‌شده
- **پلتفرم‌ها:** فلاتر (iOS, Android, Windows)
- **معماری مدیریت وضعیت:** Provider, ValueNotifier
- **سرویس‌های Native:** استفاده از MethodChannel (مانند VpnService در اندروید)
- **شبکه و ارتباطات:** dio، http، اتصال VPN (V2Ray/Sing-Box)

## ۲. لیست فایل‌ها و ماژول‌های بررسی‌شده
- `pubspec.yaml`
- `lib/main.dart`
- `lib/services/native_vpn_service.dart`
- `lib/services/config_manager.dart`
- `lib/screens/connection_home_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/widgets/config_card.dart`
- `lib/widgets/update_dialog.dart`
- `android/app/src/main/kotlin/com/ivpn_new/MainActivity.kt`

## ۳. گزارش مشکلات فنی و منطقی

### ۳.۱ مدیریت اتصالات و پلتفرم (Platform Channel & Async)

- [ ] **TECH-01** `[CRITICAL]` - **Race Condition در Android MethodChannel Result:**
  - **آدرس:** `android/app/src/main/kotlin/com/ivpn_new/MainActivity.kt` (خطوط ۱۲۰ تا ۱۸۰)
  - **علت:** متدهای کانال مانند `testConfig` و `startTestProxy` به `VpnService.prepare` وابسته‌اند و `startActivityForResult` را فراخوانی می‌کنند، اما `Result` در همان متد خاتمه نمی‌یابد و بازگردانده نمی‌شود. در فلاتر، این منجر به معلق ماندن `await`ها (Unawaited Futures) می‌شود تا زمانی که Activity Result به یک Listener برسد.
  - **راه‌حل:** در اندروید، نتیجه باید در بلوک `onActivityResult` هندل شود یا در صورت نیاز به ادامه، نتیجه از طریق یک ذخیره‌ساز (مثل `pendingResult`) با مدیریت دقیق همگام شود. در صورت عدم دریافت Permission باید ارور برگردانده شود.

- [ ] **TECH-02** `[HIGH]` - **استفاده از JSON.decode در داخل Compute برای داده‌های بسیار کوچک (Overhead):**
  - **آدرس:** `lib/services/config_manager.dart` (خط ۴۸۴، ۸۷۸، ۹۰۳، ۹۵۳ و ...)
  - **علت:** برای استخراج و پارس کردن تمام داده‌های کوچک یا تبدیل `configs` به `JSON`، به طور گسترده از `compute` (Isolates) استفاده شده است. شروع یک Isolate جدید برای داده‌های کوچک به دلیل Overhead ایجاد آن، باعث کاهش عملکرد و حتی کندی بیشتر نسبت به پردازش همگام در UI Thread می‌شود.
  - **راه‌حل:** محدود کردن `compute` فقط برای لیست‌های طولانی یا پردازش‌هایی که اندازه داده از یک آستانه مشخص (Threshold) بیشتر است. برای دیتای کوچک، از تبدیل همگام استفاده شود.

### ۳.۲ مدیریت وضعیت در UI

- [ ] **TECH-03** `[HIGH]` - **استفاده نادرست از `setState` به جای مدیریت وضعیت خرد (Local State) در صفحه‌های اصلی:**
  - **آدرس:** `lib/screens/connection_home_screen.dart` (خط ۶۱۸، ۶۳۲)، `lib/screens/settings_screen.dart` (خط ۳۶ و ۵۹ و ...) و `lib/widgets/update_dialog.dart` (استفاده متعدد)
  - **علت:** به جای استفاده از `ValueNotifier` و `ValueListenableBuilder`، به وفور از `setState` برای تغییر متغیرهای جزئی (مانند `_autoTestOnStartup`) در صفحات اصلی استفاده شده است. این کار باعث Rebuild کامل ویجت تری (Widget Tree) آن صفحات، خصوصاً صفحات سنگین می‌شود که منجر به کندی رندر (Jank) خواهد شد.
  - **راه‌حل:** تغییر متغیرهای وضعیت جزئی به `ValueNotifier` و آپدیت کردن تنها بخش‌های وابسته به آنها با `ValueListenableBuilder`.

## ۴. گزارش بهبودهای UI/UX

### ۴.۱ راست‌چین (RTL) و لایوت (Layout)

- [ ] **UX-01** `[HIGH]` - **عدم پشتیبانی صریح از جهت‌گیری‌های زبان (Directionality / RTL):**
  - **آدرس:** `lib/screens/connection_home_screen.dart`, `lib/screens/settings_screen.dart`
  - **علت:** با وجود امکان چندزبانگی یا اجرای برنامه در دستگاه‌هایی با زبان پیش‌فرض راست‌به‌چپ (مثل فارسی/عربی)، استفاده از `Directionality` در سطوح بالا صریحاً مدیریت نشده یا کامپوننت‌ها براساس `Start/End` طراحی نشده‌اند (استفاده از `Left/Right` سخت‌کد شده). این امر باعث بهم‌ریختگی رابط کاربری در زبان‌های RTL می‌شود.
  - **راه‌حل:** به جای حاشیه‌های چپ/راست (`padding: EdgeInsets.only(left: ...)`), از معادل‌های راست‌چین (`EdgeInsetsDirectional`) و برای ترازبندی‌ها از `AlignmentDirectional` استفاده شود تا هماهنگی با RTL حفظ شود.

### ۴.۲ حالت‌های تعاملی و نمایشی

- [ ] **UX-02** `[MEDIUM]` - **وضعیت‌های نامشخص هنگام تست لاتنسی و سرعت در `ConfigCard`:**
  - **آدرس:** `lib/widgets/config_card.dart`
  - **علت:** با اینکه نمایش حالت تست با یک `CircularProgressIndicator` پیاده‌سازی شده، اما وضعیت "عدم موفقیت/شکست (Failed/Timeout)" یا "خالی (Empty)" به صورت واضح برای کاربر مشخص نیست (صرفاً از رنگ‌ها استفاده شده، رنگ قرمز برای Poor).
  - **راه‌حل:** در کنار رنگ‌بندی، یک آیکون کوچک برای خطای اتصال یا پیام و وضعیت‌های شفاف‌تر به کارت‌ها افزوده شود تا بدون نیاز به دانش قبلی، کاربر با یک نگاه وضعیت سرور را درک کند.

- [ ] **UX-03** `[MEDIUM]` - **طراحی متکی بر رنگ (Color-reliance) برای مقادیر متریک:**
  - **آدرس:** `lib/widgets/config_card.dart` (توابع `getPingColor` و `getTierColor`)
  - **علت:** مقادیر مختلف پینگ صرفاً با رنگ‌ها متمایز شده‌اند (سبز، زرد، قرمز). این مسئله از نظر دسترس‌پذیری (Accessibility) برای افراد مبتلا به کوررنگی مشکل‌ساز است.
  - **راه‌حل:** علاوه بر رنگ، استفاده از برچسب‌های متنی یا آیکون‌های متناسب با وضعیت (مانند استفاده از یک آیکون Wi-Fi با نوارهای کمتر برای پینگ ضعیف).

## ۵. ابهامات و موارد نیازمند تست Runtime
- **مدیریت خطاهای MethodChannel در ویندوز:** در `NativeVpnService` ذکر شده که برخی متدها مثل درخواست پرمیشن، در ویندوز بلافاصله `true` بازمی‌گردانند. باید بررسی شود که رفتار برنامه در محیط واقعی ویندوز چه خواهد بود (آیا کرش می‌کند یا خطا به طور خاموش نادیده گرفته می‌شود؟).
- **حافظه و Stream Controllers:** در کلاس‌های `NativeVpnService` و `ConfigManager` چندین استریم به صورت Broadcast ایجاد شده‌اند. باید با ابزارهای Profiling مطمئن شد که تمام این استریم‌ها در زمان اتمام استفاده (Dispose) بسته می‌شوند و Memory Leak رخ نمی‌دهد.

## ۶. نقشه راه اجرایی (Action Plan)

1. **فاز ۱: پایداری پلتفرم (Platform Stability) - اولویت بالا**
   - رفع باگ‌های ارتباطی Native (MethodChannel) به ویژه مدیریت Result‌های `Activity` در اندروید (`TECH-01`).

2. **فاز ۲: بهبود عملکرد کلاینت و معماری State - اولویت بالا**
   - جایگزینی `setState` در کلاس‌های اصلی با `ValueNotifier` (`TECH-03`).
   - بازنگری در استفاده از Isolates (`compute`) برای دیکود JSON کوچک (`TECH-02`).

3. **فاز ۳: اصلاحات رابط کاربری و تجربه کاربری (UI/UX) - اولویت متوسط**
   - پیاده‌سازی سیستم یکپارچه RTL با تغییر `EdgeInsets` به `EdgeInsetsDirectional` (`UX-01`).
   - بهبود وضعیت‌های قابل رویت در کامپوننت‌های کارت سرور و افزودن المان‌های Accessible (`UX-02` و `UX-03`).

---
**Uninspected / Remaining Areas:**
- `lib/services/testers/*` (نیاز به بازبینی مکانیزم تست کانفیگ‌ها و Threading)
- `lib/widgets/shimmer_*.dart` (بررسی دقیق اسکلتون‌های لودینگ)
- `packages/*` (پکیج‌های کاستوم مثل `flutter_secure_storage_windows`)
