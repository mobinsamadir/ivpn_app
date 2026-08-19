# GLOBAL RULES & OPERATIONAL GUIDELINES

1. **Hierarchical Reading:** Agents MUST read this high-level summary file (`MASTER_PLAN.md`) FIRST for quick context. DO NOT read detailed logs or source code unless you need deep context for a specific assigned task. Detailed logs in `CHAT.md` and `scouts/*_log.md` must NEVER be shortened or deleted to prevent loss of technical context.
2. **Standby Trigger:** The Scrum Master (Mastermind) will only put the team on standby when TWO conditions are met:
   a) The overall project quality score (in `TRACK_RECORD.json`) reaches a high threshold (e.g., 90+/100).
   b) There are absolutely zero "blind spots" left in the codebase (all modules, edge cases, and known tasks have been thoroughly reviewed and resolved).

---
# 🔒 وضعیت Lock فایل‌ها

| فایل | مالک شب | وضعیت | تا کی |
|------|---------|-------|-------|
| lib/models/ | Hunter | 🔒 Lock | تا صبح 2026-08-09 |
| lib/services/ | Optimizer | 🔒 Lock | تا صبح 2026-08-09 |
| lib/widgets/ | Converter | 🔒 Lock | تا صبح 2026-08-09 |
| test/widgets/ | Gatekeeper | 🔒 Lock | تا صبح 2026-08-09 |

(ترتیب: شب اول Hunter، بعد Optimizer، بعد Converter، بعد Gatekeeper)
