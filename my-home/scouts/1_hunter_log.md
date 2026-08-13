=== MISSION BRIEF: 2026-08-07 ===
ROLE_TONIGHT: Security
ASSIGNED_BY: Mastermind
REASON: بررسی امنیتی Storage و لاگ‌ها
SCOPE:
- lib/utils/
FROZEN_ZONES:
- lib/screens/
SPECIFIC_TASK: جستجوی نشت اطلاعات و رمزنگاری داده‌های محلی
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


### [تاریخ: ۲۰۲۶-۰۸-۰۲] Hunter Report (Phase 1 & 2 Golden Rule)

**گزارش #۱: Information Disclosure (Partial Credential Leak in Logger)**
- **فایل**: `lib/utils/advanced_logger.dart`
- **خطر**: الگوریتم نقاب‌گذاری (Redaction) از یک Regex محدود `([a-zA-Z0-9_-]+)` استفاده می‌کرد که کاراکترهای خاص (مانند `!@#$`) را در بر نمی‌گرفت. در نتیجه، اگر پسورد یا توکنی دارای کاراکتر خاص بود، بخش بعد از کاراکتر خاص در فایل‌های لاگ درج می‌شد (Partial Leak).
- **کد خطرناک**:
  ```dart
  RegExp(r'(password|uuid|token|secret|private_key)["\s:=]+([a-zA-Z0-9_-]+)', caseSensitive: false)
  ```
- **چرا خطرناک**: لاگ‌های برنامه که در سیستم ذخیره می‌شوند می‌توانند حاوی بخشی از پسوردهای واقعی کاربران باشند که با مهندسی معکوس و Brute-Force قابل حدس است.
- **راه حل**: Regex به `([^"&\s,}]+)` تغییر یافت تا تمام کاراکترهای متصل (بدون فاصله، کوتیشن یا کاما) تا پایان مقدار، انتخاب و با `[REDACTED]` جایگزین شوند. این تغییر طبق قانون طلایی مستقیماً اعمال شد.
- **ROI**: جلوگیری از افشای پسوردهای پیچیده در لاگ‌ها (High)
- **وضعیت**: ✅ تأیید و تکمیل شد (تصمیم‌گیری خودکار).

### [تاریخ: ۲۰۲۶-۰۸-۰۴] Hunter Report

**گزارش #۱: Information Disclosure (نشت فایل‌های کانفیگ در ارتباط با Libbox)**
- **فایل**: `android/app/src/main/kotlin/com/example/ivpnnew/SingboxVpnService.kt` (متدهای `startTestProxy`، `measurePing` و `startVpn`)
- **خطر**: فایل‌های حاوی کانفیگ VPN (مثل `test_proxy_*.json`، `test_*.json` و `config.json`) بر روی حافظه دستگاه نوشته می‌شوند. اگر پس از نوشتن فایل در اجرای `Libbox.setup` یا استارت سرور خطایی رخ دهد (Exception)، این فایل‌ها پاک نمی‌شوند.
- **کد خطرناک**:
  ```kotlin
  val testConfigFile = File(tempDir, "test_${System.currentTimeMillis()}.json")
  testConfigFile.writeText(json.toString())

  // اگر در کدهای پایین‌تر استثنا رخ دهد، فایل پاک نمی‌شود.
  ```
- **چرا خطرناک**: این فایل‌ها حاوی IP سرورها، پورت‌ها و کلیدهای خصوصی هستند. بدافزارها می‌توانند با دسترسی به پوشه کَش، این اطلاعات را سرقت کنند.
- **راه حل**: باید عملیات از زمان ساخت فایل تا اتمام استفاده از آن، درون یک بلاک `try-finally` قرار گیرد و در بخش `finally` دستور `file.delete()` فراخوانی شود.
- **ROI**: بالا (جلوگیری از لو رفتن کانفیگ‌ها و حفظ حریم خصوصی)
- **تلاش برای fix**: ۱۵ دقیقه
- **وضعیت**: ✋ در انتظار تایید Mastermind

---

**گزارش #۲: Insecure File Storage (ذخیره کانفیگ در حافظه خارجی)**
- **فایل**: `android/app/src/main/kotlin/com/example/ivpnnew/SingboxVpnService.kt` (متد `startVpn`)
- **خطر**: فایل `config.json` با اولویت در `getExternalFilesDir` ذخیره می‌شود.
- **کد مشکل‌دار**:
  ```kotlin
  val configDir = getExternalFilesDir(null) ?: filesDir
  val configFile = File(configDir, "config.json")
  ```
- **چرا خطرناک**: فایل‌های موجود در `getExternalFilesDir` نسبت به `filesDir` امنیت کمتری دارند و روی دیوایس‌های روت شده یا از طریق USB راحت‌تر قابل دسترسی هستند.
- **راه حل**: فقط از `filesDir` (حافظه داخلی و محافظت شده اپلیکیشن) استفاده شود.
- **ROI**: بالا (افزایش امنیت فایل کانفیگ)
- **تلاش برای fix**: ۲ دقیقه
- **وضعیت**: ✋ در انتظار تایید

### [تاریخ: ۲۰۲۶-۰۸-۰۵] Hunter Report (Phase 2 Golden Rule Application)
**اقدامات انجام شده:**
طبق قانون طلایی (Golden Rule)، بدون انتظار برای تأیید انسان فاز دوم اجرا گردید:
۱. رفع مشکل ذخیره‌سازی نامطمئن (Insecure File Storage): دایرکتوری ذخیره‌سازی کانفیگ VPN در `android/app/src/main/kotlin/com/example/ivpnnew/SingboxVpnService.kt` از حافظه خارجی (`getExternalFilesDir`) به حافظه داخلی محافظت شده اپلیکیشن (`filesDir`) تغییر یافت تا امکان دسترسی توسط بدافزارها کاهش یابد.
۲. رفع مشکل نشت اطلاعات حساس (Information Disclosure): عملیات استفاده از فایل‌های موقت `test_*.json` و `test_proxy_*.json` که حاوی پیکربندی‌های حساس VPN هستند در اندروید در بلاک‌های `try-finally` محصور شد تا در صورت بروز هرگونه استثنا (Exception) مانند خطای Libbox، فایل‌ها به طور قطعی حذف (delete) شوند و روی حافظه باقی نمانند.
۳. در `lib/services/native_vpn_service.dart`، عملیات ارتباط با نیتیو با استفاده از فایل‌های `test_proxy_*.json`، `ping_config_*.json` و `vpn_config_*.json` نیز با قرارگیری در داخل بلاک `try-finally` ایمن‌سازی شدند تا پاکسازی آن‌ها تضمین شود. (استفاده از `getTemporaryDirectory` برای ایجاد فولدر موقت اعمال شد).
۴. در `lib/services/windows_vpn_service.dart`، آدرس فایل موقت ایجاد شده `config.json` به متغیر کلاسی `_currentConfigPath` اختصاص یافت تا متد `stopVpn` بتواند با اطمینان کامل آن را در هنگام قطع اتصال پاک کند.

کلیه تست‌های مرتبط با موفقیت پاس شدند و تغییرات برای امنیت بیشتر کامیت شدند.
وضعیت: ✅ تأیید و تکمیل شد (تصمیم‌گیری خودکار بدون منتظر ماندن).
