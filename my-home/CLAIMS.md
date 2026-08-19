# GLOBAL RULES & OPERATIONAL GUIDELINES

1. **Hierarchical Reading:** Agents MUST read this high-level summary file (`MASTER_PLAN.md`) FIRST for quick context. DO NOT read detailed logs or source code unless you need deep context for a specific assigned task. Detailed logs in `CHAT.md` and `scouts/*_log.md` must NEVER be shortened or deleted to prevent loss of technical context.
2. **Standby Trigger:** The Scrum Master (Mastermind) will only put the team on standby when TWO conditions are met:
   a) The overall project quality score (in `TRACK_RECORD.json`) reaches a high threshold (e.g., 90+/100).
   b) There are absolutely zero "blind spots" left in the codebase (all modules, edge cases, and known tasks have been thoroughly reviewed and resolved).

---
# 🔒 وضعیت Lock فایل‌ها

| فایل | مالک شب | وضعیت | تا کی |
|------|---------|-------|-------|
| lib/services/config_manager.dart | Hunter | 🔒 Lock | تا صبح 2026-08-11 |
| lib/screens/connection_home_screen.dart | Optimizer | 🔒 Lock | تا صبح 2026-08-11 |
| lib/screens/config_list_screen.dart | Converter | 🔒 Lock | تا صبح 2026-08-11 |
| integration_test/ | Gatekeeper | 🔒 Lock | تا صبح 2026-08-11 |

(ترتیب: شب اول Hunter، بعد Optimizer، بعد Converter، بعد Gatekeeper)
