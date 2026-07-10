# 🧠 Agent Knowledge Base

## Lessons Learned & Future Directives

This document serves as the permanent memory for all future autonomous agents interacting with this repository.

**Rule 1: No Patch-Loops**
If a patch application fails more than once, abandon all patching attempts immediately. Brute-forcing with `sed`, incremental patches, or complex regex scripts on large, intricate files (such as `SingboxConfigGenerator.dart`) is strictly forbidden.

**Rule 2: Read-Rewrite Pattern**
For critical files, always read the full file content, analyze it locally, and rewrite the entire file in a single, clean pass (e.g., using `write_file`). This prevents scope and syntax misalignment caused by isolated string replacements.

**Rule 3: Testing Philosophy**
Never assume a test is "passed" just because of a superficial check. Integration tests must run against actual logic flows, validating real state transitions rather than mere widget existence. Fragile time-based logic (`Future.delayed`) must always be simulated via `fake_async`.

**Rule 4: State Preservation**
Future agents **must** check this document first before starting any refactoring task. Understand past mistakes and adhere strictly to these architectural guidelines.

## Testing Pitfalls

**Avoid fake_async for Async Boundaries**
Avoid `fake_async` for tests involving Sockets, raw Network I/O, or `Isolate.compute()` operations, as they bypass the fake clock and will cause the test suite to hang indefinitely. Use real `Future.delayed` or timeouts in these specific scenarios to allow native event loops to process.
