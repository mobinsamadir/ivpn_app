# GLOBAL RULES & OPERATIONAL GUIDELINES

1. **Hierarchical Reading:** Agents MUST read this high-level summary file (`MASTER_PLAN.md`) FIRST for quick context. DO NOT read detailed logs or source code unless you need deep context for a specific assigned task. Detailed logs in `CHAT.md` and `scouts/*_log.md` must NEVER be shortened or deleted to prevent loss of technical context.
2. **Standby Trigger:** The Scrum Master (Mastermind) will only put the team on standby when TWO conditions are met:
   a) The overall project quality score (in `TRACK_RECORD.json`) reaches a high threshold (e.g., 90+/100).
   b) There are absolutely zero "blind spots" left in the codebase (all modules, edge cases, and known tasks have been thoroughly reviewed and resolved).

---
# 🌙 خلاصه شب 2026-08-09

## ✅ دستاوردهای امشب (تایید شده توسط Mastermind)
- **Hunter**: فایل‌های `lib/utils/` ایمن‌سازی شده تشخیص داده شدند و نیازی به تغییرات غیرضروری نبود.
- **Optimizer**: مسدود شدن Thread توسط Rebuildهای نامرتبط حل شد و تایید شد که سیستم از نظر پردازش در Isolateها بهینه است.
- **Converter**: بهینه‌سازی رندرینگ در `AnimatedBuilder`ها در دیالوگ‌ها و صفحات اصلی انجام شد.
- **Gatekeeper**: پوشش تست کامل برای ویجت‌ها در `test/widgets/` پاس و تایید شد.

## 🔴 پیشنهادات اصلی امشب (برای شیفت 2026-08-10)
تیم برای این شیفت به حوزه‌های زیر متمرکز می‌شود:
- **Hunter**: بررسی امنیت داده‌های ذخیره شده در دیتابیس لوکال و فایل‌های تنظیمات `lib/services/config_manager.dart`
- **Optimizer**: بررسی لاجیکِ مسیردهی و مدیریت استیت در `lib/screens/connection_home_screen.dart`
- **Converter**: بررسی بهبود انیمیشن و وضعیت لودینگ لیست در `lib/screens/config_list_screen.dart`
- **Gatekeeper**: افزایش تست‌های integration برای کل پروسه کانکت شدن VPN در `integration_test/`

## ⚠️ تضادها یا نیاز به بحث
- تمامی فعالیت‌های انجام شده در راستای Golden Rule بود و تضادی گزارش نشد. تیم بسیار عالی عمل کرد.

---

## ✋ منتظر تایید شما
**دستوری برای شب بعد:**
```
*** شیفت جدید (2026-08-10) با اهداف و Lockهای جدید آغاز شد. منتظر گزارش‌های جدید هستم.
```
