# GLOBAL RULES & OPERATIONAL GUIDELINES

1. **Hierarchical Reading:** Agents MUST read this high-level summary file (`MASTER_PLAN.md`) FIRST for quick context. DO NOT read detailed logs or source code unless you need deep context for a specific assigned task. Detailed logs in `CHAT.md` and `scouts/*_log.md` must NEVER be shortened or deleted to prevent loss of technical context.
2. **Standby Trigger:** The Scrum Master (Mastermind) will only put the team on standby when TWO conditions are met:
   a) The overall project quality score (in `TRACK_RECORD.json`) reaches a high threshold (e.g., 90+/100).
   b) There are absolutely zero "blind spots" left in the codebase (all modules, edge cases, and known tasks have been thoroughly reviewed and resolved).

---
# 🌙 خلاصه شب 2026-08-08

## ✅ پیشنهادات تایید‌شده از شب قبل
- **بهبود پرفورمنس پردازش‌های پس‌زمینه (Optimizer)**: ایجاد فایل‌های موقت JSON در کدهای نیتیو اندروید (`SingboxVpnService.kt`) حذف شد و تنظیمات مستقیماً از طریق String به `Libbox` منتقل می‌شود. این کار هم پرفورمنس را افزایش داده (حذف I/O اضافه) و هم خطر امنیتی Information Disclosure را برطرف کرده است.
- **بهبود انیمیشن‌ها و جریان کاربر (Converter)**: دکمه‌های آیکونی و `ElevatedButton` ها با استفاده از `ScaleOnTap` بهینه‌سازی شدند تا بازخورد لمسی مناسب ارائه دهند. همچنین مشکلات دسترسی‌پذیری مربوط به تداخل ژست‌های لمسی نیز حل شد.

## 🔴 پیشنهادات اصلی امشب (منتظر تصمیم شما)
(موردی برای امشب وجود ندارد، تیم بر اساس قانون طلایی پیش رفته است)

## ⚠️ تضادها یا نیاز به بحث
- تضادی مشاهده نشد. تمامی تغییرات با موفقیت تست و کامیت شدند.

---

## ✋ منتظر تایید شما
**دستوری برای شب بعد:**
```
*** تخصیص‌های جدید انجام شده و آماده شروع برای شیفت بعدی.
```
