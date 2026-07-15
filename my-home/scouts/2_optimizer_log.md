=== MISSION BRIEF: 2026-07-14 ===
ROLE_TONIGHT: Performance Fixer
ASSIGNED_BY: Mastermind
REASON: شب دوم - رفع گلوگاه‌های عملکردی و کندی UI

SCOPE:
- lib/services/funnel_service.dart
- lib/services/config_manager.dart

FROZEN_ZONES:
- none

SPECIFIC_TASK: رفع O(N*M) در استفاده از .skip().take() و بهینه‌سازی jsonDecode و جلوگیری از UI thread blocking.

CROSS_AUDIT_TARGET: نه
=== END BRIEF ===

--- تاریخچه گزارش‌ها ---

[شروع]

[2026-07-14] (Phase 2): Refactored `.skip().take()` O(N*M) bottlenecks into `sublist` replacements, and moved heavy JSON parsing inside `config_manager.dart` to a `compute()` isolate. Cleaned up workspace after execution and tests pass perfectly.
