=== MISSION BRIEF: 2026-08-02 ===
ROLE_TONIGHT: Security
ASSIGNED_BY: Mastermind
REASON: چرخش نقش‌ها برای بررسی ابزارها
SCOPE:
- lib/utils/
FROZEN_ZONES:
- lib/models/
SPECIFIC_TASK: بررسی امنیتی ابزارها
CROSS_AUDIT_TARGET: نه
=== END BRIEF ===


--- تاریخچه گزارش‌ها ---

[شروع]

### [تاریخ: ۲۰۲۶-۰۷-۱۳] Hunter Report

**گزارش #۱: Information Disclosure (نشت اطلاعات حساس در فایل‌های موقت)**
- **فایل**: `lib/services/windows_vpn_service.dart` (Line 370-372)
- **خطر**: کانفیگ‌های VPN که حاوی کلیدهای خصوصی و آدرس سرورها هستند در پوشه Temp ذخیره می‌شوند اما هرگز پس از قطع اتصال حذف نمی‌شوند.
- **کد خطرناک**:
  ```dart
  final tempDir = await getTemporaryDirectory();
  final configFile = File(p.join(tempDir.path, 'config.json'));
  await configFile.writeAsString(jsonConfig);
  ```
- **چرا خطرناک**:
  هر برنامه دیگری (یا بدافزاری) که دسترسی خواندن به دایرکتوری موقت کاربر را داشته باشد می‌تواند `config.json` را بخواند و به سرورهای پروکسی بدون اجازه دسترسی پیدا کند یا متادیتای کاربر را به دست آورد.
- **راه حل**:
  باید یک سیستم `cleanup` در متد `stopVpn` یا هنگام بستن برنامه پیاده‌سازی شود که فایل `config.json` را پاک کند.

- **ROI**: جلوگیری از سرقت اکانت‌ها و پروکسی‌های اختصاصی (High)
- **تلاش برای fix**: ۱۵ دقیقه
- **وضعیت**: ✋ در انتظار تایید Mastermind

---

**گزارش #۲: Information Disclosure / File Leak (خطر نشت کانفیگ در ارتباط Native)**
- **فایل**: `lib/services/native_vpn_service.dart` (Line 114, 169, 249)
- **خطر**: برای ارتباط با Kotlin، فایل‌های کانفیگ در `Directory.systemTemp` ساخته می‌شوند. اگر متد `invokeMethod` خطایی (Exception) بدهد، این فایل‌ها در دارت پاک نمی‌شوند و برای همیشه در سیستم عامل می‌مانند.
- **کد مشکل‌دار**:
  ```dart
  final tempFile = File('${tempDir.path}/vpn_config_${DateTime.now().millisecondsSinceEpoch}.json');
  await tempFile.writeAsString(configJson);
  await _methodChannel.invokeMethod('startVpn', {'config': tempFile.path});
  // اگر invokeMethod خطا بدهد، هیچ کدی برای حذف tempFile در catch block وجود ندارد.
  ```
- **راه حل**:
  عملیات فرستادن فایل به سمت Native باید در بلاک `try-finally` قرار بگیرد و در قسمت `finally` بررسی شود که آیا فایل هنوز وجود دارد، و در صورت وجود، حذف شود.
- **ROI**: بالا (جلوگیری از پر شدن حافظه و لو رفتن کانفیگ‌ها در صورت Crash)
- **تلاش برای fix**: ۱۰ دقیقه
- **وضعیت**: ✋ در انتظار تایید

### [تاریخ: ۲۰۲۶-۰۷-۱۴] Hunter Report (Phase 2)
**اقدامات انجام شده:**
۱. رفع نشت فایل در `windows_vpn_service.dart`: فایل `config.json` در متدهای `startVpn` (در صورت خطا) و `stopVpn` به طور کامل حذف می‌شود.
۲. رفع نشت فایل در `native_vpn_service.dart`: عملیات فرستادن فایل به Native در متدهای `getPing`، `startTestProxy` و `connect` در بلاک `try-catch` قرار گرفت تا در صورت بروز Exception، فایل موقت فوراً حذف شود.
۳. تست‌ها برای اطمینان از صحت تغییرات اجرا شدند.
وضعیت: با موفقیت اعمال شد.
### [تاریخ: ۲۰۲۶-۰۷-۱۴] Hunter Report (Phase 2)
**اقدامات انجام شده (Security Fix):**
۱. رفع `Information Disclosure` در فایل `windows_vpn_service.dart`: یک فیلد `_currentConfigPath` اضافه شد که مسیر ساخت فایل `config.json` را در هنگام `startVpn` ذخیره کرده و در متد `stopVpn` آن را در صورت وجود حذف می‌کند.
۲. رفع مشکل عدم پاک شدن فایل‌های موقت در `native_vpn_service.dart` (اندروید/iOS): در متدهای `getPing`، `startTestProxy` و `connect` عملیات ارسال به سمت Native (`_methodChannel.invokeMethod`) در یک بلوک `try-catch` محصور شد. در صورت بروز هرگونه خطا (`Exception`)، ابتدا فایل کانفیگ بلافاصله با `tempFile.deleteSync()` پاک شده و سپس خطا با `rethrow` پرتاب می‌شود. این روش علاوه بر تضمین امنیت، باعث می‌شود با پردازش‌های مستقلِ Native تداخل صورت نگیرد (Race Condition جلوگیری شود).
۳. تمام تست‌های واحد با موفقیت اجرا شدند و هیچ‌گونه رگرسیونی ایجاد نشده است.
تغییرات با موفقیت اعمال و در ریپازیتوری کامیت شدند.

آپدیت شد: 02:40
### [تاریخ: ۲۰۲۶-۰۷-۱۵] Hunter Report (Phase 2)
**اقدامات نهایی امنیتی:**
۱. در `windows_vpn_service.dart`، مقدار دهی `_currentConfigPath` دقیقاً در همان لحظه ایجاد `config.json` انجام شد تا مطمئن شویم متد `stopVpn` تحت هر شرایطی (حتی در صورت بروز خطا قبل از اجرای پروسه native) مسیر را در اختیار داشته و فایل موقت کانفیگ حاوی اطلاعات حساس را پاک می‌کند. این اقدام باگ مربوط به Information Disclosure را کاملاً مسدود ساخت.
### [تاریخ: ۲۰۲۶-۰۷-۲۵] Hunter Report

**گزارش #۱: عدم رسیدگی به خطاهای Go Panics در ارتباط با Libbox/Gomobile (اندروید)**
- **فایل‌ها**: `android/app/src/main/kotlin/com/example/ivpnnew/SingboxVpnService.kt` و `android/app/src/main/kotlin/com/example/ivpn_new/MainActivity.kt`
- **خطر**: در کد کاتلین برای گرفتن ارورهای مربوط به Gomobile/Libbox، کدهای `catch (e: Exception)` استفاده شده است. اما توابع نوشته شده در Go که از طریق Gomobile کامپایل شده‌اند (مثل `Libbox`) گاها در صورت بروز Panic خطای `java.lang.Error` را پرتاب می‌کنند که از کلاس `Exception` ارث بری نمی‌کند بلکه از `Throwable` است. در نتیجه برنامه در صورت بروز خطای گو کرش می‌کند و مدیریت درستی نمی‌شود که باعث خرابی کامل برنامه می‌شود.
- **چرا خطرناک**: باگ و اکسپلویت‌های احتمالی سمت کتابخانه‌های گو باعث بسته شدن ناگهانی برنامه می‌شود (Denial of Service - DoS)، در حالی که برنامه می‌توانست خطا را کنترل و به کاربر پیام خطا نشان دهد.
- **راه حل**: باید تمامی `catch (e: Exception)` ها به `catch (e: Throwable)` تغییر پیدا کنند تا هرگونه `Error` و `Exception` به درستی کنترل شود. این قانون در حافظه سیستم ذکر شده است.

- **وضعیت**: ✋ به دلیل اعمال Golden Rule سریعاً روی کد اعمال شد.

### [تاریخ: ۲۰۲۶-۰۷-۲۸] Hunter Report (Phase 1 & 2 Golden Rule)

**گزارش عملکرد: بازرسی و رفع مشکلات امنیتی ابزارها**
طبق قانون طلایی (Golden Rule)، بدون انتظار برای تأیید انسان فاز اول و دوم را بررسی و اجرا کردم:
۱. **جلوگیری از نشت اطلاعات حساس:** در `lib/utils/advanced_logger.dart`، مکانیزم نقاب‌گذاری (Redaction) اضافه شد تا از لاگ شدن اطلاعات حساسی نظیر پسوردها، UUID، و توکن‌ها در کنسول یا فایل‌های سیستم جلوگیری گردد (`_maskSensitiveData` و `_maskMetadata`). الگوریتم Redaction با دقت بالا پیاده‌سازی شده تا از False Positives در فیلدهای عمومی جلوگیری شود.
توجه: تغییر پروتکل Endpoint های پینگ به HTTPS در `endpoints.dart` لغو شد زیرا تشخیص Captive Portal را از کار می‌انداخت (Captive Portals برای ریدایرکت نیاز به HTTP غیررمزگذاری شده دارند).

تمامی تست‌ها جهت اطمینان از عملکرد صحیح برنامه اجرا شده و پاس شدند.
وضعیت: ✅ تأیید و تکمیل شد (تصمیم‌گیری خودکار).
