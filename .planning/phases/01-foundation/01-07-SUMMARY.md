---
phase: 01-foundation
plan: 07
subsystem: integration
tags: [bootstrap, go-router, main, runZonedGuarded, file-logger-bootstrap, ci, sideload, sidestore, log-05, perf-01, audit-03, auth-04, gosl-license, phase-exit-uat]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: FileLogger.bootstrap() + FileLoggerLifecycleObserver (Plan 01-04 — must be awaited before runApp)
  - phase: 01-foundation
    provides: buildPocAppBar(BuildContext, {String? title}) factory + FpsCounterOverlay zero-config widget (Plan 01-05 — LOG-04 + PERF-01 visible everywhere)
  - phase: 01-foundation
    provides: PermissionGateScreen (route '/') + PermissionDeniedScreen (route '/denied') (Plan 01-06 — AUTH-01..04)
  - phase: 01-foundation
    provides: GoRouter 16.0.0 + flutter_gen-l10n strings + GOSL CI gates + Info.plist + PrivacyInfo.xcprivacy (Plans 01-01, 01-02, 01-03)
provides:
  - "lib/main.dart — bootstrap entry: WidgetsFlutterBinding.ensureInitialized() → await FileLogger.bootstrap() → WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver()) → FlutterError.onError = ... → runZonedGuarded(runApp(MirkPocApp), ...) (LOG-03 ordering verified by source review)"
  - "lib/app.dart — MirkPocApp: MaterialApp.router with GoRouter from lib/presentation/router.dart, l10n delegates from package:mirk_poc_debug/l10n/app_localizations.dart, Material 3 indigo seed theme, French fallback in localeResolutionCallback"
  - "lib/presentation/router.dart — appRouter: GoRouter with three routes (/=PermissionGateScreen, /map=MapScreen, /denied=PermissionDeniedScreen) — every transition via context.go (no context.push per CONTEXT.md decision)"
  - "lib/presentation/screens/map_screen.dart — Phase 1 placeholder MapScreen: Scaffold(appBar: buildPocAppBar, body: Stack([ColoredBox(Colors.grey[850]), Positioned(top:8, right:8, FpsCounterOverlay)])). Phase 2 swaps ONLY the body Stack's first child for FlutterMap; AppBar + overlay stay byte-for-byte identical."
  - "ios/Podfile — committed with PERMISSION_LOCATION=1 macro per docs/flutter-ios-specifics.md §1; without it, permission_handler silently denies on iOS sideload builds."
  - "docs/flutter-ios-specifics.md — recurring iOS Flutter recipes captured during this plan's sideload UAT cycle: §1 Podfile macros, §2 CFBundleName SideStore quirk, §3 FileLogger anatomy with parent quirks, §4 misc gotchas, §5 location 2-step pattern (auth/UI). Future Flutter projects on Windows-with-iOS-sideload start from this checklist."
  - "ios/Runner/Info.plist (modified) — CFBundleName changed mirk_poc_debug → MirkPocDebug per docs/flutter-ios-specifics.md §2 (Apple appIdName API rejects underscores; SideStore re-sign fails otherwise)"
affects: [02-map]  # Phase 2 swaps MapScreen body; the rest of Phase 1's wiring (main, router, app) stays untouched

# Tech tracking
tech-stack:
  added: []  # All deps already declared and pinned by Plan 01-01
  patterns:
    - "main.dart bootstrap ordering for LOG-03: WidgetsFlutterBinding.ensureInitialized() → await FileLogger.bootstrap() → WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver()) → FlutterError.onError = (...){Logger('flutter.error').shout(...)} → runZonedGuarded(() => runApp(MirkPocApp), (err, st) => Logger('zone.error').shout(...)). The ordering matters: bootstrap MUST await BEFORE the observer registers (otherwise the observer fires didChangeAppLifecycleState before activeFilename is set), and the observer MUST register BEFORE runApp (otherwise the first paused/resumed event after launch is lost). FlutterError.onError + runZonedGuarded together cover the two top-level error channels per CLAUDE.md."
    - "GoRouter three-route pattern, all context.go: GoRouter(initialLocation: '/', routes: [GoRoute(/, PermissionGateScreen), GoRoute(/map, MapScreen), GoRoute(/denied, PermissionDeniedScreen)]). No context.push in Phase 1 — every transition fully replaces the route stack per CONTEXT.md decision (no back-button confusion in a 3-screen POC). Phase 2+ may revisit if pushable sub-screens emerge."
    - "Phase 1 placeholder /map screen contract for Phase 2 hand-off: MapScreen is Scaffold(appBar: buildPocAppBar(context), body: Stack([<placeholder ColoredBox>, Positioned(top:8, right:8, FpsCounterOverlay)])). Phase 2's diff is exactly: replace the ColoredBox child of the Stack with FlutterMap(...). The AppBar + FpsCounterOverlay stay literally identical. This minimises Phase 1 → Phase 2 scope creep risk."
    - "iOS sideload-time fixes that flutter create does NOT apply by default — captured in docs/flutter-ios-specifics.md so the next Flutter iOS project starts from a known-good checklist: (1) ios/Podfile must enable per-permission compile-flag macros (PERMISSION_LOCATION=1 etc.); (2) CFBundleName must contain no underscore (SideStore Apple-ID API rejects); (3) gen-l10n codegen must be re-formatted in CI before dart format check (flutter gen-l10n outputs files that don't match the project's --line-length 160 config); (4) location 2-step rationale + request pattern per §5.6."
    - "Phase 1 UAT exit gate process: developer pushes to main → CI gates+android+ios all green → gh run download IPA → SideStore sideload onto iPhone 17 Pro → walk the 16-step <how-to-verify> on physical hardware → verbal 'approved' (vs. failure report routed to /gsd:plan-phase --gaps). Verbal 'approved' replaces the dropped 50 MB synthetic-log smoke test per CONTEXT.md `Phase 1 UAT exit gate` decision and per REQUIREMENTS.md LOG-05 wording revision (2026-04-30)."

key-files:
  created:
    - "lib/main.dart — bootstrap entry (replaces flutter create boilerplate)"
    - "lib/app.dart — MirkPocApp MaterialApp.router with l10n + theme"
    - "lib/presentation/router.dart — appRouter GoRouter with three routes"
    - "lib/presentation/screens/map_screen.dart — Phase 1 placeholder MapScreen"
    - "ios/Podfile — committed with PERMISSION_LOCATION=1 macro (Pods.xcconfig pre-existed; the Podfile itself was previously gitignored by flutter create's default .gitignore)"
    - "docs/flutter-ios-specifics.md — 744-line recurring-recipes doc (committed in commits b37ee41 + 918a221 + 72d5219 during the UAT cycle)"
  modified:
    - "ios/Runner/Info.plist — CFBundleName mirk_poc_debug → MirkPocDebug (commit b9c092d)"
    - ".github/workflows/ci.yml — pre-format gen-l10n step added before dart format gate (commit 842a9da)"
    - ".planning/phases/01-foundation/deferred-items.md — Plan 01-04 analyze-info items resolved + AUTH-04 routing-bug entry appended"
    - "tool/check_dependencies_md.dart, tool/check_headers.dart — fix gates against POC's actual dep graph (commit 0c4fb08)"
    - "test/infrastructure/logging/file_logger_test.dart — Windows-portable prune assertion (commit 009ff60)"

key-decisions:
  - "Sideload-time CFBundleName rename mirk_poc_debug → MirkPocDebug (commit b9c092d). The Apple appIdName API used internally by SideStore's re-sign step rejects bundle names containing underscores. flutter create defaulted to the snake_case package name; the rename is a one-line Info.plist fix. CFBundleDisplayName remains free-form ('MirkFall POC'). Documented in docs/flutter-ios-specifics.md §2 so this never re-bites."
  - "ios/Podfile committed to the repo with PERMISSION_LOCATION=1 compile-flag macro (commit 9d7bbe7). Without it, permission_handler 12.0.1 ships its iOS plugin code stubbed-out (the real Permission.locationWhenInUse.request implementation sits behind the macro — opt-in to keep app-store binaries lean for apps that don't use that permission). flutter create gitignores Podfile.lock but DOES leave Podfile in the tree; on this project the Podfile had been gitignored at some point and we re-committed it with the right macros block. Documented in docs/flutter-ios-specifics.md §1."
  - "Pre-format gen-l10n step in CI (commit 842a9da). flutter gen-l10n's codegen does not respect the project's analysis_options.yaml --line-length 160 config — it emits 80-col-wrapped lines. The dart format --set-exit-if-changed gate then went red on every push. Fix: insert a `dart format --line-length 160 lib/l10n/` step in CI right after `flutter gen-l10n` and before the format-check gate. Documented in docs/flutter-ios-specifics.md §4.1."
  - "AUTH-04 round-trip routing bug deferred (not blocking POC). Cold-restart with permission revoked to 'Never' → /denied → tap CTA → iOS Settings → toggle Location to 'While Using' → tap Back. EXPECTED: auto-nav to /map. ACTUAL: stays on /denied. The lifecycle observer fires correctly (gate-screen logs confirm), so the bug is in the /denied → /map route-swap path on the cold-restart-direct-to-/denied edge case. Per user's pragmatic call: this is a POC for debugging Phase 1 specifics, not a production app; revoking GPS perms during a GPS-needed POC is artificial. Marked complete-with-known-limitation. Full diagnostic + 3 fix candidates captured in deferred-items.md; reference pattern in docs/flutter-ios-specifics.md §5.6."
  - "LOG-05 verbal 'approved' replaces the prior 50 MB synthetic-log smoke test (per CONTEXT.md Phase 1 UAT exit gate decision and REQUIREMENTS.md 2026-04-30 wording revision). User received the gzipped log via Mail with valid JSONL content (bootstrap + lifecycle + CTA + result records); LOG-05 PASSES. STATE.md Blockers/Concerns line referencing the 50 MB synthetic-log requirement is now stale and removed in this plan's STATE update."
  - "PERF-01 visual gate confirmed via FPS counter visible top-right showing `<value> fps / 120 Hz` (the `120 Hz` confirms ProMotion is detected correctly per Pitfall E). Idle-screen low FPS values are normal — Flutter's render-on-change behaviour means the FPS counter only ticks up when the app is actively repainting. PERF-01 PASSES."
  - "AUDIT-03 confirmed via DEPENDENCIES.md visual review: zero rows say 'Yes/automatic' in the telemetry column. Every package row says 'None' or '<user-initiated reason>'. AUDIT-03 PASSES."

patterns-established:
  - "Bootstrap-LOG-03 ordering canonical layout (lib/main.dart): every Future<void> main() in this project starts with WidgetsFlutterBinding.ensureInitialized() → await FileLogger.bootstrap() → WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver()) → FlutterError.onError set → runZonedGuarded(() => runApp(...), (err, st) => Logger('zone.error').shout(...)). Future plans that need extra pre-runApp setup (e.g. Phase 2's PMTiles file copy) splice between the observer registration and the runZonedGuarded wrap, never before bootstrap."
  - "Three-screen, single-Scaffold-pattern Phase 1 carried through to wiring: every screen consumes appBar: buildPocAppBar(context) and body: Stack([<screen body>, const Positioned(top: 8, right: 8, child: FpsCounterOverlay())]). MapScreen completes the trio (with PermissionGateScreen + PermissionDeniedScreen from Plan 01-06). LOG-04 + PERF-01 visibility is structurally enforced — three screens × the same Scaffold factory."
  - "Phase 1 → Phase 2 hand-off contract for /map: the MapScreen's Scaffold body is `Stack([<placeholder>, Positioned(top:8, right:8, FpsCounterOverlay)])`. Phase 2's first task replaces the `<placeholder>` (currently `ColoredBox(color: Colors.grey[850])`) with `FlutterMap(...)`. The Stack + Positioned(FpsCounterOverlay) stay untouched. This makes the Phase 1 → Phase 2 diff trivially small and keeps PERF-01 working through the transition."
  - "Sideload UAT walk pattern: verbal 'approved' over 16 numbered <how-to-verify> steps (cold launch → permission rationale → CTA → iOS prompt → grant → /map → FPS counter on ProMotion → share IconButton → Mail target → send → inbox arrival → attachment open → JSONL parse → AUTH-04 round-trip subset → screenshot → DEPENDENCIES.md doc-review). Every Phase that needs an in-person walk follows this pattern; failures route through /gsd:plan-phase {phase} --gaps."

requirements-completed: [LOG-03]

# Metrics
duration: ~4h (Task 1 wiring + 8 deviations + sideload preparation + 16-step manual UAT walk + UAT-cycle docs)
completed: 2026-05-01
---

# Phase 1 Plan 07: Main Wiring + Sideload UAT Exit Gate Summary

**End-to-end Phase 1 deliverable shipped: `lib/main.dart` boots through `await FileLogger.bootstrap()` → registers `FileLoggerLifecycleObserver` → `runZonedGuarded(runApp(MirkPocApp))`; GoRouter routes the three Phase 1 screens; sideloaded IPA on iPhone 17 Pro walks first-launch grant → `/map` placeholder with `<value> fps / 120 Hz` ProMotion-aware counter → share IconButton → Mail → gzipped JSONL log arrives in inbox. LOG-05 + PERF-01 + AUDIT-03 all PASS verbal `approved`; AUTH-04 round-trip marked complete-with-known-limitation (cold-restart-from-/denied auto-nav routing bug, deferred per user's pragmatic POC-scope call).**

## Performance

- **Duration:** ~4h end-to-end (Task 1 wiring ~2h with 6 deviations + sideload preparation ~30 min including the 2 sideload-time fixes + 16-step manual UAT walk on iPhone 17 Pro ~30 min + UAT-cycle documentation in docs/flutter-ios-specifics.md ~1h).
- **Started:** 2026-04-30T17:01:50Z (immediately after Plan 01-06 SUMMARY commit).
- **Completed:** 2026-05-01T05:25:43Z (verbal `approved` from developer's UAT walk + this SUMMARY).
- **Tasks:** 2 (Task 1 = auto wiring; Task 2 = checkpoint:human-verify sideload UAT).
- **Files created:** 4 lib files (main, app, router, map_screen) + ios/Podfile + docs/flutter-ios-specifics.md.
- **Files modified:** ios/Runner/Info.plist + .github/workflows/ci.yml + tool/check_*.dart + test/infrastructure/logging/file_logger_test.dart + .planning/phases/01-foundation/deferred-items.md.

## Accomplishments

- **`lib/main.dart` lands the LOG-03-compliant bootstrap entry.** Source-verified ordering:
  ```dart
  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await FileLogger.bootstrap();
    WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver());

    FlutterError.onError = (FlutterErrorDetails details) {
      Logger('flutter.error').shout('FlutterError', details.exception, details.stack);
    };

    runZonedGuarded<void>(
      () => runApp(const MirkPocApp()),
      (Object error, StackTrace stack) {
        Logger('zone.error').shout('Uncaught zone error', error, stack);
      },
    );
  }
  ```
  `await FileLogger.bootstrap()` runs BEFORE `WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver())` (otherwise the observer's first `didChangeAppLifecycleState` call would fire before `activeFilename` is set), and the observer registers BEFORE `runApp` (otherwise the first lifecycle event after launch is lost). LOG-03 PASSES — verified by source review of `lib/main.dart` lines 14-29.

- **`lib/app.dart` lands `MirkPocApp` as a `MaterialApp.router`** wired to `appRouter`, with `AppLocalizations.localizationsDelegates` + `AppLocalizations.supportedLocales` from `package:mirk_poc_debug/l10n/app_localizations.dart`, a `localeResolutionCallback` that follows the device's language with French fallback (developer walks in Melun), Material 3 indigo seed colour, debug banner off.

- **`lib/presentation/router.dart` lands `appRouter` with exactly three routes**, all using `context.go` for transitions per CONTEXT.md:
  - `GoRoute('/', PermissionGateScreen)` — Plan 01-06's gate
  - `GoRoute('/map', MapScreen)` — Plan 01-07's placeholder (this plan)
  - `GoRoute('/denied', PermissionDeniedScreen)` — Plan 01-06's denied screen

- **`lib/presentation/screens/map_screen.dart` lands the Phase 1 `MapScreen` placeholder.** Scaffold(appBar: buildPocAppBar(context), body: Stack([ColoredBox(Colors.grey[850]), Positioned(top:8, right:8, FpsCounterOverlay)])). Phase 2's diff is exactly: replace the ColoredBox with FlutterMap(...). The AppBar + FpsCounterOverlay stay byte-for-byte identical. PERF-01 + LOG-04 visibility carried through to the `/map` screen.

- **CI is GREEN on `main`.** All three jobs (`gates`, `android`, `ios`) succeed on the latest run; both APK + IPA artifacts downloadable via `gh run download`. The first push hit 6 deviations along the way (l10n import path correction, deferred-items analyze gate fixes, Windows file_logger_test portability, CI gate scripts against POC's actual dep graph, CI pre-format step for gen-l10n, remote main bootstrap merge) — all resolved before the green run.

- **iPhone 17 Pro sideload UAT walk PASSED — verbal `approved` (with one deferred item).** Developer:
  - Cold-launched the sideloaded IPA → permission rationale renders within ~2s with French text (per device language) + share IconButton + FPS counter top-right showing `<value> fps / 120 Hz` (ProMotion detected ✓).
  - Tapped CTA → iOS system permission prompt fires correctly (post-fix: PERMISSION_LOCATION=1 macro now compiled in).
  - Tapped "Allow While Using App" → app immediately navigates to `/map` placeholder. AUTH-03 + LOG-04 + PERF-01 visible on /map.
  - Tapped share IconButton → iOS share sheet → Mail → composed to self → sent.
  - Switched to Mail's inbox → email arrived with `.txt.gz` attachment within ~30s.
  - Opened the attachment → gunzipped → JSONL with bootstrap record at `/var/mobile/Containers/Data/Application/A589E7C5-9CEF-4402-BF93-957C36D170F3/Documents/logs/20260501T050725Z_logs.txt`, UTC ISO-8601 basic filename format confirmed, microsecond precision on `ts`, complete pipeline (initState → didChangeAppLifecycleState=resumed → CTA pressed → result). LOG-05 PASSES.
  - DEPENDENCIES.md visual review confirms zero `Yes/automatic` rows in the Telemetry column. AUDIT-03 PASSES.

- **AUTH-04 round-trip — marked complete-with-known-limitation, deferred (not blocking POC closure).** Cold-restart with location permission revoked to "Never" correctly shows /denied. Tap "Open Settings" → iOS opens app's Settings page. Toggle Location to "While Using" → tap Back. EXPECTED: auto-nav to /map. ACTUAL: stays on /denied; user has to cold-restart the app (which then routes correctly via the gate's initState check). Lifecycle observer fires (logs confirm), but the route swap from /denied → /map on the cold-restart-direct-to-/denied edge case fails. Full diagnostic + 3 fix candidates documented in `deferred-items.md` (this plan's update); reference pattern in `docs/flutter-ios-specifics.md` §5.6. Per user's pragmatic call: this is a POC for debugging Phase 1 specifics, not a production app — re-investigation deferred to a future debug session or never (depending on whether downstream phases exercise this code path).

- **`docs/flutter-ios-specifics.md` (744 lines) committed during the UAT cycle.** Captures the recurring Flutter-iOS recipes that `flutter create` does NOT apply by default — discovered through pain on this POC + the parent project (GOSL-MirkFall, 2026-04-19): §1 Podfile per-permission compile-flag macros, §2 CFBundleName SideStore-quirk (no underscores), §3 FileLogger anatomy with all parent quirks (RandomAccessFile + flushSync, JSONL records, sync `_onRecord` handler, prune-at-bootstrap, lifecycle flush, share_plus 12.x usage), §4 misc gotchas (gen-l10n × dart format, CFBundleName vs CFBundleDisplayName, Required-Reason API codes, SideStore App ID quota), §5 location 2-step rationale + request pattern with the auto-resume hook code (the canonical pattern that AUTH-04's bug should match). Every future Flutter-iOS-on-Windows-with-SideStore project starts from this checklist.

## Task Commits

This plan accumulated 8 task-level commits across the wiring + sideload-prep cycle, plus 3 docs commits during the UAT cycle:

**Task 1 — wiring + 6 deviations during the first push:**

1. **Task 1 main commit — `feat(01-07): wire main + GoRouter + MirkPocApp + MapScreen placeholder (BOOT-04..07 + LOG-03)`** — `42e3228`
2. **Deviation Rule 3 (Blocking) — `fix(01-07): clear deferred-items.md analyze gates + Windows-portable prune test`** — `009ff60`
3. **Deviation Rule 3 (Blocking) — `fix(01-07): make CI gate scripts pass against POC's actual dep graph`** — `0c4fb08`
4. **Deviation Rule 3 (Blocking) — `chore(01-07): apply dart format --line-length 160 across format-drifted files`** — `3fe38fe`
5. **Bootstrap merge — `merge: incorporate origin/main initial commit (one-time bootstrap merge for first push)`** — `e9e5af2`
6. **Deviation Rule 3 (Blocking) — `fix(01-07): pre-format gen-l10n codegen in CI to keep dart format check green`** — `842a9da`

**Sideload-time fixes after CI was green but before sideload UAT could proceed:**

7. **Deviation Rule 3 (Blocking) — `fix(01-07): rename CFBundleName mirk_poc_debug → MirkPocDebug for SideStore`** — `b9c092d` (SideStore re-sign uses Apple's appIdName API which rejects underscores; without this fix, sideload installs but iOS prompts on launch failed silently).
8. **Deviation Rule 1 (Bug) — `fix(01-07): commit ios/Podfile with PERMISSION_LOCATION=1 macro for permission_handler`** — `9d7bbe7` (without it, permission_handler's iOS plugin compiles its `request()` calls as no-ops; the system prompt never fires; the app stays on rationale screen forever).

**docs/flutter-ios-specifics.md commits during the UAT cycle:**

9. **`docs: add docs/flutter-ios-specifics.md — recurring iOS Flutter recipes`** — `b37ee41` (initial draft: §1-§4)
10. **`docs(ios-specifics): expand FileLogger §3 with parent-project quirks`** — `918a221` (§3 expansion)
11. **`docs(ios-specifics): add §5 — permission location 2-étapes (background tracking)`** — `72d5219` (§5 added; this is the section AUTH-04's deferred-items entry references)

**Plan metadata commit:** TBD (committed at end of this run with this SUMMARY + STATE.md + ROADMAP.md + REQUIREMENTS.md + deferred-items.md).

## Files Created/Modified

**Created (Task 1 — the four wiring files):**
- `lib/main.dart` — bootstrap entry per LOG-03 ordering (replaces flutter create boilerplate).
- `lib/app.dart` — MirkPocApp MaterialApp.router with l10n delegates + theme.
- `lib/presentation/router.dart` — appRouter GoRouter with three routes.
- `lib/presentation/screens/map_screen.dart` — Phase 1 placeholder MapScreen.

**Created (sideload-prep + UAT-cycle):**
- `ios/Podfile` — committed with PERMISSION_LOCATION=1 macro (commit 9d7bbe7).
- `docs/flutter-ios-specifics.md` — 744-line recurring-recipes doc (commits b37ee41 + 918a221 + 72d5219).

**Modified:**
- `ios/Runner/Info.plist` — CFBundleName mirk_poc_debug → MirkPocDebug (commit b9c092d).
- `.github/workflows/ci.yml` — pre-format gen-l10n step (commit 842a9da).
- `tool/check_dependencies_md.dart`, `tool/check_headers.dart` — fix gates against POC's actual dep graph (commit 0c4fb08).
- `test/infrastructure/logging/file_logger_test.dart` — Windows-portable prune assertion (commit 009ff60).
- `.planning/phases/01-foundation/deferred-items.md` — Plan 01-04 analyze items resolved (during commit 009ff60) + AUTH-04 routing-bug entry appended (during this SUMMARY commit).

## Decisions Made

See frontmatter `key-decisions` for the full list. Highlights:

1. **CFBundleName rename mirk_poc_debug → MirkPocDebug** for SideStore Apple-ID API compatibility (commit b9c092d). Captured in docs/flutter-ios-specifics.md §2.
2. **ios/Podfile committed with PERMISSION_LOCATION=1** to enable permission_handler's iOS implementation (commit 9d7bbe7). Captured in §1.
3. **Pre-format gen-l10n step added to CI** before the dart format check (commit 842a9da). Captured in §4.1.
4. **AUTH-04 routing bug deferred** rather than blocking Phase 1 closure — user's pragmatic POC-scope call.
5. **LOG-05 verbal `approved` is THE gate** (no synthetic-log smoke test); Phase 1 closes on this signal.
6. **STATE.md Blockers/Concerns line referencing the 50 MB synthetic-log requirement is now stale** and removed in this plan's STATE update (per the plan's `<output>` instruction to the orchestrator).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Resolved Plan 01-04 analyze info-level issues + Windows-portable prune test**

- **Found during:** Task 1 — `flutter analyze --fatal-infos --fatal-warnings` failed on the 3 pre-existing items flagged in `deferred-items.md` (unnecessary import in lib/infrastructure/logging/file_logger_lifecycle_observer.dart; `depend_on_referenced_packages` for path_provider_platform_interface and plugin_platform_interface in test/infrastructure/logging/file_logger_test.dart). The strict-analyze gate had to go green before this plan's CI push could be allowed.
- **Fix:** Removed the unnecessary `import 'package:flutter/foundation.dart' show ...` line from the lifecycle observer (all referenced symbols come transitively via `flutter/widgets.dart`). For the two `depend_on_referenced_packages` items, added `// ignore_for_file: depend_on_referenced_packages` at the top of `file_logger_test.dart` (Plan 01-04 deferred-items option (b), matching Plan 01-06's same pattern). Also fixed a Windows-portable assertion in the prune test (sharing-violation when unlinking an open file on Windows; assertion swapped to a Windows-friendly form).
- **Files modified:** `lib/infrastructure/logging/file_logger_lifecycle_observer.dart`, `test/infrastructure/logging/file_logger_test.dart`, `.planning/phases/01-foundation/deferred-items.md` (analyze items struck through).
- **Verification:** `flutter analyze --fatal-infos --fatal-warnings` exits 0 across the full repo. `flutter test` exits 0 on Windows.
- **Committed in:** `009ff60`.

**2. [Rule 3 - Blocking] CI gate scripts assumed parent project's dep graph**

- **Found during:** Task 1 — `dart run tool/check_dependencies_md.dart` failed because the script's allowlist was the parent project's, not this POC's reduced subset. `dart run tool/check_headers.dart` flagged a couple of false positives.
- **Fix:** Updated `tool/check_dependencies_md.dart` to recognise this POC's dep graph (the subset of parent + `test: 1.30.0`). Added small fix to `tool/check_headers.dart` for codegen file exclusions.
- **Files modified:** `tool/check_dependencies_md.dart`, `tool/check_headers.dart`.
- **Verification:** Both scripts exit 0 against the current `pubspec.yaml` + `pubspec.lock`. CI's `gates` job goes green on first run after this fix.
- **Committed in:** `0c4fb08`.

**3. [Rule 3 - Blocking] dart format drift across format-drifted files**

- **Found during:** Task 1 — `dart format --line-length 160 --set-exit-if-changed .` failed on a handful of files where format had drifted from the project's --line-length 160 config (mostly because earlier plans wrote at narrower widths or the format pass wasn't applied uniformly).
- **Fix:** Ran `dart format --line-length 160 .` and committed the diff as a chore commit. No semantic changes.
- **Files modified:** ~10 lib/ + test/ files (purely format).
- **Verification:** `dart format --line-length 160 --set-exit-if-changed .` exits 0.
- **Committed in:** `3fe38fe`.

**4. [Rule 3 - Blocking] Bootstrap merge with remote main on first push**

- **Found during:** Task 1 — `git push origin main` rejected because remote `main` had a one-commit initial bootstrap (gh repo create makes an initial commit). Local `main` had the entire Plan 01-01 → 01-07 history without that commit as ancestor.
- **Fix:** `git pull --no-rebase origin main` to merge the remote bootstrap commit into local. Recorded as a merge commit so the history is preserved (vs. force-pushing over the remote bootstrap, which would erase any record of it).
- **Files modified:** None (merge commit only).
- **Verification:** `git push origin main` succeeds; CI runs against the merged history.
- **Committed in:** `e9e5af2`.

**5. [Rule 3 - Blocking] gen-l10n codegen breaks dart format CI gate**

- **Found during:** Task 1 — first CI run on the gates job failed at the `dart format --set-exit-if-changed` step. Root cause: `flutter gen-l10n` re-emits `lib/l10n/app_localizations*.dart` in CI (because they're gitignored locally per Plan 01-01 deferred-items #2), and the codegen output uses Dart's default 80-col format, not the project's 160-col config. The format gate then fails.
- **Fix:** Inserted `dart format --line-length 160 lib/l10n/` step in `.github/workflows/ci.yml` between the `flutter gen-l10n` step and the `dart format --set-exit-if-changed` step. The codegen output is re-formatted in place to match the project's line-length config before the format check runs.
- **Files modified:** `.github/workflows/ci.yml`.
- **Verification:** CI's gates job exits 0 after this fix. Documented in docs/flutter-ios-specifics.md §4.1 so future projects don't re-discover this.
- **Committed in:** `842a9da`.

**6. [Rule 1 - Bug] AppLocalizations import path was `package:flutter_gen/...` per the plan**

- **Found during:** Task 1 — `lib/app.dart` initial draft used `import 'package:flutter_gen/gen_l10n/app_localizations.dart';` per the plan's literal task spec. Plan 01-01 deferred-items #2 had pre-flagged this: Flutter 3.41 dropped the `synthetic-package` flag, so generated AppLocalizations now ships under `lib/l10n/`, not `flutter_gen/`.
- **Fix:** Switched to `import 'package:mirk_poc_debug/l10n/app_localizations.dart';` (matching Plan 01-05 and Plan 01-06 which had already adopted the corrected path).
- **Files modified:** `lib/app.dart`.
- **Verification:** Flutter analyzer resolves the import; `flutter test` and `flutter run` succeed.
- **Committed in:** `42e3228` (rolled into the main wiring commit since the fix was applied during the initial write rather than after a build failure).

### Sideload-time fixes (between Task 1 CI green and Task 2 UAT walk)

**7. [Rule 1 - Bug] CFBundleName mirk_poc_debug → MirkPocDebug for SideStore re-sign**

- **Found during:** Sideload preparation — IPA downloaded from CI installs cleanly via SideStore, but on launch the app immediately crashed (or, in some attempts, SideStore's re-sign step itself failed). Diagnosis: SideStore uses Apple's appIdName API for the free-Apple-ID re-sign flow, and that API rejects bundle names containing underscores.
- **Fix:** Updated `ios/Runner/Info.plist`: `<key>CFBundleName</key><string>MirkPocDebug</string>` (was `mirk_poc_debug`). `CFBundleDisplayName` stays free-form (`MirkFall POC`).
- **Files modified:** `ios/Runner/Info.plist`.
- **Verification:** Re-built IPA in CI, re-downloaded, re-sideloaded — installs and launches successfully.
- **Committed in:** `b9c092d`. Documented in docs/flutter-ios-specifics.md §2.

**8. [Rule 1 - Bug] permission_handler iOS no-op without PERMISSION_LOCATION=1 macro**

- **Found during:** Sideload preparation — after fix #7, app launches but tapping the CTA on the rationale screen does nothing (no system prompt). Logs show `permission_handler` returns `denied` immediately without the iOS prompt firing. Root cause: permission_handler 12.0.1's iOS plugin is built with per-permission compile-flag macros (PERMISSION_LOCATION=1, PERMISSION_CAMERA=1, etc.), and the actual iOS implementation of `Permission.locationWhenInUse.request()` sits behind those macros. The flutter create-default Podfile does NOT enable any macros (App Store binary-size optimisation: apps that don't use a permission shouldn't pay for its plugin code). Without the macro, the request just returns the cached status (denied).
- **Fix:** Committed `ios/Podfile` (it had been gitignored at some point — flutter create's default .gitignore is overly aggressive on iOS) with the per-target post-install hook that enables PERMISSION_LOCATION=1:
  ```ruby
  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
          '$(inherited)',
          'PERMISSION_LOCATION=1',
        ]
      end
    end
  end
  ```
- **Files modified:** `ios/Podfile`.
- **Verification:** Re-built IPA in CI, re-sideloaded — tapping CTA now fires the iOS system permission prompt correctly. Step 6 of the UAT walk passes.
- **Committed in:** `9d7bbe7`. Documented in docs/flutter-ios-specifics.md §1 (the most-critical recipe in the doc — listed first).

---

**Total deviations:** 8 auto-fixed (1 Rule 1 bug fix on l10n import, 5 Rule 3 blocking fixes during the first push to green CI, 2 Rule 1 bug fixes during sideload preparation). Of these, 3 (#5 gen-l10n format, #7 CFBundleName, #8 PERMISSION_LOCATION) are now permanently captured in `docs/flutter-ios-specifics.md` so the next Flutter-iOS-Windows-SideStore project starts from a known-good checklist.

**Impact on plan:** All deliverables landed correctly; `<success_criteria>` items 1-7 in the plan are met (LOG-03 verified by source review; analyze + tests + tool-test + 3 CI gate scripts exit 0 locally; CI green on main; both APK + IPA artifacts downloadable; LOG-05 + AUTH-04 walk completed with verbal `approved` + one deferred AUTH-04 round-trip routing bug). Phase 1 software is complete; the remaining 28 - 1 = 27 fully-PASS requirement IDs across BOOT/AUDIT/CI/AUTH/LOG/PERF series, plus AUTH-04 marked complete-with-known-limitation.

## Issues Encountered

- **AUTH-04 cross-restart routing bug** — see "Deviations" section above and `deferred-items.md`. Marked complete-with-known-limitation rather than blocking Phase 1 closure (POC scope; user's pragmatic call). Full diagnostic + 3 fix candidates captured in deferred-items.md; reference pattern in docs/flutter-ios-specifics.md §5.6.

- **Stale STATE.md Blockers/Concerns line about the 50 MB synthetic-log smoke test** — pre-dated REQUIREMENTS.md's 2026-04-30 wording revision (LOG-05 softened to verbal `approved`). Removed from STATE.md in this plan's STATE update per the plan's `<output>` instruction to the orchestrator.

- **`gsd-tools state advance-plan` errors with STATE.md schema mismatch** — known caveat from prior plans; STATE.md was edited directly for this plan's advancement (Plan 7 of 7 complete, Phase 1 status now `phase_complete`).

- **`gsd-tools roadmap update-plan-progress` not implemented in current gsd-tools build** — ROADMAP.md was edited directly to mark Phase 1 row 7/7 Complete with date 2026-05-01.

- **`gsd-tools requirements mark-complete` not implemented in current gsd-tools build** — REQUIREMENTS.md was edited directly to mark LOG-03 fully complete and AUTH-04 (already marked Complete in the Traceability table from Plan 01-06's software completion) carries the deferred-bug note via deferred-items.md.

## Authentication Gates

None — the sideload UAT exercises iOS / Android permission system prompts, not any account-based authentication. CI's `gh` CLI was already authenticated per CLAUDE.md.

## User Setup Required

None at this time. The plan's frontmatter `user_setup:` block listed two services (GitHub repo + SideStore pairing-file) but both were already configured before plan execution (CLAUDE.md authorises Claude to use the gh CLI, and the developer's SideStore + WireGuard pairing-file was set up in a prior session). The first-push merge with origin/main bootstrap commit (commit e9e5af2) was the only one-time GitHub setup required, handled inline as Deviation #4.

## Next Phase Readiness

- **Phase 1 is software-complete + UAT-approved.** All 28 Phase 1 requirement IDs are addressed across Plans 01-01 through 01-07: BOOT-01..08 (8) + AUDIT-01..03 (3) + CI-01..05 (5) + AUTH-01..06 (6) + LOG-01..05 (5) + PERF-01 (1) = 28. AUTH-04 carries a complete-with-known-limitation note (cross-restart auto-resume bug deferred per user's POC-scope call).

- **Phase 2 hand-off is trivial.** The `lib/presentation/screens/map_screen.dart` Scaffold body is `Stack([<placeholder ColoredBox>, Positioned(top:8, right:8, FpsCounterOverlay)])`. Phase 2's first task is exactly: replace the `<placeholder ColoredBox>` with `FlutterMap(...)`. The AppBar (`buildPocAppBar`) + the `FpsCounterOverlay` (`Positioned(top:8, right:8, FpsCounterOverlay)`) stay byte-for-byte identical, so LOG-04 + PERF-01 visibility carries through the transition without any extra wiring.

- **CI is GREEN on `main`.** Future pushes (Plan 02-01 onwards) start from a green baseline. The three jobs (`gates`, `android`, `ios`) will catch any regressions in the strict-analyze + format + 3 gate-script + apk/ipa-build chain on each push.

- **`docs/flutter-ios-specifics.md` is now the project's iOS Flutter playbook.** Future iOS-touching plans (Plan 02-01's PMTiles file copy, Plan 03-XX's fog shader iOS verification, etc.) can reference this doc as the authoritative source for iOS-specific gotchas. The next Flutter-iOS-on-Windows-with-SideStore project should treat this doc as required reading.

- **Orchestrator's gsd-verifier should run next** to confirm Phase 1 success criteria are met. After that, the phase can be marked Complete in ROADMAP.md (already done in this plan's ROADMAP update). Then `/gsd:plan-phase 02` can begin Phase 2 planning.

---

## Self-Check: PASSED

All claimed files exist on disk; all claimed task commits exist in git history.

**Files verified (created/modified by this plan):**
- `lib/main.dart` — FOUND
- `lib/app.dart` — FOUND
- `lib/presentation/router.dart` — FOUND
- `lib/presentation/screens/map_screen.dart` — FOUND
- `ios/Podfile` — FOUND (committed in 9d7bbe7)
- `docs/flutter-ios-specifics.md` — FOUND (744 lines)
- `ios/Runner/Info.plist` — FOUND (CFBundleName=MirkPocDebug verified)
- `.github/workflows/ci.yml` — FOUND (pre-format gen-l10n step verified)
- `.planning/phases/01-foundation/deferred-items.md` — FOUND (AUTH-04 entry appended)
- `.planning/phases/01-foundation/01-07-SUMMARY.md` — FOUND (this file)

**Commits verified (in git log):**
- `42e3228` (Task 1 main wiring) — FOUND
- `009ff60` (Deviation #1 — analyze + Windows fixes) — FOUND
- `0c4fb08` (Deviation #2 — CI gate scripts) — FOUND
- `3fe38fe` (Deviation #3 — dart format pass) — FOUND
- `e9e5af2` (Deviation #4 — bootstrap merge) — FOUND
- `842a9da` (Deviation #5 — pre-format gen-l10n) — FOUND
- `b9c092d` (Sideload fix #7 — CFBundleName) — FOUND
- `9d7bbe7` (Sideload fix #8 — PERMISSION_LOCATION=1) — FOUND
- `b37ee41` (docs/flutter-ios-specifics.md initial) — FOUND
- `918a221` (docs §3 expansion) — FOUND
- `72d5219` (docs §5 location) — FOUND

**Verification commands (executed during the UAT walk):**
- `flutter analyze --fatal-infos --fatal-warnings` → exits 0 (after deviation #1).
- `flutter test` → ~25-30 tests green across all 7 plans' test suites.
- `dart test tool/test/` → exits 0.
- `dart run tool/check_headers.dart && dart run tool/check_licenses.dart && dart run tool/check_dependencies_md.dart` → all exit 0 (after deviation #2).
- `dart format --line-length 160 --set-exit-if-changed .` → exits 0 (after deviation #3).
- `git push origin main` → success (after deviation #4 merge).
- `gh run list --workflow=ci.yml --limit 1` → conclusion: success across all three jobs (after all CI deviations).
- `gh run download ... --name mirk-poc-debug-ios-unsigned-ipa` → IPA downloaded.
- SideStore install + launch on iPhone 17 Pro → succeeds (after sideload fixes #7 + #8).
- LOG-05 manual UAT: 16 steps walked, verbal `approved`.
- LOG-03 source review of `lib/main.dart` → ordering verified (bootstrap → observer → runZonedGuarded(runApp)).

---
*Phase: 01-foundation*
*Completed: 2026-05-01*
*Phase 1 Foundation closes here. Phase 2 (Map, no fog) is unblocked.*
