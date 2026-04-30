# Deferred items — Phase 01 Foundation

Items discovered during Plan 01-01 execution that are out of scope for this plan
but should be addressed before Phase 1 closes (Plan 01-07 / verifier pass).

## flutter analyze info-level issues (post-Plan-01-01 wave-completion)

After Plan 01-01 lands the pubspec, `flutter analyze lib/ test/` reports 3
info-level issues. None are errors; CI runs with `--fatal-infos` so they
will eventually need fixing before Plan 07's first push goes green.

### 1. lib/infrastructure/logging/file_logger_lifecycle_observer.dart:7

```
info - The import of 'package:flutter/foundation.dart' is unnecessary because
       all of the used elements are also provided by the import of
       'package:flutter/widgets.dart' - unnecessary_import
```

**Owner:** Plan 01-04 (FileLogger + lifecycle observer port).
**Fix:** delete the `import 'package:flutter/foundation.dart' show ...` line —
all referenced symbols (`@visibleForTesting`, `WidgetsBindingObserver`,
`AppLifecycleState`) come transitively via `flutter/widgets.dart` which is
already imported.

### 2. test/infrastructure/logging/file_logger_test.dart:12

```
info - The imported package 'path_provider_platform_interface' isn't a
       dependency of the importing package - depend_on_referenced_packages
```

**Owner:** Plan 01-04.
**Fix options:**
- (a) Add `path_provider_platform_interface: <pin>` to dev_dependencies in
  pubspec.yaml. This is the test-mode swap mechanism per Plan 01-04 design.
- (b) Add `// ignore_for_file: depend_on_referenced_packages` at the top of
  the test file — `path_provider_platform_interface` is a transitive dep of
  `path_provider` itself, so the import resolves at runtime; the lint just
  flags the missing direct declaration.

Plan 01-04 SUMMARY documents the use of `PathProviderPlatform.instance`
swap as a test seam; option (a) makes that dependency explicit.

### 3. test/infrastructure/logging/file_logger_test.dart:13

```
info - The imported package 'plugin_platform_interface' isn't a dependency
       of the importing package - depend_on_referenced_packages
```

**Owner:** Plan 01-04. Same as item #2 — `plugin_platform_interface` is
transitive via `path_provider_platform_interface`. Same two fix options.

---

## Synthetic-package l10n flag removed in Flutter 3.41+

`l10n.yaml` originally specified `synthetic-package: true` per the plan, but
Flutter 3.41 rejects this flag (`Cannot enable "synthetic-package", this
feature has been removed`). The flag was dropped during Plan 01-01 Task 2
execution, and `flutter gen-l10n` now writes generated files into
`lib/l10n/` (gitignored) instead of `.dart_tool/flutter_gen/`.

**Future-import-path adjustment for Plans 01-05 and 01-07:** the import
statement
`import 'package:flutter_gen/gen_l10n/app_localizations.dart';`
must instead be
`import 'package:mirk_poc_debug/l10n/app_localizations.dart';`
(file ends up under the project's own lib/ tree rather than under the
synthetic flutter_gen package).

---

## Test execution defer-state at end of Plan 01-01

Plan 01-04's ~14 logging tests, Plan 01-02's tool tests, and Plan 01-03's
donor file tree are all expected to pass now that Plan 01-01's pubspec.yaml
+ pubspec.lock + lib/config/constants.dart are committed. Verifier should
run:

```bash
cd C:/claude_checkouts/mirk-poc-debug
flutter pub get
flutter test test/assets/asset_bundle_test.dart    # 5 tests (Plan 01-01) — confirmed green during plan execution
flutter test test/infrastructure/logging/           # ~14 tests (Plan 01-04) — runnable post-Wave-1
flutter test test/tooling/info_plist_keys_test.dart # 4 tests (Plan 01-02)
dart test tool/test/                                # 17 tests (Plan 01-02)
flutter analyze --fatal-infos --fatal-warnings      # expected red until items 1-3 above are addressed
```

`lib/main.dart` from `flutter create` remains in place — Plan 07 replaces it
with the proper bootstrap and GOSL header. Until then, `tool/check_headers`
will flag it as expected (per Plan 01-02 + Plan 01-03 SUMMARY notes).
