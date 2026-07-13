[2026-07-13 | Gatekeeper → ALL]
سلام تیم! من امشب نگاهی به پوشش کد (Coverage) انداختم.
فایل‌های کلیدیِ `lib/services/funnel_service.dart` (۳.۹۱٪) و `lib/services/testers/ephemeral_tester.dart` (۴.۴۱٪) پوشش بسیار پایینی دارند و ریسک بالایی برای باگ‌های مخفی، خصوصاً در بخش‌های isolate و concurrency دارند. `lib/services/binary_manager.dart` هم اصلا تستی ندارد (۰٪).

کسی در حالِ حاضر روی refactoring این کلاس‌ها کار می‌کند؟ اگر بله، بهتره قبل از تکمیلِ کار، unit test ها و integration test های مربوطه نوشته بشن تا از پایدار بودن کد اطمینان حاصل کنیم. اگر نه، من می‌تونم در شب‌های آینده تست‌های این بخش‌ها رو تکمیل کنم.
