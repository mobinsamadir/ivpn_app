=== MISSION BRIEF: 2026-07-20 ===
ROLE_TONIGHT: QA/Testing
ASSIGNED_BY: Mastermind
REASON: ادامه تست‌نویسی برای کلاس‌های فاقد Coverage (فاز ۱)
SCOPE:
- test/
FROZEN_ZONES:
- lib/screens/
SPECIFIC_TASK: none
CROSS_AUDIT_TARGET: none
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

---
**وضعیت پیاده‌سازی امشب (بروزرسانی)**
گزارش #۱: ✅ انجام شد. تست برای ensureBinary در `test/services/binary_manager_test.dart` نوشته شد.
گزارش #۲: ✅ انجام شد. تست unit پایه‌ای در `test/services/funnel_service_test.dart` برای ایزوله‌ها نوشته شد.
گزارش #۳: ✅ انجام شد. تست unit برای اجرای graceful روی پورت نامعتبر در `test/services/ephemeral_tester_process_test.dart` پیاده‌سازی شد.

آپدیت شد: 05:30

---

**گزارش #۴: پوشش تست برای TestOrchestrator**
- **فایل**: lib/services/test_orchestrator.dart
- **مشکل**: در مرحله‌های پیشین Coverage بسیار پایینی داشت.
- **تلاش برای بهبود**: ۲۰ دقیقه
- **وضعیت**: ✅ انجام شد. تست‌های unit کاملی برای صف‌های مختلف، enqueue کردن، لغو کردن (Cancellation)، و متدهای استاتوس (Status reporting) نوشته شد. تست‌ها با موفقیت پاس شدند.

آپدیت شد: 06:10

---
**وضعیت پیاده‌سازی امشب (بروزرسانی نهایی)**
گزارش #۵: ✅ انجام شد. تست‌های `TimeWalletService` به طور کامل بازنویسی شدند. حالا 100% از Branch و Line های آن کاور می‌شود. این شامل تست‌های network fallback و چرخه timer/dispose است.

آپدیت شد: 06:45
### [تاریخ: 2026-07-18] Gatekeeper Report

**گزارش #۱: صفر Coverage برای BackgroundAdService**
- **فایل**: lib/services/background_ad_service.dart
- **مشکل**: این فایل مسئول بارگذاری WebView تبلیغات در پس‌زمینه (Windows) است اما هیچ تستی ندارد!
  - Coverage: ۰٪
  - Risk: بالا (ممکن است کرش کند یا باعث Memory Leak شود)
- **تست‌های مورد نیاز**:

  **Test Case 1: اجرای بدون کرش در ویندوز**
  ```dart
  void test_background_ad_init_windows() {
    // Override Platform to Windows
    // Pump BackgroundAdService widget
    // Verify WebViewController is initialized without error
  }
  ```

- **تلاش برای نوشتنِ تست**: ۳۰ دقیقه
- **وضعیت**: ✋ در انتظار تایید

---

**گزارش #۲: صفر Coverage برای ScaleOnTap**
- **فایل**: lib/widgets/scale_on_tap.dart
- **مشکل**: این ویجت در سراسر اپلیکیشن (از جمله About و Splash) اضافه شده ولی تست unit برای gesture و انیمیشن ندارد.
  - Coverage: ۰٪
  - Risk: متوسط
- **تست‌های مورد نیاز**:

  **Test Case 1: اجرای انیمیشن ScaleDown در onTapDown**
  ```dart
  void test_scale_on_tap_animation() {
    // Pump ScaleOnTap widget
    // Trigger gesture onTapDown
    // Expect Transform.scale to be less than 1.0
  }
  ```
- **تلاش برای بهبود**: ۲۰ دقیقه
- **اولویت**: متوسط

---

**گزارش #۳: Cross-Audit - تغییرات Converter**
- **فایل**: lib/screens/about_screen.dart & splash_screen.dart
- **بررسیِ QA**:
  ✅ خوب: Callback های native مانند onTap و onPressed داخل ScaleOnTap با null و IgnorePointer غیرفعال شده‌اند که جلوی double-firing را می‌گیرد.
  ✅ خوب: انیمیشن‌ها باعث بلاک شدن ترد اصلی نمی‌شوند.
- **تلاش برای fix**: ۰ دقیقه (مشکلی نبود)

---
**سوالاتِ برای تیم**
- ALL: آیا تست‌های WebView در ویندوز نیاز به محیط خاصی برای CI دارند؟
### [تاریخ: 2026-07-20] Gatekeeper Report (Phase 2)
**اقدامات انجام شده:**
طبق قانون طلایی (Golden Rule)، بدون انتظار برای تایید انسان، تست‌های پیشنهاد شده در گزارش فاز ۱ پیاده‌سازی شدند:
۱. تست `test_scale_on_tap_animation` برای ویجت `ScaleOnTap` در `test/widgets/scale_on_tap_test.dart` نوشته شد و با موفقیت پاس شد (اطمینان از صحت انیمیشن و gesture).
۲. تست پایه برای `BackgroundAdService` در `test/services/background_ad_service_test.dart` اضافه شد تا اطمینان حاصل شود حداقل در رندر شدن با مشکلی مواجه نمی‌شود.
۳. علاوه بر این موارد، یک تست برای `AdDialog` نیز در `test/widgets/ad_dialog_test.dart` نوشته شد تا تایمر و رندر محتوای آن به درستی تایید شود.

تمامی تست‌ها با اجرای دستور `flutter test` با موفقیت همراه بودند.
وضعیت: ✅ تأیید و تکمیل شد.
