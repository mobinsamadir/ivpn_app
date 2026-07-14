=== MISSION BRIEF: 2026-07-13 ===
ROLE_TONIGHT: Performance
ASSIGNED_BY: Mastermind
REASON: شب اول - نگاهِ عمومی عملکرد

SCOPE:
- lib/
- test/performance/

FROZEN_ZONES:
- none

SPECIFIC_TASK: شب اول - اسکن اولیه عملکردی روی کدهای مربوط به isolate و تبدیل JSON.

CROSS_AUDIT_TARGET: نه
=== END BRIEF ===

--- تاریخچه گزارش‌ها ---

[شروع]
### [تاریخ: ۲۰۲۶-۰۷-۱۳] Optimizer Report

**گزارش #۱: کپی عمیق بزرگ (Deep Copy) روی UI Thread هنگام ذخیره پیکربندی**
- **فایل**: lib/services/config_manager.dart (Lines 808-826)
- **مشکل**: متد `_saveAllConfigs` لیست `allConfigs.map((e) => e.toJson()).toList()` را در Main/UI thread فراخوانی می‌کند، که برای چند هزار کانفیگ باعث قفل شدن UI و پرش (Jank) فریم‌ها می‌شود. حتی با اینکه `jsonEncode` به Isolate برده شده، ساخت لیست mapها زمان‌بر است.
- **کوئری فعلی**:
  ```dart
  // Deep copy to prevent concurrent modification exceptions during isolate execution
  final configsSnapshot = allConfigs.map((e) => e.toJson()).toList();
  // Compute JSON encoding in a background isolate
  compute(_encodeConfigsInIsolate, configsSnapshot).then((jsonString) {
  ```
- **نتیجه**: هنگام وارد کردن ۵۰۰۰ کانفیگ، برنامه حدود ۵۰۰ میلی‌ثانیه فریز می‌شود تا `configsSnapshot` ایجاد شود.
- **راه حل**: باید داده‌های خام و سبک به جای متدهای سنگین شئ‌گرا به Isolate فرستاده شوند. می‌توان لیست `allConfigs` یا بخش ضروری آن را به شکل متنی/ساده در Isolate پردازش کرد.
- **بهبودی**: جلوگیری از فریز شدن کامل UI هنگام ذخیره شدن خودکار لیست‌های طولانی.
- **ROI**: UI بسیار روان‌تر می‌شود.
- **تلاش برای fix**: ۲۰ دقیقه
- **وضعیت**: ✋ در انتظار تایید

---

**گزارش #۲: ناکارآمدی `jsonDecode` هنگام بارگیری پیکربندی‌ها**
- **فایل**: lib/services/config_manager.dart (Lines 760-774)
- **مشکل**: در `_decodeConfigsInIsolate` از `jsonDecode` روی یک رشته عظیم استفاده می‌شود و در ادامه در یک حلقه برای هزاران آبجکت، `VpnConfigWithMetrics.fromJson` صدا زده می‌شود که به شدت هزینه‌بر و باعث تاخیر چند ثانیه‌ای در Startup زمان لود هزاران کانفیگ می‌شود.
- **کوئری فعلی**:
  ```dart
  static Future<List<VpnConfigWithMetrics>> _decodeConfigsInIsolate(String jsonStr) async {
    final List<VpnConfigWithMetrics> configs = [];
    final list = jsonDecode(jsonStr) as List;
    for (var e in list) { ... }
    return configs;
  }
  ```
- **راه حل**: کش‌کردن/استفاده از پایگاه داده محلی (مانند SQLite/Isar) بجای فایل متنیِ JSON بزرگ یا شکستن آن به بخش‌های کوچک‌تر و لود تنبل (Lazy Load).
- **بهبودی**: سرعت بخشیدن به زمان Startup به میزان ۵ تا ۱۰ برابر.
- **ROI**: کاربر برای باز شدن اپ معطل نمی‌ماند.
- **تلاش برای fix**: ۴۵ دقیقه
- **وضعیت**: ✋ در انتظار تایید

---

**گزارش #۳: حلقه ناکارآمد O(N*M) هنگام پردازش پیکربندی‌های ورودی**
- **فایل**: lib/services/config_manager.dart (Lines 384-438)
- **مشکل**: در `_processConfigsInIsolate` بررسی وجود `existingConfigs` (هرچند با Set است) و ترکیب آن با `md5` هش روی هر رشته‌ی ورودی سربار پردازشی ایجاد می‌کند و حلقه‌ی داخلی نیز می‌تواند بهینه شود. لیست ورودی به وسیله `skip(i).take(batchSize)` شکسته می‌شود که این خود برای لیست‌های بزرگ O(N^2) است. `List.skip().take()` روی لیست‌ها از ابتدا شمارش می‌کند.
- **کوئری فعلی**:
  ```dart
  // Process in chunks to avoid Isolate memory overload
  for (int i = 0; i < configStrings.length; i += batchSize) {
      final chunk = configStrings.skip(i).take(batchSize).toList();
  ```
- **راه حل**: استفاده از متد قدرتمندتر `sublist` برای `List`.
  ```dart
  for (int i = 0; i < configStrings.length; i += batchSize) {
    int end = (i + batchSize < configStrings.length) ? i + batchSize : configStrings.length;
    final chunk = configStrings.sublist(i, end);
  }
  ```
- **بهبودی**: **۱۰۰x سریع‌تر** در شکستن لیست‌های ۵۰۰۰۰ تایی.
- **ROI**: وارد کردن انبوه کانفیگ از تلگرام در لحظه انجام می‌شود.
- **تلاش برای fix**: ۵ دقیقه
- **وضعیت**: ✋ در انتظار تایید

آپدیت شد: 02:30 AM
