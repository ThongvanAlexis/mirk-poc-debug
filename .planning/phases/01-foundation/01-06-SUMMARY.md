---
phase: 01-foundation
plan: 06
subsystem: presentation
tags: [permission-gate, location, auth, lifecycle-observer, go-router, permission-handler, tdd, gosl-license]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: l10n bilingual strings (permissionRationaleParagraph, permissionRationaleCta, permissionDeniedParagraph, permissionDeniedOpenSettings) + pinned permission_handler 12.0.1 + go_router 16.0.0 (Plan 01-01)
  - phase: 01-foundation
    provides: buildPocAppBar(BuildContext, {String? title}) factory + FpsCounterOverlay zero-config widget (Plan 01-05 — LOG-04 + PERF-01 visible everywhere)
provides:
  - "PermissionGateScreen — StatefulWidget with WidgetsBindingObserver lifecycle re-check (route '/'). On initState if status already granted -> /map; on CTA tap requests locationWhenInUse -> grant=/map, deny=/denied; on AppLifecycleState.resumed re-checks status and auto-navs to /map if granted (W-2 fix — handles post-Settings round-trip with zero extra taps per CONTEXT.md)."
  - "PermissionDeniedScreen — Stateless screen (route '/denied') with single Open Settings button. No 'Try Again' per CONTEXT.md (iOS caches first-prompt result). The gate screen owns lifecycle re-check, so user grants in Settings + returns and the app auto-navs without manual intervention."
  - "AppLifecycleState.resumed test pattern via tester.binding.handleAppLifecycleStateChanged — proven mechanism to fire WidgetsBindingObserver.didChangeAppLifecycleState on widget tests without real iOS (W-2 verification recipe for downstream plans)."
affects: [01-07]  # Plan 07 wires the PermissionGateScreen at '/' and PermissionDeniedScreen at '/denied' in main.dart's GoRouter

# Tech tracking
tech-stack:
  added: []  # All deps already declared by Plan 01-01 (permission_handler 12.0.1, go_router 16.0.0, logging 1.3.0)
  patterns:
    - "WidgetsBindingObserver lifecycle re-check: a StatefulWidget mixes WidgetsBindingObserver, registers in initState (addObserver), unregisters in dispose (removeObserver), and overrides didChangeAppLifecycleState. On AppLifecycleState.resumed it re-runs the permission status check. This is the W-2 fix — without it, the user must either tap 'Try Again' or cold-restart the app to re-detect a permission they granted in iOS Settings. With it, the app silently picks up the new state when the user returns. Validated in widget tests via tester.binding.handleAppLifecycleStateChanged."
    - "PermissionHandlerPlatform.instance test seam: instead of mocktail or any extra mocking dep, both screen tests subclass PermissionHandlerPlatform directly and assign the override to PermissionHandlerPlatform.instance in setUp. The override extends (not implements) the abstract base so future-added methods don't break the test (per the package's own contract). Returns canned PermissionStatus / openAppSettings results without invoking real platform channels. Single mutable field per test (statusReturn / requestReturn) lets a single test simulate state transitions (the lifecycle resume test flips the field mid-test to model the post-Settings round-trip)."
    - "Pitfall B compliance carried forward: in PermissionGateScreen, _onCtaPressed and _checkAndMaybeNavigate each have one `await` followed by `if (!mounted) return;` BEFORE any context.go() call. The `use_build_context_synchronously: error` lint set by Plan 01-01 catches regressions at analyze time."
    - "go_router widget test routing: test wraps the screen in MaterialApp.router with a GoRouter configured for the three Phase 1 routes (/=screen, /map=stub, /denied=stub). Navigation assertions check for stub text presence (e.g. find.text('MAP_STUB')) instead of inspecting GoRouter internal state. Plan 07 will replace the stubs with real screens; the test stays valid because the route paths don't change."

key-files:
  created:
    - "lib/presentation/screens/permission_gate_screen.dart — PermissionGateScreen StatefulWidget with WidgetsBindingObserver lifecycle re-check (104 lines after format)"
    - "lib/presentation/screens/permission_denied_screen.dart — PermissionDeniedScreen StatelessWidget with Open Settings button (62 lines after format)"
    - "test/presentation/screens/permission_gate_screen_test.dart — 6 widget tests (AUTH-01..03 + lifecycle shortcut + deny path + AppLifecycleState.resumed re-check)"
    - "test/presentation/screens/permission_denied_screen_test.dart — 5 widget tests (AUTH-04 + LOG-04/PERF-01 visibility from denied screen)"
  modified: []

key-decisions:
  - "AppLocalizations import path: package:mirk_poc_debug/l10n/app_localizations.dart (not the plan's package:flutter_gen/gen_l10n/...). Pre-flagged in Plan 01-01 deferred-items.md and confirmed correct in Plan 01-05. Same root cause: Flutter 3.41 removed the synthetic-package flag, so AppLocalizations now ships under lib/l10n/ rather than under flutter_gen/."
  - "permission_handler_platform_interface imported in tests under `// ignore_for_file: depend_on_referenced_packages`. The package is a transitive dep of permission_handler 12.0.1 (declared in pubspec.lock, not pubspec.yaml), so the import resolves at runtime; the lint just flags the missing direct declaration. Plan 01-04 deferred-items.md flagged the same lint for path_provider_platform_interface — both follow the same pattern: comment-suppress at the test-file level rather than padding pubspec.yaml with transitive-dep declarations. Suppression scope is the test file only; production code carries no suppressions."
  - "Test 7 (Pitfall B widget test) is intentionally NOT in the test file — widget tests cannot directly assert use_build_context_synchronously violations. The plan explicitly authorises this skip; the lint rule + analyze --fatal-infos at CI is the enforcement mechanism. Behaviour is independently covered by Tests 3 (grant→/map after await) and 4 (deny→/denied after await)."
  - "Mock fields default-initialised on declaration (statusReturn/requestReturn = PermissionStatus.denied) rather than via constructor named params. After dart format the unused-optional-named-param warning emerged; switching to instance-field initialisation eliminated the warning while preserving the per-test mutate-after-construction pattern. Functionally equivalent."
  - "Two-test-file split (gate vs denied) instead of one combined file: each screen has its own concerns and its own setUp mock variant (gate test mock implements checkPermissionStatus + requestPermissions; denied test mock implements openAppSettings only). Splitting keeps each test file under 150 lines, makes failures isolate to a single screen, and matches the plan's <files> declaration."

patterns-established:
  - "WidgetsBindingObserver lifecycle re-check: the canonical Pattern 3 from RESEARCH.md §326-395. Future screens needing 'react to app return from a system page' (Settings, share sheet, camera) follow the same template — addObserver in initState, removeObserver in dispose, override didChangeAppLifecycleState, branch on AppLifecycleState.resumed."
  - "PermissionHandlerPlatform.instance test seam: zero-cost mock pattern that avoids mocktail / mockito boilerplate and works for any plugin built on the platform-interface pattern. Future plans needing geolocator / path_provider / share_plus mocks can adopt the same pattern (path_provider already does — Plan 01-04)."
  - "AppLifecycleState.resumed widget-test recipe: tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed) is the documented test-binding entrypoint that fires didChangeAppLifecycleState on every registered observer. Combined with mid-test mutation of the platform mock (mock.statusReturn = ...), this lets a single test simulate the full denied → user-grants-in-Settings → app-resumes round-trip without spinning up a real iOS Settings page."

requirements-completed: [AUTH-01, AUTH-02, AUTH-03, AUTH-04]

# Metrics
duration: 10 min
completed: 2026-04-30
---

# Phase 1 Plan 06: Permission Gate UI Summary

**Two GoRouter-backed permission screens — PermissionGateScreen (route `/`) implementing the WidgetsBindingObserver lifecycle resume re-check (W-2 fix per CONTEXT.md) plus the request-and-route flow, and PermissionDeniedScreen (route `/denied`) with a single Open-Settings button — landed with 11 widget tests green and zero new analyzer issues. Plan 01-07 can now wire both into the GoRouter directly.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-04-30T16:51:23Z
- **Completed:** 2026-04-30T17:01:50Z
- **Tasks:** 2 (both type=auto, tdd=true)
- **Files created:** 4 (2 lib, 2 test)
- **Files modified:** 0

## Accomplishments

- **`PermissionGateScreen` lands at `lib/presentation/screens/permission_gate_screen.dart`** — StatefulWidget mixing `WidgetsBindingObserver`. On `initState`, `_checkAndMaybeNavigate(reason: 'initState')` reads `Permission.locationWhenInUse.status`; if granted, `context.go('/map')` (re-launch shortcut). On CTA tap, `_onCtaPressed` calls `Permission.locationWhenInUse.request()`; on grant goes to `/map`, on deny goes to `/denied`. Every `await` in the file is followed by `if (!mounted) return;` BEFORE `context.go(...)` (Pitfall B compliance — analyzer-enforced via `use_build_context_synchronously: error`). Uses `buildPocAppBar(context)` from Plan 05 + `Positioned(top: 8, right: 8, child: FpsCounterOverlay())` for LOG-04 + PERF-01 visibility.

- **The lifecycle resume re-check (W-2 fix) is implemented as:**
  ```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkAndMaybeNavigate(reason: 'didChangeAppLifecycleState=resumed'));
    }
  }
  ```
  This is THE differentiator between "rough POC permission flow" and "polished walk experience" per the plan: when the user is on the denied screen, opens Settings, toggles the location switch, and returns to the app, the gate screen silently re-checks status and navigates to `/map` without requiring any further tap. Verified by Test 6 in the gate-screen test file (model: `AppLifecycleState.resumed` fired via `tester.binding.handleAppLifecycleStateChanged` after flipping the mock from `denied` to `granted`).

- **`PermissionDeniedScreen` lands at `lib/presentation/screens/permission_denied_screen.dart`** — StatelessWidget per CONTEXT.md (gate screen owns the lifecycle observer; denied screen has nothing to observe because if the user returns with permission granted, the gate screen — still mounted via the navigator stack — picks it up first). Single `FilledButton` labelled `permissionDeniedOpenSettings` whose `_onOpenSettingsPressed` calls `permission_handler.openAppSettings()`. No `Try Again` button per CONTEXT.md (iOS caches the first-prompt result, so re-requesting in-app cannot re-show the system prompt). Same shared AppBar + FPS overlay pattern.

- **11 widget tests pass** (6 gate + 5 denied):
  - **Gate (AUTH-01..03 + W-2):** rationale icon + paragraph + CTA render; tap CTA invokes mock's `requestPermissions`; grant → `/map` (MAP_STUB visible); deny → `/denied` (DENIED_STUB visible); already-granted on `initState` → auto-nav (MAP_STUB without CTA); `AppLifecycleState.resumed` after flipping mock to granted → auto-nav.
  - **Denied (AUTH-04 + LOG-04 + PERF-01):** denied paragraph renders; Open Settings button renders; tapping invokes mock's `openAppSettings`; share IconButton visible (LOG-04 — proves the shared AppBar carries through); FPS overlay text containing `'fps'` visible (PERF-01 — proves the overlay carries through).

- **`flutter analyze --fatal-infos --fatal-warnings`** on `lib/presentation/` and `test/presentation/` returns `No issues found!`. The 3 pre-existing info-level issues in `lib/infrastructure/logging/` and `test/infrastructure/logging/` (Plan 01-04 owners — flagged in Plan 01-01 deferred-items.md) remain out-of-scope per Rule 1-3 SCOPE BOUNDARY.

- **`dart format --line-length 160 --set-exit-if-changed`** on the four new files → exits 0 after the format pass committed during execution (no further format-only commit needed; format applied inline before each Task GREEN commit).

## API Confirmation for Plan 07

- **`PermissionGateScreen` signature locked**: `class PermissionGateScreen extends StatefulWidget { const PermissionGateScreen({super.key}); }`. Plan 07's `GoRoute(path: '/', builder: (_, _) => const PermissionGateScreen())` is the only wiring required.
- **`PermissionDeniedScreen` signature locked**: `class PermissionDeniedScreen extends StatelessWidget { const PermissionDeniedScreen({super.key}); }`. Plan 07's `GoRoute(path: '/denied', builder: (_, _) => const PermissionDeniedScreen())` likewise.
- **No imports propagate up from these screens to GoRouter config** — both screens self-contain their `permission_handler` + `go_router.context.go` calls. Plan 07's main.dart only needs to import the screen classes themselves.

## Task Commits

Each TDD cycle committed in two atomic commits (test → implementation):

1. **Task 1 RED — `test(01-06): add failing test for PermissionGateScreen rationale + request + lifecycle resume`** — `74e5cb5`
2. **Task 1 GREEN — `feat(01-06): implement PermissionGateScreen rationale + request + lifecycle resume re-check (AUTH-01..03)`** — `74b6a16`
3. **Task 2 RED — `test(01-06): add failing test for PermissionDeniedScreen Open-Settings flow (AUTH-04)`** — `c4e4722`
4. **Task 2 GREEN — `feat(01-06): implement PermissionDeniedScreen Open-Settings flow (AUTH-04)`** — `d1d26b6`

**Plan metadata commit:** TBD (committed at end of this run via gsd-tools).

## Files Created/Modified

- `lib/presentation/screens/permission_gate_screen.dart` — PermissionGateScreen StatefulWidget + WidgetsBindingObserver lifecycle re-check (~104 lines after format).
- `lib/presentation/screens/permission_denied_screen.dart` — PermissionDeniedScreen StatelessWidget with Open Settings button (~62 lines after format).
- `test/presentation/screens/permission_gate_screen_test.dart` — 6 widget tests (~146 lines after format).
- `test/presentation/screens/permission_denied_screen_test.dart` — 5 widget tests (~71 lines).

## Decisions Made

- **Used `package:mirk_poc_debug/l10n/app_localizations.dart` import path.** Plan 01-01 deferred-items.md explicitly flagged this for Plans 05 and 07; same applies to Plan 06. Synthetic-package flag dropped per Flutter 3.41; generated AppLocalizations now ships under `lib/l10n/`. Used the correct path from the start (no deviation).

- **`// ignore_for_file: depend_on_referenced_packages` at the top of each test file.** Both tests import `permission_handler_platform_interface`, which is a transitive dep of `permission_handler 12.0.1` (in `pubspec.lock` line 616 but not in `pubspec.yaml`). The flutter_lints default rule `depend_on_referenced_packages` flags this as info-level, and Plan 01-01's strict `--fatal-infos` posture promotes it to fatal. Two options: (a) declare `permission_handler_platform_interface` as a dev_dependency in pubspec.yaml (would surface a transitive dep as a direct one — adds ceremony), or (b) suppress the lint at the test-file level. Chose (b) because it scopes the suppression to test code only (production lib carries no suppressions), and it follows the same pattern Plan 01-04 already adopted for `path_provider_platform_interface` / `plugin_platform_interface` (per deferred-items.md option (b)).

- **Mock field default-initialisation** instead of optional named constructor params. After format, the unused-optional-named-param warnings (`unused_element_parameter`) appeared because each test directly mutates `mock.statusReturn = ...` rather than constructing with defaults. Switching to `PermissionStatus statusReturn = PermissionStatus.denied;` instance fields and `_MockPermissionHandlerPlatform()` zero-arg constructor eliminated the warning. The mutate-after-construction pattern (essential for the lifecycle resume test) is preserved.

- **Two-test-file split** (`permission_gate_screen_test.dart` + `permission_denied_screen_test.dart`) instead of one combined file. Each screen has different mock requirements (gate test exercises `checkPermissionStatus` + `requestPermissions`; denied test exercises `openAppSettings`), the plan's `<files>` declaration mandates the split, and it keeps each file focused.

- **Test 7 (Pitfall B) intentionally NOT authored.** The plan's `<behavior>` explicitly says: "no widget tests can directly assert use_build_context_synchronously violations — covered by `flutter analyze` enforcing `use_build_context_synchronously: error` on the source file at CI time." The lint rule + the strict-analyze CI gate is the enforcement mechanism; Tests 3 and 4 (post-await navigation) cover the runtime behaviour.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Mock unused-optional-param warnings under strict analyze**

- **Found during:** Task 1 GREEN — `flutter analyze --fatal-infos --fatal-warnings test/presentation/screens/permission_gate_screen_test.dart` reported 2 warnings:
  - `warning - A value for optional parameter 'statusReturn' isn't ever given - unused_element_parameter`
  - `warning - A value for optional parameter 'requestReturn' isn't ever given - unused_element_parameter`
- **Issue:** Plan sketched `_MockPermissionHandlerPlatform({this.statusReturn = ..., this.requestReturn = ...})` with optional named params. Tests mutate `mock.statusReturn = ...` after construction (essential for the lifecycle resume test that flips the field mid-test), so the constructor params are never passed. Strict mode flags this as fatal.
- **Fix:** Switched to instance-field default initialisation (`PermissionStatus statusReturn = PermissionStatus.denied;`) plus zero-arg constructor (`_MockPermissionHandlerPlatform();`). Functionally equivalent; warning gone.
- **Files modified:** `test/presentation/screens/permission_gate_screen_test.dart`.
- **Verification:** `flutter analyze --fatal-infos --fatal-warnings test/presentation/screens/permission_gate_screen_test.dart` → `No issues found! (ran in 1.9s)`. All 6 tests still green.
- **Committed in:** `74b6a16` (Task 1 GREEN — fix bundled with the screen-impl commit).

### Note on the `// ignore_for_file: depend_on_referenced_packages` suppression

This is documented above under "Decisions Made" rather than as a deviation, because the suppression is the explicit follow-the-Plan-01-04-pattern choice (per deferred-items.md option (b)) for handling transitive-dep imports in test code, not an unplanned deviation.

---

**Total deviations:** 1 auto-fixed (Rule 3 — strict-analyze warning blocking the GREEN gate). The fix is functionally equivalent to the plan sketch; only the field-initialisation style changed.

**Impact on plan:** All deliverables landed correctly; `<success_criteria>` items 1-5 all met. The two screen APIs (`PermissionGateScreen` + `PermissionDeniedScreen`) match the plan's specified signatures exactly. The lifecycle resume re-check pattern is byte-for-byte the plan's RESEARCH.md §Pattern 3 sketch.

## Issues Encountered

- **3 pre-existing info-level analyzer issues in `lib/infrastructure/logging/` and `test/infrastructure/logging/`** (Plan 01-04 owners — pre-existing, documented in Plan 01-01 `deferred-items.md`, **NOT in scope per Rule 1-3 SCOPE BOUNDARY**). My new files contribute zero new issues. Full-repo `flutter analyze --fatal-infos` count remains 3, unchanged from before this plan executed.

- **`tool/check_headers.dart` likely still flags the same Plan 07-owned files** (`lib/main.dart`, `test/widget_test.dart`, codegen `lib/l10n/app_localizations*.dart`) as in Plan 05's report. My new files all carry the GOSL 3-line header — confirmed by direct read of the first 3 lines of each:
  - `lib/presentation/screens/permission_gate_screen.dart` — header present
  - `lib/presentation/screens/permission_denied_screen.dart` — header present
  - `test/presentation/screens/permission_gate_screen_test.dart` — header present
  - `test/presentation/screens/permission_denied_screen_test.dart` — header present

## Authentication Gates

None — the screens invoke iOS / Android permission system prompts, not any account-based authentication. Manual UAT for the actual system prompt + Settings round-trip is deferred to Plan 01-07's iOS sideload walk per VALIDATION.md `Manual-Only Verifications` table.

## User Setup Required

None — no external service configuration required for this plan. The plan's frontmatter has no `user_setup:` section.

## Next Phase Readiness

- **Plan 01-07 (main.dart bootstrap + GoRouter wiring + map-screen scaffolding)** can now declare:
  ```dart
  GoRoute(path: '/',       builder: (_, _) => const PermissionGateScreen()),
  GoRoute(path: '/denied', builder: (_, _) => const PermissionDeniedScreen()),
  GoRoute(path: '/map',    builder: (_, _) => const MapScreen()), // Plan 07 builds MapScreen
  ```
- **Three screens, one Scaffold pattern**: every Phase 1 screen consumes `appBar: buildPocAppBar(context)` and `body: Stack(children: [<screen body>, const Positioned(top: 8, right: 8, child: FpsCounterOverlay())])`. LOG-04 + PERF-01 visibility is structurally enforced (every Scaffold uses the same factory).
- **AUTH-01..04 are software-complete after this plan**; full UAT (system prompt UI, Settings deep-link round-trip, post-resume auto-nav with a real iPhone) is on Plan 01-07's iOS sideload walk per VALIDATION.md.

---

## Self-Check: PASSED

All claimed files exist on disk; all claimed task commits exist in git history.

**Files verified:**
- `lib/presentation/screens/permission_gate_screen.dart` (FOUND)
- `lib/presentation/screens/permission_denied_screen.dart` (FOUND)
- `test/presentation/screens/permission_gate_screen_test.dart` (FOUND)
- `test/presentation/screens/permission_denied_screen_test.dart` (FOUND)
- `.planning/phases/01-foundation/01-06-SUMMARY.md` (FOUND — this file)

**Commits verified:**
- `74e5cb5` (Task 1 RED) — FOUND
- `74b6a16` (Task 1 GREEN) — FOUND
- `c4e4722` (Task 2 RED) — FOUND
- `d1d26b6` (Task 2 GREEN) — FOUND

**Verification commands (output captured during execution):**
- `flutter test test/presentation/screens/` → 11/11 tests pass (6 gate + 5 denied).
- `flutter analyze --fatal-infos --fatal-warnings lib/presentation/ test/presentation/` → `No issues found! (ran in 2.4s)`.
- `dart format --line-length 160 --set-exit-if-changed lib/presentation/screens/ test/presentation/screens/` → exits 0 (4 files unchanged after the in-flight format pass during GREEN commits).
- Full-repo `flutter analyze --fatal-infos` → 3 pre-existing issues only (Plan 01-04 owners), zero new contributions from this plan.

---
*Phase: 01-foundation*
*Completed: 2026-04-30*
