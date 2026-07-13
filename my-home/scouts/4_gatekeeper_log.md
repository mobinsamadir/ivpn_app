=== MISSION BRIEF: 2026-07-13 ===
ROLE_TONIGHT: QA/Testing
ASSIGNED_BY: Mastermind
REASON: شب اول - نگاهِ عمومی به تست‌ها و پوشش کد

SCOPE:
- test/
- lib/services/

FROZEN_ZONES:
- none

SPECIFIC_TASK: شب اول - بررسی وضعیت تست‌های موجود و پوشش کدهای حساس.

CROSS_AUDIT_TARGET: نه
=== END BRIEF ===

--- تاریخچه گزارش‌ها ---

[شروع]

### [تاریخ: 2026-07-13] Gatekeeper Report

**گزارش #۱: صفر Coverage برای BinaryManager**
- **فایل**: lib/services/binary_manager.dart
- **مشکل**: این فایل کاملا فاقد تست است.
  - Coverage: ۰٪
  - Risk: متوسط

- **Logic غیرتست‌شده**:
  متد `ensureBinary` هیچ تستی برای حالت‌های مختلف سیستم‌عامل ندارد.

- **تست‌های مورد نیاز**:

  **Test Case 1: Android JNI Exception**
  ```dart
  void test_ensureBinary_android() {
    // Override platform to Android
    // Call BinaryManager.ensureBinary()
    // Expect UnsupportedError
  }
  ```

- **تلاش برای نوشتنِ تست**: ۱۵ دقیقه
- **وضعیت**: ✋ در انتظار تایید

---

**گزارش #۲: Coverage بسیار پایین برای FunnelService**
- **فایل**: lib/services/funnel_service.dart
- **مشکل**: اصلی‌ترین منطقِ پردازشِ صفِ تست‌ها تست نشده است.
- **نتایج Coverage**:
  ```
  Line coverage: ۳.۹۱٪
  ```

- **Methods بدون تست**:
  - `startFunnel`
  - `stop`
  - worker queues (`_tcpWorker`, `_httpWorker`, `_speedWorker`)

- **پیشنهاد**: این کلاس دارای لاجیک پیچیده isolate و concurrency است، بنابراین نیاز به integration test دارد تا از deadlock یا memory leak جلوگیری شود. minimum ۵۰٪ coverage.
- **تلاش برای بهبود**: ۶۰ دقیقه
- **اولویت**: بالا (Core logic)

---

**گزارش #۳: Coverage بسیار پایین برای EphemeralTester**
- **فایل**: lib/services/testers/ephemeral_tester.dart
- **مشکل**: منطق اصلی اجرای تست روی singbox باینری به درستی تست نشده است.
- **نتایج Coverage**:
  ```
  Line coverage: ۴.۴۱٪
  ```

- **Methods بدون تست**:
  - `runTest`
  - `_runDirectTest`

- **پیشنهاد**: باید تست‌هایی برای شبیه‌سازی response های مختلف sing-box با استفاده از mock process نوشته شود.
- **تلاش برای بهبود**: ۴۵ دقیقه
- **اولویت**: بالا
