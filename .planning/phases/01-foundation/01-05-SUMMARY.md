---
phase: 01-foundation
plan: 05
subsystem: presentation
tags: [widgets, app-bar, share-logs, fps-counter, promotion, tdd, gosl-license]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: pubspec.yaml deps (share_plus 12.0.2, path_provider 2.1.5, path 1.9.1, logging 1.3.0) + l10n (AppLocalizations.shareLogsTooltip, AppLocalizations.appTitle) (Plan 01-01)
  - phase: 01-foundation
    provides: FileLogger.activeFilename static getter (Plan 01-04)
provides:
  - "buildPocAppBar(BuildContext, {String? title}) — PreferredSizeWidget factory shared by every Phase 1 Scaffold (LOG-04). Encapsulates the share IconButton + tooltip + title fallback."
  - "FpsCounterOverlay — const StatefulWidget rendering '<fps> fps / <Hz> Hz' chip (PERF-01, Pitfall E ProMotion-aware). Zero-config; parents Stack it on top of their body."
  - "Receiver-side LOG-05 baseline: the share handler logs raw + gzipped byte counts at INFO level (Pitfall D — establishes the byte-integrity reference for the iOS Mail attachment UAT)."
affects: [01-06, 01-07]  # Plans 06 + 07 import buildPocAppBar in their Scaffold's appBar slot and Stack FpsCounterOverlay on top of their body

# Tech tracking
tech-stack:
  added: []  # All deps already declared by Plan 01-01 (share_plus 12.0.2, path_provider 2.1.5, path 1.9.1, logging 1.3.0); FileLogger from Plan 01-04
  patterns:
    - "AppBar factory pattern: a top-level function returning PreferredSizeWidget. Parent screens consume `appBar: buildPocAppBar(context)` directly — no class wrapper, no extra abstraction layer. Enforces the LOG-04 contract via a single shared helper."
    - "Pitfall B compliance for share-sheet handler: every `await` in `_onSharePressed` is followed by `if (!context.mounted) return;` before context is reused. Three awaits → three guards. The analyzer's `use_build_context_synchronously: error` rule (set by Plan 01-01) catches regressions."
    - "Pitfall E compliance for refresh rate: NEVER hardcoded. `WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate` is read once in `initState` and surfaced verbatim in the chip's `Hz` field — so a 30 fps reading on a 120 Hz target is unambiguous."
    - "share_plus 12.0.2 deprecation deviation: the plan called for `Share.shareXFiles([XFile(...)])`, but flutter analyze (strict mode + `--fatal-infos`) flags both `Share` and `shareXFiles` as deprecated. Switched to `SharePlus.instance.share(ShareParams(files: ...))` — the only non-deprecated path forward in this version."

key-files:
  created:
    - "lib/presentation/widgets/poc_app_bar.dart — buildPocAppBar factory + _onSharePressed handler"
    - "lib/presentation/widgets/fps_counter_overlay.dart — FpsCounterOverlay StatefulWidget"
    - "test/presentation/widgets/poc_app_bar_test.dart — 5 widget tests covering LOG-04"
    - "test/presentation/widgets/fps_counter_overlay_test.dart — 4 widget tests covering PERF-01 + Pitfall E"
  modified: []

key-decisions:
  - "AppLocalizations import path: `package:mirk_poc_debug/l10n/app_localizations.dart` instead of the plan's suggested `package:flutter_gen/gen_l10n/app_localizations.dart`. Plan 01-01 dropped the synthetic-package flag (Flutter 3.41 removal) and generated AppLocalizations now lives under the project's own `lib/l10n/` tree. Pre-flagged in Plan 01-01's deferred-items.md."
  - "share_plus API switch: `SharePlus.instance.share(ShareParams(files: <XFile>[...]))` instead of plan's `Share.shareXFiles(<XFile>[...])`. share_plus 12.0.2 deprecates the latter (Rule 1 deviation — analyze fails strict mode). The new API is functionally equivalent and is the only non-deprecated path in this version."
  - "Skipped Test 5 (button disabled when activeFilename is null). Plan explicitly authorises this skip — exercising the disabled-state path requires either path_provider mocking (already proven in Plan 01-04 but adds test boilerplate) or a test seam on FileLogger.activeFilename. The on-press handler's null-guard already covers the runtime semantics, and Plan 01-04's tests confirm the static getter works."
  - "FpsCounterOverlay styling discretion (per CONTEXT.md): font size 12, padding 8/4, background `Colors.black54`, rounded radius 4. The CONTEXT.md mandate is the data shape (`<fps> fps / <Hz> Hz`) and the position (top-right, supplied by parent's Stack), not the styling. Discretion taken on chip aesthetics; values are sensible defaults that Plans 06/07 can override visually if needed."
  - "Magic number rule compliance: `0.0` initial _refreshRate replaced with `_defaultRefreshRateHz` named constant; `1e6` replaced with `_microsPerSecond`; `2 * refreshRate` replaced with `_bufferWindowSeconds`. Per CLAUDE.md §Magic numbers — local-use constants live as private static fields on the State class."

patterns-established:
  - "PreferredSizeWidget factory: the LOG-04 enforcement mechanism. Future screens just call `appBar: buildPocAppBar(context)` — they cannot accidentally drop the share button without affirmatively writing a different AppBar."
  - "Frame-callback FPS counter pattern: `addPersistentFrameCallback` for accumulation + 250 ms `Timer.periodic` for setState. Bounded buffer (refreshRate * 2 ceil) keeps memory flat. Flutter SDK does NOT expose `removePersistentFrameCallback` — the State's `mounted` guard in `_recompute` is the only correctness fence after dispose. No leak."
  - "Pitfall B share-sheet handler pattern: when a UI action triggers a multi-await async chain, every step that wants to use `context` after an `await` must guard with `if (!context.mounted) return;`. This handler has 3 awaits → 3 guards before each context reuse."

requirements-completed: [LOG-04, PERF-01]

# Metrics
duration: 5 min
completed: 2026-04-30
---

# Phase 1 Plan 05: Cross-cutting Presentation Widgets Summary

**Two cross-cutting widgets — `buildPocAppBar(context, {String? title})` PreferredSizeWidget factory carrying the share-logs IconButton (LOG-04) and `FpsCounterOverlay` StatefulWidget rendering the ProMotion-aware FPS chip (PERF-01, Pitfall E) — landed with 9 widget tests green and zero analyzer issues. Plans 06 + 07 can now import both directly without further plumbing.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-30T16:41:23Z
- **Completed:** 2026-04-30T16:45:56Z
- **Tasks:** 2 (both type=auto, tdd=true)
- **Files created:** 4 (2 lib, 2 test)
- **Files modified:** 0

## Accomplishments

- **`buildPocAppBar(BuildContext, {String? title})` factory** lands at `lib/presentation/widgets/poc_app_bar.dart`. Returns a Material 3 AppBar with one IconButton in `actions`. The IconButton's:
  - `tooltip` resolves from `AppLocalizations.shareLogsTooltip` — `'Share logs'` in en, `'Partager les logs'` in fr.
  - `onPressed` is null when `FileLogger.activeFilename == null` (button visually disabled — consistent with the no-active-log runtime state).
  - When pressed: reads bytes from the active log file, gzips in-memory via `dart:io` `GZipCodec`, writes the gzipped bytes to `<tempDir>/<basenameWithoutExtension>.txt.gz` via path_provider, and routes through `SharePlus.instance.share(ShareParams(files: [XFile(..., mimeType: 'application/gzip')]))`. Pitfall B compliance: every `await` followed by `if (!context.mounted) return;` (3 awaits, 3 guards).
  - The handler logs `'Sharing log: <raw> bytes raw, <gzipped> bytes gzipped, file=<path>'` at INFO level — Pitfall D receiver-side baseline for LOG-05 UAT.

- **`FpsCounterOverlay` widget** lands at `lib/presentation/widgets/fps_counter_overlay.dart`. Const constructor; reads refresh rate ONCE in `initState` from `WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate` (Pitfall E mandate — NEVER hardcode 60 or 120). Frame timing accumulated via `SchedulerBinding.addPersistentFrameCallback`; a 250 ms `Timer.periodic` recomputes the rolling 1-second average and triggers `setState`. Frame buffer bounded to `refreshRate * 2` ceil entries (~2 s of frames) so memory stays flat. The chip:
  - Renders `'<fps> fps / <Hz> Hz'` (e.g. `'30 fps / 120 Hz'` on a ProMotion device throttled to 30 fps).
  - `Container` with `Colors.black54` background, rounded radius 4, padding 8/4.
  - Text: `Colors.white`, `fontSize: 12`, `FontFeature.tabularFigures()` for stable digit width.

- **9 widget tests pass** (5 + 4). LOG-04 coverage: share IconButton present in AppBar `actions`; English tooltip equals `'Share logs'`; French tooltip equals `'Partager les logs'`; default title is `'MirkFall POC'`; custom `title:` parameter overrides default. PERF-01 + Pitfall E coverage: chip text contains `'fps'`; chip text contains `'Hz'`; chip text contains the value of `WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate.toStringAsFixed(0)` followed by `' Hz'` (proves the refresh rate is read from PlatformDispatcher, not hardcoded); initial state renders `'0 fps'` before any frames are produced.

## API Confirmation for Plans 06 + 07

- **`buildPocAppBar` signature locked**: `PreferredSizeWidget buildPocAppBar(BuildContext context, {String? title})`. Plans 06 + 07 consume:
  - `appBar: buildPocAppBar(context)` — defaults to `AppLocalizations.appTitle` ('MirkFall POC').
  - `appBar: buildPocAppBar(context, title: 'Custom Title')` — for screens that need a non-default title.
- **`FpsCounterOverlay` API locked**: `const FpsCounterOverlay()` — zero-config. Plans 06 + 07 wrap it in a `Positioned(top: 8, right: 8, child: FpsCounterOverlay())` inside the Scaffold's `body: Stack(children: [...])`.

## Task Commits

Each TDD cycle was committed in two atomic commits (test → implementation), plus one chore commit for `dart format` adjustments:

1. **Task 1 RED — `test(01-05): add failing test for buildPocAppBar share-logs factory`** — `6538242`
2. **Task 1 GREEN — `feat(01-05): implement buildPocAppBar share-logs factory (LOG-04)`** — `229c96f`
3. **Task 2 RED — `test(01-05): add failing test for FpsCounterOverlay PERF-01 chip`** — `c50246d`
4. **Task 2 GREEN — `feat(01-05): implement FpsCounterOverlay ProMotion-aware FPS chip (PERF-01)`** — `241127d`
5. **Format pass — `chore(01-05): apply dart format --line-length 160 to presentation widgets`** — `50a2aca`

**Plan metadata commit:** TBD (committed at end of this run via gsd-tools).

## Files Created/Modified

- `lib/presentation/widgets/poc_app_bar.dart` — buildPocAppBar factory + _onSharePressed handler (76 lines).
- `lib/presentation/widgets/fps_counter_overlay.dart` — FpsCounterOverlay StatefulWidget (109 lines after format).
- `test/presentation/widgets/poc_app_bar_test.dart` — 5 widget tests (54 lines).
- `test/presentation/widgets/fps_counter_overlay_test.dart` — 4 widget tests (51 lines after format).

## Decisions Made

- **Replaced `Share.shareXFiles(...)` with `SharePlus.instance.share(ShareParams(files: ...))`.** The plan's `<action>` block called for `Share.shareXFiles([XFile(outFilename, mimeType: 'application/gzip')])`, but share_plus 12.0.2 deprecates both `Share` and `shareXFiles`. The strict analyze gate (Plan 01-01's `analysis_options.yaml` + the `--fatal-infos` posture) flags this as 2 errors. The replacement is functionally equivalent: `ShareParams.files` accepts `List<XFile>?` with the same `XFile(path, mimeType: ...)` signature, and `SharePlus.instance.share(...)` is the documented non-deprecated entry point. Both API symbols verified against the package source at `/c/Users/oliver/AppData/Local/Pub/Cache/hosted/pub.dev/share_plus_platform_interface-6.1.0/lib/platform_interface/share_plus_platform.dart` (`class ShareParams` line 39, `final List<XFile>? files` line 115).

- **Used `package:mirk_poc_debug/l10n/app_localizations.dart` import path.** Plan 01-01 deferred-items.md called this out explicitly: synthetic-package flag dropped per Flutter 3.41 removal; generated AppLocalizations now ships under `lib/l10n/` rather than under `flutter_gen/`. The plan's suggested `package:flutter_gen/gen_l10n/...` path would simply fail to resolve.

- **Skipped Test 5 (button disabled when no active log).** The plan explicitly green-lights this skip: "behavior is still observable in the on-press handler which `return`s early on null. ... For Plan 05, it's acceptable to omit this test case." The runtime null-guard in the factory (`onPressed: activeFilename == null ? null : ...`) is straightforward and visually inspectable; exercising it would require either the path_provider mock pattern from Plan 01-04 or a test seam on `FileLogger.activeFilename`. Neither warranted for the LOG-04 contract that the visible button + correct tooltip on every screen — already covered by tests 1-4.

- **`dart:ui` import dropped from FpsCounterOverlay.** The plan's sketch imported `'dart:ui' show FontFeature`, but `package:flutter/material.dart` re-exports `FontFeature` transitively. Strict analyze flagged the import as unnecessary (`unnecessary_import`); removed inline. No behavioural change.

- **Magic-number cleanup in FpsCounterOverlay.** Per CLAUDE.md §Magic numbers, the literal `60` (default refresh rate fallback in `_refreshRate` field initialiser), `1e6` (microseconds-per-second factor in the FPS division), and `2` (the multiplier on refresh rate that gives the buffer cap) all became named private static constants on `_FpsCounterOverlayState`: `_defaultRefreshRateHz`, `_microsPerSecond`, `_bufferWindowSeconds`. The intent is documented inline; the values are unchanged.

- **FpsCounterOverlay styling — discretion taken on aesthetics.** Per CONTEXT.md, the data shape (`<fps> fps / <Hz> Hz`) and the position (top-right, supplied by parent Stack) are mandated; the chip's visual style is discretion. Chosen: `Colors.black54` background, rounded 4 px corners, `EdgeInsets.symmetric(horizontal: 8, vertical: 4)` padding, white 12-pt text with `FontFeature.tabularFigures()` for stable digit width. Plans 06 + 07 can override visually by wrapping FpsCounterOverlay in a Theme + adjusting if needed; the public API is intentionally minimal.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Share.shareXFiles(...)` is deprecated in share_plus 12.0.2 — strict analyze fails**

- **Found during:** Task 1 GREEN — `flutter analyze --fatal-infos --fatal-warnings lib/presentation/widgets/poc_app_bar.dart` reported 2 info-level issues:
  - `info - 'Share' is deprecated and shouldn't be used. Use SharePlus instead - deprecated_member_use`
  - `info - 'shareXFiles' is deprecated and shouldn't be used. Use SharePlus.instance.share() instead - deprecated_member_use`
- **Issue:** With analysis_options.yaml carrying `--fatal-infos` posture (Plan 01-01 mandate), info-level deprecation warnings are CI-fatal. The plan's `<action>` sketch used the deprecated API.
- **Fix:** Replaced `await Share.shareXFiles(<XFile>[XFile(outFilename, mimeType: 'application/gzip')])` with `await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(outFilename, mimeType: 'application/gzip')]))`. Verified the new API against the package source (share_plus 12.0.2 + share_plus_platform_interface 6.1.0). Inline workaround comment explains the deprecation — per CLAUDE.md §Workarounds.
- **Files modified:** `lib/presentation/widgets/poc_app_bar.dart`.
- **Verification:** `flutter analyze --fatal-infos --fatal-warnings lib/presentation/widgets/poc_app_bar.dart` → `No issues found! (ran in 2.8s)`. All 5 widget tests still green.
- **Committed in:** 229c96f (Task 1 GREEN).

**2. [Rule 1 - Bug] `import 'dart:ui' show FontFeature` flagged as unnecessary by strict analyze**

- **Found during:** Task 2 GREEN — `flutter analyze --fatal-infos --fatal-warnings lib/presentation/widgets/fps_counter_overlay.dart` reported 1 info-level issue:
  - `info - The import of 'dart:ui' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/material.dart' - unnecessary_import`
- **Issue:** `package:flutter/material.dart` already re-exports `FontFeature` transitively via `package:flutter/painting.dart` → `dart:ui`. The explicit show import is redundant. Strict mode flags this as fatal.
- **Fix:** Removed `import 'dart:ui' show FontFeature;`. The `FontFeature.tabularFigures()` call site continues to resolve via the re-export.
- **Files modified:** `lib/presentation/widgets/fps_counter_overlay.dart`.
- **Verification:** `flutter analyze --fatal-infos --fatal-warnings lib/presentation/widgets/fps_counter_overlay.dart` → `No issues found! (ran in 1.3s)`. All 4 widget tests still green.
- **Committed in:** 241127d (Task 2 GREEN).

**3. [Rule 1 - Bug] AppLocalizations import path mismatch with Plan 01-01 reality**

- **Found during:** Task 1 RED authoring (pre-flagged by Plan 01-01 deferred-items.md).
- **Issue:** The plan's sketch imports `package:flutter_gen/gen_l10n/app_localizations.dart`. That path is the synthetic-package output path. Plan 01-01 dropped the synthetic-package flag from `l10n.yaml` (Flutter 3.41 removed the feature), so generated AppLocalizations now lives at `lib/l10n/app_localizations.dart` and the correct import path is `package:mirk_poc_debug/l10n/app_localizations.dart`.
- **Fix:** Used the correct path from the start (Plan 01-01's deferred-items.md flagged this for Plan 01-05). No deviation from intent — only from the literal plan sketch.
- **Files modified:** `lib/presentation/widgets/poc_app_bar.dart`, `test/presentation/widgets/poc_app_bar_test.dart` — both use `package:mirk_poc_debug/l10n/app_localizations.dart`.
- **Verification:** `flutter test test/presentation/widgets/poc_app_bar_test.dart` → 5/5 tests pass.
- **Committed in:** 6538242 (Task 1 RED) + 229c96f (Task 1 GREEN).

### Format-only adjustments (not deviations)

- **`dart format --line-length 160 --set-exit-if-changed`** reformatted 3 files (line wrap + trailing commas applied per Dart 3.11.5 formatter rules). All 9 widget tests still green; analyze still clean. Committed as `chore(01-05): apply dart format ...` (50a2aca). This is a format-style alignment, not a behavioural deviation.

---

**Total deviations:** 3 auto-fixed (all Rule 1 — strict-analyze deprecations + a documented downstream import-path adjustment from Plan 01-01).
**Impact on plan:** All deliverables landed correctly; `<success_criteria>` items 1-5 all met. The two core APIs (`buildPocAppBar` factory + `FpsCounterOverlay` widget) match the plan's specified signatures exactly; only the implementation chose a non-deprecated share_plus call site.

## Issues Encountered

- **`tool/check_headers.dart` reports pre-existing failures.** The check flags `lib/main.dart` + `test/widget_test.dart` + the three `lib/l10n/app_localizations*.dart` codegen files as missing the GOSL header. None are owned by this plan:
  - `lib/main.dart` is the un-rewritten `flutter create` default — Plan 01-07 owns the GOSL-headed bootstrap.
  - `test/widget_test.dart` is also a `flutter create` default — Plan 01-07 will replace it.
  - `lib/l10n/app_localizations*.dart` are codegen outputs; ideally `tool/check_headers.dart` would skip them under the `_excludePatterns` list. Updating that exclusion list is out of scope for this plan; logged as a candidate for the deferred-items.md follow-up.
- **My new files pass GOSL header check.** Confirmed by running `dart run tool/check_headers.dart` and grepping the output for `poc_app_bar` / `presentation` — no matches in the failure list.
- **3 info-level analyzer issues remain in `test/infrastructure/logging/`** (Plan 01-04 owners — pre-existing, documented in deferred-items.md, NOT in scope per Rule 1-3 SCOPE BOUNDARY).

## Authentication Gates

None — both widgets are pure UI + dart:io / share_plus / path_provider. The share-sheet handler invokes the iOS / Android system share sheet but does not require any account login or API key. The actual share UI is exercised manually during the LOG-05 iOS sideload UAT walk (Plan 01-07).

## User Setup Required

None — no external service configuration required for this plan. Plans 06 + 07 will surface the screens that exercise these widgets at runtime; the iOS sideload UAT for share-sheet integrity is owned by Plan 01-07.

## Next Phase Readiness

- **Plan 01-06 (permission gate UI)** can `import '../widgets/poc_app_bar.dart';` and `import '../widgets/fps_counter_overlay.dart';` to wire `appBar: buildPocAppBar(context)` and `body: Stack(children: [<screen body>, const Positioned(top: 8, right: 8, child: FpsCounterOverlay())])`. No further plumbing required.
- **Plan 01-07 (main.dart wiring + denied screen + map screen scaffolding)** consumes the same two APIs in three Scaffold sites. The LOG-04 contract — share button reachable from every screen — is enforced because every Phase 1 Scaffold uses the same factory.
- **LOG-05 UAT readiness (Plan 01-07):** the share handler's `_shareLogger.info('Sharing log: ${bytes.length} bytes raw, ${gzipped.length} bytes gzipped, file=$outFilename')` line establishes the byte-integrity baseline for the iOS Mail attachment receiver-side check (Pitfall D). The receiver decompresses `<basename>.txt.gz` and asserts `gunzip|wc -c` matches the logged raw byte count.
- **PERF-01 manual gate (Plan 01-07 UAT):** the `<live fps> fps / 120 Hz` overlay being visible on the map screen during the Phase 1 walk is the human-verifiable manual gate. The widget is ready for that walk; no further code in this plan.

---

## Self-Check: PASSED

All claimed files exist on disk; all claimed task commits exist in git history.

**Files verified:**
- `lib/presentation/widgets/poc_app_bar.dart` (FOUND)
- `lib/presentation/widgets/fps_counter_overlay.dart` (FOUND)
- `test/presentation/widgets/poc_app_bar_test.dart` (FOUND)
- `test/presentation/widgets/fps_counter_overlay_test.dart` (FOUND)
- `.planning/phases/01-foundation/01-05-SUMMARY.md` (FOUND — this file)

**Commits verified:**
- `6538242` (Task 1 RED: test(01-05): add failing test for buildPocAppBar share-logs factory) — FOUND
- `229c96f` (Task 1 GREEN: feat(01-05): implement buildPocAppBar share-logs factory (LOG-04)) — FOUND
- `c50246d` (Task 2 RED: test(01-05): add failing test for FpsCounterOverlay PERF-01 chip) — FOUND
- `241127d` (Task 2 GREEN: feat(01-05): implement FpsCounterOverlay ProMotion-aware FPS chip (PERF-01)) — FOUND
- `50a2aca` (chore(01-05): apply dart format --line-length 160 to presentation widgets) — FOUND

**Verification commands:**
- `flutter test test/presentation/widgets/` → 9/9 tests pass
- `flutter analyze --fatal-infos --fatal-warnings lib/presentation/ test/presentation/` → `No issues found! (ran in 3.3s)`
- `dart format --line-length 160 --set-exit-if-changed lib/presentation/widgets/ test/presentation/widgets/` → exits 0 (post-50a2aca)

---
*Phase: 01-foundation*
*Completed: 2026-04-30*
