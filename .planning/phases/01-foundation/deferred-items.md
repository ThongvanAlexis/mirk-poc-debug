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

---

## AUTH-04 — auto-resume routing bug after iOS Settings round-trip (Plan 01-07 sideload UAT)

**Discovered:** Plan 01-07 LOG-05 sideload UAT on iPhone 17 Pro (2026-04-30).
**Status:** AUTH-04 software is implemented per Plan 01-06 spec (lifecycle
observer + recheck), but the cross-restart Settings → app return code path
fails to auto-navigate from `/denied` to `/map`. Marked complete-with-known-
limitation rather than blocking Phase 1 closure (POC scope, GPS revocation
during a GPS POC is artificial; user's pragmatic call).

### Symptom

UAT walk steps 12-14 of Plan 01-07's `<how-to-verify>`:

1. Cold-restart with permission revoked to "Never" in iOS Settings →
   app correctly lands on `/denied` with the rationale + Open-Settings button.
2. Tap CTA → iOS opens the app's Settings page (no in-app prompt because
   the perm is in a hard-deny state — expected).
3. Toggle Location to "While Using" in iOS Settings → tap Back to return
   to the POC.
4. **Expected:** lifecycle `resumed` event fires → `_recheckPermissionAndMaybePop`
   reads granted → auto-navigate to `/map` (zero extra taps).
5. **Actual:** the app stays on the `/denied` screen. No auto-nav. User
   has to cold-restart the app (which then correctly routes to `/map` via
   the gate screen's `initState` check).

### Diagnostic notes

- The lifecycle observer DOES fire — earlier UAT logs from the gate
  screen contain `didChangeAppLifecycleState=resumed: granted` records,
  so the `WidgetsBindingObserver.didChangeAppLifecycleState` callback
  is wired correctly on `PermissionGateScreen`.
- The likely root cause is on **`PermissionDeniedScreen`** specifically:
  when the app cold-restarts directly into `/denied` (because the gate's
  `initState` check sees `permanentlyDenied`/`denied` and routes there),
  the route stack becomes `[/denied]` only — there's no parent `/` route
  to pop back to.
- The denied screen's recheck pattern uses
  `if (context.canPop()) context.pop(true); else context.go('/');`
  per `docs/flutter-ios-specifics.md` §5.6. After the cold-restart edge
  case, `canPop()` returns `false` → fallback `context.go('/')` runs →
  the gate screen mounts → its `initState` re-reads the (now-granted)
  permission → SHOULD `context.go('/map')`. One of these steps drops the
  navigation, possibly because the gate screen's `initState` runs before
  the lifecycle `resumed` propagates fully, or because the recheck Future
  is racing against the `go('/')` route swap.

### Fix candidates (when revisited)

- Add a microtask delay (`await Future<void>.delayed(Duration.zero)`) before
  the `context.go('/')` fallback to let the lifecycle event settle.
- Read `Permission.locationWhenInUse.status` in `PermissionDeniedScreen`'s
  own resume handler and `context.go('/map')` directly (skip the `pop`/`/`
  bounce entirely on the cold-restart edge case).
- Wrap the navigation in a `WidgetsBinding.instance.addPostFrameCallback`
  to ensure the route swap happens after the current frame.

### Reference

Working pattern (parent project, where the cold-restart edge case is
also handled cleanly): `docs/flutter-ios-specifics.md` §5.6 — UI écran
denied + auto-resume hook.

### Why deferred

POC is for debugging Phase 1 specifics, not a production app. The
intended UAT flow is **grant on first launch** (which works perfectly
end-to-end). Revoking GPS perms while testing a POC that needs GPS
is artificial. Plan 01-07's primary success criteria (first-launch
grant → /map → share-logs → Mail round-trip) all PASS. Re-investigating
this bug is on hold until either (a) a downstream phase exercises the
cross-restart re-grant flow, or (b) a future debug session decides the
POC's polish budget can absorb it.
