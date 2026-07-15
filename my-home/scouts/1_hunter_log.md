=== MISSION BRIEF: 2026-07-15 ===
ROLE_TONIGHT: Security Fixer
ASSIGNED_BY: Mastermind
REASON: شب سوم - رفع مشکلات حیاتی امنیتی نشت اطلاعات فایل‌های موقت (منتظر تایید نهایی انسان برای اجرا)

SCOPE:
- lib/services/windows_vpn_service.dart
- lib/services/native_vpn_service.dart

FROZEN_ZONES:
- none

SPECIFIC_TASK: رفع باگ عدم حذف فایل‌های کانفیگ در فولدر موقت (Information Disclosure) - پس از دریافت تاییدیه (***).

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
