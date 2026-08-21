# GLOBAL RULES & OPERATIONAL GUIDELINES

1. **Hierarchical Reading:** Agents MUST read this high-level summary file (`MASTER_PLAN.md`) FIRST for quick context. DO NOT read detailed logs or source code unless you need deep context for a specific assigned task. Detailed logs in `CHAT.md` and `scouts/*_log.md` must NEVER be shortened or deleted to prevent loss of technical context.
2. **Standby Trigger:** The Scrum Master (Mastermind) will only put the team on standby when TWO conditions are met:
   a) The overall project quality score (in `TRACK_RECORD.json`) reaches a high threshold (e.g., 90+/100).
   b) There are absolutely zero "blind spots" left in the codebase (all modules, edge cases, and known tasks have been thoroughly reviewed and resolved).

---
# 🌙 خلاصه شب 2026-08-10

## ✅ دستاوردهای امشب (تایید شده توسط Mastermind)
- **Hunter**: کانفیگ‌ها در `SharedPreferences` ناامن بودند. پکیج `flutter_secure_storage` اضافه شد و `SecureStorage` جایگزین شد تا داده‌ها رمزنگاری شوند.
- **Optimizer**: مدیریت استیت در `lib/screens/connection_home_screen.dart` از `setState` به `ValueNotifier` و `ListenableBuilder` تغییر یافت. Rebuildهای غیرضروری رفع شدند.
- **Converter**: فایل `config_list_screen.dart` وجود نداشت. طبق Golden Rule تغییراتی اعمال نشد تا از تغییرات خارج از اسکوپ جلوگیری شود.
- **Gatekeeper**: تست‌های `integration_test/vpn_lifecycle_test.dart` برای پوشش فلو متصل شدن/قطع شدن (Connect/Disconnect) و تعاملات UI با موفقیت اضافه و Mock شدند.

## 🔴 پیشنهادات اصلی امشب (برای شیفت 2026-08-11)
تیم برای این شیفت به حوزه‌های زیر متمرکز می‌شود:
- **Hunter**: بررسی امنیت داده‌های Network در `lib/services/funnel_service.dart` و ارتباطات محلی.
- **Optimizer**: بهینه‌سازی پرفورمنس پردازش‌های پس‌زمینه در `lib/services/singbox_config_generator.dart`.
- **Converter**: اعمال و بهبود `ScaleOnTap` و انیمیشن‌ها در مسیر `lib/screens/settings_screen.dart`.
- **Gatekeeper**: نوشتن Unit Test برای پوشش کامل در `test/services/binary_manager_test.dart` که Coverage پایینی دارد.

## ⚠️ تضادها یا نیاز به بحث
- تمامی فعالیت‌های انجام شده در راستای Golden Rule بود و تضادی گزارش نشد. تیم بسیار عالی عمل کرد.

---

## ✋ منتظر تایید شما
**دستوری برای شب بعد:**
```
*** شیفت جدید (2026-08-11) با اهداف و Lockهای جدید آغاز شد. منتظر گزارش‌های جدید هستم.
```


## Global CI/CD Optimization Policy
To strictly optimize our GitHub Actions usage and conserve our free CI/CD minutes, the following rules apply:
1. **Commit-Level Control (Stateless):** By default, for all routine bug fixes, logging updates, documentation changes, and minor code iterations, agents MUST append `[skip ci]` to their commit messages or PR titles. GitHub will natively skip the workflow execution.
2. **On-Demand Execution:** Workflows should ONLY run when the Scrum Master (Mastermind) determines that an end-to-end test or build is strictly necessary (e.g., when merging a major feature, finalizing an architectural shift, or closing a critical bug before standby). In these cases, simply do not use the `[skip ci]` tag.
