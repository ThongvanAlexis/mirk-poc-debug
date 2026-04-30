# Phase 1: Foundation - Research

**Researched:** 2026-04-30
**Domain:** Flutter bootstrap (iOS-primary sideload via SideStore, GitHub Actions CI matrix, GOSL license/telemetry gates), JSON-Lines file logger (port from parent), `permission_handler` whenInUse flow with lifecycle re-check, `share_plus` to iOS Mail, on-screen FPS counter (ProMotion-aware), bilingual fr/en via `flutter_localizations`
**Confidence:** HIGH

## Summary

Phase 1 is mechanical assembly, not invention. The decisions in `01-CONTEXT.md` plus the project-level `research/STACK.md` and `research/PITFALLS.md` already lock the stack, the dependency pins, the CI workflow shape, and the source for every non-trivial component (parent project `C:\claude_checkouts\GOSL-MirkFall`). This research file's job is to (a) consolidate the locked decisions into a planner-ready brief, (b) name the exact parent files to port verbatim, (c) flag the three-line POC adaptations the planner must instruct the executor to apply, and (d) define the validation architecture — which is unusually thin for Phase 1 because the highest-value validations are manual sideload smoke tests, not unit tests.

There is one unresolved-by-CONTEXT.md verification item the planner must own: the parent project's CI workflow (which we are mirroring) has `flutter-version: '3.41.7'` and `runs-on: macos-26`, while STACK.md prescribes `flutter-version: '3.41.8'` and historically `macos-latest`. The planner must pick one and lock it consistently across the workflow file and `pubspec.yaml`'s `environment:` constraint — recommended below.

**Primary recommendation:** Port-then-adapt rather than re-implement. Every Phase 1 component except the placeholder `/map` Scaffold and the bilingual `AppLocalizations` setup has a working source in `C:\claude_checkouts\GOSL-MirkFall`. The planner should structure tasks as "copy file X from parent path Y, apply the documented adaptations, verify via Z" rather than "implement file X following pattern Y."

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Localization**
- Both French and English via `flutter_localizations` (SDK package, BSD-3, no telemetry)
- ARB files under `lib/l10n/`, generated via `flutter gen-l10n`
- Locale follows device; default fallback = French (developer is French, walks in Melun)
- All in-app strings (rationale screen, denied screen, share button tooltip, FPS counter labels, AppBar title) go through the `AppLocalizations` accessor — no hardcoded user-facing strings
- `Info.plist` `NSLocationWhenInUseUsageDescription`: French string (per AUTH-05); English variant via `InfoPlist.strings` if iOS i18n is straightforward, otherwise French only is acceptable for v1

**Permission flow UX**
- Rationale screen layout: centered Material icon (`Icons.location_on_outlined`) + one explanatory paragraph (~2 sentences explaining locationWhenInUse → fog of war + "stays on device") + single primary CTA button (`'Autoriser la position'` / `'Allow location'`)
- Denied screen: short explanation + single 'Open Settings' button calling `permission_handler.openAppSettings()`. No 'Try Again' button (iOS caches first-prompt result; subsequent in-app requests silently return cached status — misleading UX)
- Lifecycle resume re-check: app observes `AppLifecycleState.resumed` and re-checks `Permission.locationWhenInUse.status` on every resume. If granted → auto-navigate to `/map` via `context.go('/map')`
- Grant flow (AUTH-03): the moment permission becomes `granted` (whether from in-app prompt or post-settings resume), call `context.go('/map')` immediately. No confirmation, no delay, no extra tap

**FPS counter**
- Visibility: always-on overlay, present on every screen of the POC (permission gate, denied, /map). POC is debug-only; no production state to hide it from
- Position: top-right corner. Avoids Dynamic Island / notch (top-center), iOS home-indicator gesture zone (bottom), and the recenter FAB Phase 2 will add (bottom-right)
- Display format: `60 fps / 120 Hz` — current 1-second rolling-average fps, slash, device refresh rate. ProMotion-aware per Pitfall 14
- Averaging: 1-second rolling average per PERF-01. Computed via `WidgetsBinding.instance.addPersistentFrameCallback` (or `SchedulerBinding`) accumulating frame timings, recomputed every ~250 ms display tick
- Refresh rate source: `WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate` (or equivalent) — never hardcode 60 or 120

**Logger & share UX**
- Filename format: UTC ISO-8601 basic: `yyyymmddTHHMMSSZ_logs.txt` (e.g. `20260430T142503Z_logs.txt`). Fixes Pitfall 19 (midnight-cross local-time ambiguity). Diverges from parent project's `yyyymmdd_hhmm.ss_logs.txt` — intentional POC improvement
- Per-session size: unbounded write (no per-session rotation). Gzip happens at share time only
- Across-session retention: 10 MB total cap on `<app_documents_dir>/logs/` directory, enforced by prune-oldest at bootstrap (port `kMaxLogsDirBytes = 10 MB` constant + `_pruneToSizeLimit` from parent verbatim)
- File encoding: UTF-8, no BOM. Set explicitly (do not rely on platform default). Preserves accented French place names round-trip through Mail
- Share trigger: `Icons.share` in the Scaffold's AppBar `actions` list, with tooltip (`'Partager les logs'` / `'Share logs'`). Visible on every screen (LOG-04). Tapping → gzip the active log file → invoke `share_plus.shareXFiles([gzippedFile])` → user picks Mail (or Messages, etc.)
- No PII confirmation dialog: POC is single-developer
- On log write failure: silent fallback to `dart:developer.log()` only. Catch `FileSystemException`, surface via `dart:developer.log()`, null the `RandomAccessFile` handle to avoid infinite loop in zone error handler. No UI banner, no crash. Matches CLAUDE.md "erreurs non-critiques en périphérie" policy

**Placeholder /map screen (Phase 1 only — Phase 2 replaces body)**
- Scaffold with AppBar (title `'MirkFall POC'`, share-icon action) + dark-grey solid-color body (e.g. `Colors.grey[850]`) + always-on FPS counter overlay top-right
- No placeholder text, no logo, no GPS readout — Phase 2 swaps the body for `FlutterMap`. Minimum churn between phases
- Same AppBar appears on permission gate and denied screens (LOG-04 mandate). One `Widget _buildAppBar(BuildContext)` helper in a shared `widgets/` file, reused across all three screens

**Phase 1 UAT exit gate**
- No 50 MB synthetic-log smoke test. Explicitly removed from scope: "this is a POC, just log, and if it does not work I'll tell you"
- LOG-05 ("Phase 1 smoke test confirms this") softens to: developer sideloads the IPA, taps share-logs, picks Mail, verifies the email arrives with the gzipped log file. Verbal "approved" is the gate
- Update REQUIREMENTS.md LOG-05 wording during Phase 1 planning to drop the "50 MB synthetic-log" specification

### Claude's Discretion

- Exact wording / paragraph copy of the rationale and denied screens (subject to user review during planning if a draft is rejected)
- FPS counter styling: font size, font weight, background opacity, padding, color (legible in any background)
- Dark-grey shade for the placeholder body
- AppBar styling (color, elevation) — match Material 3 defaults unless something obviously wrong
- Whether the AppBar `leading` shows a hamburger / back arrow / nothing on the permission gate
- Tooltip strings for the share button (within the bilingual scope)

### Deferred Ideas (OUT OF SCOPE)

- **In-app debug menu / verbose toggle**: parent has SharedPreferences-backed verbose toggle reachable via 7-tap easter egg on the about screen. POC is always-verbose (LOG-02), so the toggle is unnecessary
- **Custom illustration on rationale screen**: rejected for v1 in favor of a Material icon
- **English-localized `Info.plist` `NSLocationWhenInUseUsageDescription`**: French-only is acceptable for v1 if iOS `InfoPlist.strings` localization adds friction
- **Per-session log file rotation by size**: parent uses across-session 10 MB cap with unbounded per-session writes. POC keeps the same
- **Walk-replay tool** (Pitfall 6 mitigation): out of scope for Phase 1, captured here so Phase 2 planning can pick it up
- **CI license-check failure UX / DEPENDENCIES.md format details**: locked by parent's `tool/check_licenses.dart` + `tool/check_dependencies_md.dart` (port verbatim)
- **App icon design**: out of scope for Phase 1; default Flutter icon is fine for sideloaded debug walks
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BOOT-01 | Flutter SDK pinned 3.41.8, Dart 3.11.x; `pubspec.yaml` strict-pinned (no `^`); `pubspec.lock` committed | STACK.md §1 (Flutter SDK), §Final pubspec.yaml. **Verification action below**: parent uses 3.41.7 — planner picks one. |
| BOOT-02 | Every `.dart` file in `lib/` and `test/` starts with the GOSL v1.0 3-line header | Port `tool/check_headers.dart` from parent verbatim (parent file `C:\claude_checkouts\GOSL-MirkFall\tool\check_headers.dart`). Includes `--help`, exclusion regex list, exit codes 0/1/2. Already covers `lib/test/tool/integration_test` roots. |
| BOOT-03 | `LICENSE` at repo root contains GOSL v1.0 text | Port from parent `C:\claude_checkouts\GOSL-MirkFall\LICENSE.md` verbatim (note `.md` extension in parent — POC's REQUIREMENTS.md says `LICENSE` without extension; planner should clarify with user; either name works on the filesystem) |
| BOOT-04 | `analysis_options.yaml` enforces `strict-casts/inference/raw-types`; uses `flutter_lints 6.0.0` | STACK.md §12 — exact YAML provided. Add `use_build_context_synchronously: error` per Pitfall 15 |
| BOOT-05 | `dart format --line-length 160 --set-exit-if-changed .` passes | CI step exists in parent `ci.yml` line 53-55 — port verbatim |
| BOOT-06 | `flutter analyze` passes with no warnings | CI step exists in parent `ci.yml` line 57-58 with `--fatal-infos --fatal-warnings` — port verbatim |
| BOOT-07 | `Fra_Melun.pmtile` (4 MB MVT vector) bundled under `assets/maps/` | STACK.md §PMTiles asset bundling. Source: `C:\claude_checkouts\countries-pmtiles\Fra_Melun.pmtile` per PROJECT.md context. `pubspec.yaml` `flutter:` block includes `assets:` + `shaders:` lines |
| BOOT-08 | Battle-tested files ported verbatim from MirkFall (shader, SDF builder, reveal disc, viewport bbox, tile cell iteration, projection, fog uniforms, animation helpers, constants) | Files listed in CONTEXT.md `<code_context>` "Files to port verbatim per BOOT-08". Phase 1 lands them as source files; Phases 2-4 import them. GOSL header check (BOOT-02) immediately validates them |
| AUDIT-01 | `DEPENDENCIES.md` lists every direct dependency (name, pinned version, license, telemetry audit, transitive license summary, maintenance signal, platform compatibility, audit date) | Format defined by parent `tool/check_dependencies_md.dart` parser: pipe-table rows under `## Direct dependencies` / `## Dev dependencies` / `## Transitive dependencies` headers, with `\| Package \| Version \| License \| Source \| ...` columns. Reference parent `DEPENDENCIES.md` for column conventions |
| AUDIT-02 | CI fails build on non-allowlisted license | Port `tool/check_licenses.dart` verbatim (allowlist already matches CONTEXT.md: MIT, BSD-2/3, Apache-2.0, ISC, zlib, CC0, Unlicense). Includes the `MPL-2.0-Linux-only` synthetic SPDX for Linux-only transitives if/when they appear |
| AUDIT-03 | Zero packages perform automatic network egress on app launch | Manual audit during DEPENDENCIES.md drafting. STACK.md §Detailed package audit confirms each direct dep is clean. Captured per-package in the "telemetry audit" column |
| CI-01 | GitHub Actions on every push to `main` runs three jobs | STACK.md §CI provides the exact YAML; matches parent `ci.yml` structure (gates → android + ios in parallel) |
| CI-02 | Lint job runs `flutter analyze`, `dart format`, `flutter test` | STACK.md §CI workflow `lint` job — exact steps |
| CI-03 | Build-android job produces debug APK as workflow artifact | STACK.md §CI `build-android` job; parent uses JDK 21 (`temurin`); per parent ci.yml line 224-227 the JDK 17 → 21 bump was forced by `maplibre_gl` — POC doesn't use maplibre_gl, so JDK 17 is technically sufficient, but JDK 21 is what the parent runs and pinning to it removes a "what if JDK 17 stops being default" surprise |
| CI-04 | Build-ios job produces unsigned IPA via `macos-latest` (or pinned macos image) | STACK.md §CI `build-ios` job. **Verification action below**: parent uses `macos-26` (forced by `device_info_plus 12.4.0`'s iOS 26.1 SDK requirement); POC has no `device_info_plus`, so `macos-latest` is acceptable. Recommended: pin `macos-14` for reproducibility (Xcode 16, iOS 18 SDK — sufficient for our deps) |
| CI-05 | Both APK and IPA artifacts visible from Actions run page on every push | `actions/upload-artifact@v4` with `if-no-files-found: error` per parent ci.yml — surfaces an empty-artifact regression as a build failure rather than a silent "artifact missing" |
| AUTH-01 | App shows permission rationale screen on launch | `PermissionGateScreen` is the `/` route. Material icon + 2-sentence paragraph + single CTA per CONTEXT.md decisions |
| AUTH-02 | On rationale acceptance, requests `Permission.locationWhenInUse` via `permission_handler` | `permission_handler 12.0.1` already in pubspec; STACK.md §5 confirms iOS 12+ support |
| AUTH-03 | On grant, navigates to `/map` via `context.go('/map')` | `go_router 16.0.0`; STACK.md §11 confirms parent's exact pin |
| AUTH-04 | On deny, shows denied screen with "Open Settings" button calling `permission_handler.openAppSettings()` | CONTEXT.md `Denied screen` decision; no "Try Again" button per iOS-cache UX rationale |
| AUTH-05 | `Info.plist` contains `NSLocationWhenInUseUsageDescription` (French) and NO `NSLocationAlwaysAndWhenInUseUsageDescription` | STACK.md §iOS sideload toolchain notes - "Required Info.plist keys" + "Do NOT add" lists |
| AUTH-06 | `Info.plist` contains `ITSAppUsesNonExemptEncryption=false` | Standard sideload requirement; STACK.md §iOS sideload + Apple submission guidance |
| LOG-01 | Logger writes to `<app_documents_dir>/logs/{filename}.txt`, one file per session | Port `FileLogger` from parent (`C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\logging\file_logger.dart`). Adapt filename to UTC ISO-8601 basic |
| LOG-02 | Log level = `Level.ALL` (verbose); each line timestamped to ms precision | Adapt parent: replace the `--dart-define=DEBUG` + SharedPreferences toggle logic with a hardcoded `Logger.root.level = Level.ALL`. Removes `shared_preferences` dep entirely. Parent already writes `rec.time.toIso8601String()` (ms precision) into the JSONL `ts` field |
| LOG-03 | Logger initialised before any other module that might log | `await FileLogger.bootstrap()` in `main()` before `WidgetsBinding.instance.addObserver(...)` and before `runApp()`. Pattern from parent main.dart bootstrap; CONTEXT.md `<integration_points>` "main.dart" |
| LOG-04 | Share button visible from any screen — app-bar action via `share_plus 12.0.2` | `buildPocAppBar()` shared helper in `lib/presentation/widgets/poc_app_bar.dart` per CONTEXT.md `<integration_points>` "AppBar reuse". Each Scaffold passes its own title |
| LOG-05 | Share sheet works on SideStore-sideloaded iOS build with iOS Mail (Phase 1 smoke test) | UAT softened per CONTEXT.md `Phase 1 UAT exit gate` decision. Planner must update REQUIREMENTS.md LOG-05 wording during Phase 1 to drop the "50 MB synthetic-log" specification (an action the planner must include in a task) |
| PERF-01 | On-screen FPS counter overlay; rolling 1-s average; ProMotion-aware refresh-rate display | `WidgetsBinding.instance.addPersistentFrameCallback` accumulates frame timings; `~250 ms` display tick recomputes the rolling average; refresh rate via `WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate`. Display format: `60 fps / 120 Hz` per CONTEXT.md `FPS counter` decision |
</phase_requirements>

## Standard Stack

### Core (Phase 1 active dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Flutter SDK | 3.41.8 (or 3.41.7) | Toolchain | STACK.md §1 — latest stable in 3.41.x line. **VERIFICATION ACTION (planner)**: parent ci.yml uses `3.41.7`; STACK.md prescribes `3.41.8`. Pick one; lock both `pubspec.yaml` (`environment.flutter`) and CI workflow (`subosito/flutter-action@v2 with: flutter-version`). Recommendation: **3.41.7** (matches parent exactly — code-donor mandate makes "matches parent" win over "latest hotfix") |
| Dart SDK | 3.11.x | Bundled with Flutter | Pin range `>=3.11.0 <4.0.0` in `pubspec.yaml` |
| flutter_localizations | SDK | Bilingual fr/en (CONTEXT.md decision) | BSD-3, no telemetry. Generated `AppLocalizations` accessor via `flutter gen-l10n` from `lib/l10n/*.arb` files |
| permission_handler | 12.0.1 | Location whenInUse request + openAppSettings | STACK.md §5; matches parent pin |
| geolocator | 14.0.2 | Declared but NOT wired in Phase 1 (Phase 2 wires it) | CONTEXT.md `<integration_points>`: declaring it now keeps `Info.plist` Privacy Manifest stable across phases |
| path_provider | 2.1.5 | `getApplicationDocumentsDirectory()` for log files | STACK.md §8; Flutter Favorite |
| path | 1.9.1 | `p.join()` cross-platform path construction (CLAUDE.md mandate) | STACK.md §9 |
| logging | 1.3.0 | Hierarchical logger feeding the file sink | STACK.md §7 |
| share_plus | 12.0.2 | Share gzipped log file via iOS share sheet | STACK.md §10; pin **12.0.2 not 13.x** to match parent (avoids `win32` transitive churn) |
| go_router | 16.0.0 | Three routes: `/`, `/map`, `/denied` | STACK.md §11; matches parent |

### Phase 1 also declares (for stable Privacy Manifest + future audits)

| Library | Version | Purpose |
|---------|---------|---------|
| cupertino_icons | 1.0.9 | Default Flutter template icon pack |
| flutter_map | 7.0.2 | Phase 2+; declare now per CONTEXT.md |
| vector_map_tiles | 8.0.0 | Phase 2+ |
| vector_map_tiles_pmtiles | 1.5.0 | Phase 2+ |
| vector_tile_renderer | 5.2.0 | Promoted transitive (CLAUDE.md "every dep pinned" rule) |
| pmtiles | 1.2.0 | Promoted transitive |
| latlong2 | 0.9.1 | Promoted transitive of flutter_map |

### Dev dependencies

| Library | Version | Purpose |
|---------|---------|---------|
| flutter_test | SDK | Unit + widget tests |
| flutter_lints | 6.0.0 | Lint baseline (parent-matching) |
| yaml | 3.1.3 | Required by `tool/check_licenses.dart` + `tool/check_dependencies_md.dart` |

### NOT included (parent has, POC explicitly drops)

- `shared_preferences` — POC is always-verbose, so the parent's verbose-toggle plumbing is removed (CONTEXT.md `<code_context>` adaptation #3)
- `flutter_riverpod` / `riverpod_*` / `custom_lint` — STACK.md §State management: plain `setState` for a 3-screen POC
- `drift` / `drift_flutter` / `sqlite3_flutter_libs` — no DB
- `freezed*` / `json_serializable` / codegen — no serialized models
- `flutter_local_notifications` — no notifications surface
- `device_info_plus` — drops the `macos-26` CI requirement (we can use `macos-14` or `macos-latest`)
- `image_picker`, `file_picker`, `crypto`, `flutter_dotenv` — none needed
- `maplibre_gl` — architecturally excluded (the POC's whole point is to escape it)

### Installation

```bash
flutter pub get
# Validate license + dependency table tooling
dart run tool/check_licenses.dart
dart run tool/check_dependencies_md.dart
dart run tool/check_headers.dart
```

## Architecture Patterns

### Recommended Project Structure

```
mirk-poc-debug/
├── .github/workflows/ci.yml              # Three-job CI (gates → android+ios parallel)
├── analysis_options.yaml                 # Strict mode + use_build_context_synchronously
├── pubspec.yaml                          # All deps strict-pinned
├── pubspec.lock                          # Committed
├── DEPENDENCIES.md                       # Per-dep audit rows (CI-checked)
├── LICENSE                               # GOSL v1.0 text
├── l10n.yaml                             # gen-l10n config
├── assets/
│   ├── maps/Fra_Melun.pmtile             # BOOT-07 (declared as asset)
│   └── shaders/atmospheric_fog.frag      # BOOT-08 (declared, unused in Phase 1)
├── ios/Runner/
│   ├── Info.plist                        # NSLocationWhenInUseUsageDescription (FR), ITSAppUsesNonExemptEncryption=false
│   └── PrivacyInfo.xcprivacy             # path_provider + share_plus Required Reason API
├── lib/
│   ├── main.dart                         # bootstrap → runZonedGuarded → runApp
│   ├── l10n/
│   │   ├── app_en.arb
│   │   └── app_fr.arb
│   ├── config/
│   │   └── constants.dart                # kMaxLogsDirBytes, kMirkFog*, kMetersPerDegreeLat, kEarthRadiusMeters
│   ├── infrastructure/
│   │   ├── logging/
│   │   │   ├── file_logger.dart          # PORT VERBATIM + 3 adaptations
│   │   │   └── file_logger_lifecycle_observer.dart  # PORT VERBATIM
│   │   └── mirk/                         # BOOT-08 dormant donor files
│   │       ├── sdf/revealed_sdf_builder.dart
│   │       ├── tile_cell_iteration.dart
│   │       ├── mirk_projection.dart
│   │       ├── shader/fog_shader_uniforms.dart
│   │       └── animation_helpers.dart
│   ├── domain/                           # BOOT-08 dormant donor files
│   │   ├── revealed/reveal_disc.dart
│   │   └── mirk/mirk_viewport_bbox.dart
│   ├── presentation/
│   │   ├── router.dart                   # go_router with 3 routes
│   │   ├── widgets/
│   │   │   ├── poc_app_bar.dart          # buildPocAppBar() shared helper
│   │   │   └── fps_counter_overlay.dart  # always-on top-right overlay
│   │   └── screens/
│   │       ├── permission_gate_screen.dart
│   │       ├── permission_denied_screen.dart
│   │       └── map_screen.dart           # PLACEHOLDER (dark grey body)
│   └── application/
│       └── permission_lifecycle_observer.dart  # AppLifecycleState.resumed → re-check + auto-nav
├── test/
│   ├── infrastructure/logging/
│   │   ├── file_logger_test.dart
│   │   ├── file_logger_lifecycle_observer_test.dart
│   │   └── file_logger_filename_format_test.dart
│   ├── presentation/
│   │   ├── widgets/fps_counter_overlay_test.dart
│   │   └── widgets/poc_app_bar_test.dart
│   └── tooling/
│       └── (parent's tool/test/* port — see Wave 0)
└── tool/
    ├── check_headers.dart                # PORT VERBATIM
    ├── check_licenses.dart               # PORT VERBATIM
    ├── check_dependencies_md.dart        # PORT VERBATIM
    └── test/
        ├── check_headers_test.dart
        ├── check_licenses_test.dart
        └── check_dependencies_md_test.dart
```

### Pattern 1: main.dart bootstrap with top-level error handler

**What:** Single bootstrap call before `runApp` ensures the FileLogger captures any failure during initialisation, including its own.
**When to use:** Phase 1 wiring, never modified afterwards (Phase 2-5 only swap `MirkPocApp`'s child tree).

```dart
// Source: parent C:\claude_checkouts\GOSL-MirkFall\lib\main.dart pattern + CLAUDE.md §Error handling
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'infrastructure/logging/file_logger.dart';
import 'infrastructure/logging/file_logger_lifecycle_observer.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FileLogger.bootstrap(); // MUST be awaited; LOG-03
  WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver());

  // CLAUDE.md top-level error handler — bugs propagate here.
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

### Pattern 2: FileLogger port-verbatim with 3 adaptations

**What:** Synchronous JSON-Lines file sink with `RandomAccessFile` + `flushSync` per record.
**Source:** `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\logging\file_logger.dart` (296 lines, fully self-contained).

**The three POC adaptations** (CONTEXT.md `<code_context>` Reusable Assets):

1. Replace `_formatFilenameTimestamp` body to emit UTC ISO-8601 basic:
   ```dart
   static String _formatFilenameTimestamp(DateTime dt) {
     final u = dt.toUtc();
     String pad(int n, int w) => n.toString().padLeft(w, '0');
     return '${pad(u.year, _yearWidth)}${pad(u.month, _calendarComponentWidth)}${pad(u.day, _calendarComponentWidth)}'
         'T${pad(u.hour, _calendarComponentWidth)}${pad(u.minute, _calendarComponentWidth)}${pad(u.second, _calendarComponentWidth)}Z';
   }
   ```
2. Replace verbose-decision logic in `bootstrap()`:
   ```dart
   // BEFORE (parent):
   //   const debugDefine = bool.fromEnvironment('DEBUG');
   //   final prefs = await SharedPreferences.getInstance();
   //   final verboseFromPrefs = prefs.getBool(kDebugLoggingPrefsKey) ?? false;
   //   Logger.root.level = (debugDefine || verboseFromPrefs) ? Level.ALL : Level.INFO;
   // AFTER (POC):
   Logger.root.level = Level.ALL; // LOG-02
   ```
3. Delete: `kDebugLoggingPrefsKey`, `toggleVerbosePref`, `writeVerbosePref`, `readVerbosePref`. Remove `import 'package:shared_preferences/shared_preferences.dart';`.

**Everything else is verbatim**, including:
- `RandomAccessFile` opened in `FileMode.writeOnlyAppend` with `writeStringSync` + `flushSync` per record
- Synchronous `_onRecord` (NOT async — `Stream.listen` doesn't await)
- `FileSystemException` catch nulls `_raf` to avoid infinite loop in zone error handler
- `_pruneToSizeLimit` at bootstrap until directory < `kMaxLogsDirBytes` (10 MB)
- `listLogFiles` sorted by `FileStat.modified` (not filename) for forward-compat with the new filename format
- Idempotent bootstrap: closes `_raf` + cancels `_subscription` before opening new file
- First record after bootstrap captures `activeFilename` so a reader can verify path identity (iOS sandbox UUID shifts)
- `flush()` no-op safeguard kept for call-site stability

`FileLoggerLifecycleObserver` — port verbatim from `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\logging\file_logger_lifecycle_observer.dart` (49 lines). No adaptations needed.

### Pattern 3: PermissionGateScreen + lifecycle resume re-check

**What:** Single screen that:
1. On `initState`: reads current `Permission.locationWhenInUse.status`. If already granted, navigates to `/map` immediately (covers re-launches after grant).
2. Renders rationale UI (icon + paragraph + CTA button) for non-granted state.
3. On CTA tap: calls `Permission.locationWhenInUse.request()`; on grant → `context.go('/map')`; on deny/permanentlyDenied → `context.go('/denied')`.
4. Subscribes to `WidgetsBindingObserver.didChangeAppLifecycleState`; on `resumed` re-checks status and auto-navigates to `/map` if granted.

**When to use:** This is the `/` route — every cold launch passes through it.

**Critical detail (Pitfall 15):** every `await Permission.locationWhenInUse.request()` and every `await Permission.locationWhenInUse.status` MUST be followed by `if (!context.mounted) return;` before any `context.go(...)` or `setState(...)`. Lint rule `use_build_context_synchronously: error` in `analysis_options.yaml` catches misses.

```dart
// Source: synthesized from CONTEXT.md decisions; no direct parent equivalent (parent uses different permission flow)
class _PermissionGateScreenState extends State<PermissionGateScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkAndMaybeNavigate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkAndMaybeNavigate());
    }
  }

  Future<void> _checkAndMaybeNavigate() async {
    final status = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    if (status.isGranted) {
      context.go('/map');
    }
  }

  Future<void> _onCtaPressed() async {
    final result = await Permission.locationWhenInUse.request();
    if (!mounted) return;
    if (result.isGranted) {
      context.go('/map');
    } else {
      context.go('/denied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: buildPocAppBar(context, title: l10n.appTitle),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_outlined, size: 64),
                  const SizedBox(height: 24),
                  Text(l10n.permissionRationaleParagraph, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _onCtaPressed, child: Text(l10n.permissionRationaleCta)),
                ],
              ),
            ),
          ),
          const Positioned(top: 8, right: 8, child: FpsCounterOverlay()),
        ],
      ),
    );
  }
}
```

### Pattern 4: FPS counter via `addPersistentFrameCallback`

**What:** Stateful widget that tallies frame durations between callbacks; recomputes the rolling 1-s average every ~250 ms; renders `"$fps fps / $refreshRate Hz"` text in a small chip.

**Why ProMotion-aware** (Pitfall 14): a bare "32 fps" reading is meaningless on a 120 Hz display where the OS expects 120 fps. The slash-Hz suffix shows the gap.

**Refresh rate source:**
```dart
// Flutter 3.41 API
final view = WidgetsBinding.instance.platformDispatcher.views.first;
final refreshRate = view.display.refreshRate; // double, Hz
```

**Sketch:**
```dart
class _FpsCounterOverlayState extends State<FpsCounterOverlay> {
  final List<Duration> _frameTimes = <Duration>[];
  Duration? _lastFrameStamp;
  Timer? _recomputeTimer;
  double _displayedFps = 0;
  double _refreshRate = 60;

  @override
  void initState() {
    super.initState();
    _refreshRate = WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate;
    WidgetsBinding.instance.addPersistentFrameCallback(_onFrame);
    _recomputeTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _recompute());
  }

  void _onFrame(Duration timestamp) {
    if (_lastFrameStamp != null) {
      _frameTimes.add(timestamp - _lastFrameStamp!);
      // Drop frames older than 1 s.
      final cutoff = timestamp - const Duration(seconds: 1);
      _frameTimes.removeWhere((d) => (timestamp - d) < Duration.zero);
      // Simpler: keep last N frames where N ~= refreshRate
    }
    _lastFrameStamp = timestamp;
  }

  void _recompute() {
    if (_frameTimes.isEmpty) return;
    final avgMicros = _frameTimes.fold<int>(0, (a, b) => a + b.inMicroseconds) / _frameTimes.length;
    setState(() => _displayedFps = avgMicros == 0 ? 0 : 1e6 / avgMicros);
  }

  @override
  void dispose() {
    _recomputeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${_displayedFps.toStringAsFixed(0)} fps / ${_refreshRate.toStringAsFixed(0)} Hz',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}
```

The exact rolling-window math is Claude's discretion per CONTEXT.md.

### Pattern 5: Share-logs button (gzip + share_plus)

**What:** AppBar action that gzips the active log file in-memory, writes to a temp `.gz`, and invokes `share_plus.shareXFiles`.

**Why gzip:** Pitfall 11 — iOS Mail attachment caps (~20-25 MB depending on provider). 10 MB ASCII JSONL compresses to ~600 KB.

```dart
// In poc_app_bar.dart
Future<void> _onSharePressed(BuildContext context) async {
  final activeFilename = FileLogger.activeFilename;
  if (activeFilename == null) {
    Logger('share').warning('Share invoked but FileLogger has no active file');
    return;
  }
  final logFile = File(activeFilename);
  if (!await logFile.exists()) return;
  final bytes = await logFile.readAsBytes();
  final gzipped = GZipCodec().encode(bytes);
  final tmpDir = await getTemporaryDirectory();
  final basename = p.basenameWithoutExtension(activeFilename);
  final outFilename = p.join(tmpDir.path, '$basename.txt.gz');
  await File(outFilename).writeAsBytes(gzipped, flush: true);
  if (!context.mounted) return;
  await Share.shareXFiles([XFile(outFilename, mimeType: 'application/gzip')]);
}
```

`GZipCodec` is in `dart:io`; `Share.shareXFiles` is `share_plus 12.0.2`'s API.

### Pattern 6: Bilingual via `flutter_localizations` + `gen-l10n`

**What:** ARB files in `lib/l10n/`; `flutter gen-l10n` produces `AppLocalizations` accessor. Locale follows device with French fallback.

**Setup:**
```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_fr.arb
output-localization-file: app_localizations.dart
```

```dart
// lib/main.dart inside MaterialApp.router(...)
MaterialApp.router(
  routerConfig: appRouter,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  // Default fallback = French (developer in Melun); Flutter picks system locale automatically.
  localeResolutionCallback: (locale, supported) {
    if (locale != null && supported.any((l) => l.languageCode == locale.languageCode)) {
      return locale;
    }
    return const Locale('fr');
  },
  ...
)
```

ARB content example:
```json
// lib/l10n/app_fr.arb
{
  "@@locale": "fr",
  "appTitle": "MirkFall POC",
  "permissionRationaleParagraph": "MirkFall a besoin de ta position pour révéler le brouillard de ta carte. Tout reste sur ton téléphone — aucun envoi.",
  "permissionRationaleCta": "Autoriser la position",
  "permissionDeniedParagraph": "Sans autorisation, MirkFall ne peut pas révéler la carte. Ouvre les Réglages pour l'activer.",
  "permissionDeniedOpenSettings": "Ouvrir les Réglages",
  "shareLogsTooltip": "Partager les logs"
}
```

### Pattern 7: Three-job CI workflow

**Source:** `C:\claude_checkouts\GOSL-MirkFall\.github\workflows\ci.yml` adapted for the POC's smaller surface.

**Adaptations from parent:**
- Drop SQLite install (no Drift)
- Drop `check_domain_purity`, `check_avoid_maplibre_leak`, `check_avoid_remote_pmtiles`, `check_style_no_external_url`, `check_mirk_variant_file_count`, `check_platform_manifests` (all out-of-scope for POC). Keep `check_headers`, `check_licenses`, `check_dependencies_md`
- Drop drift schema gate
- Drop `Plain-Dart domain + infra tests` step (POC has no pure-Dart-only test directories)
- Drop `Flutter test with DEBUG define` step (POC is always-verbose; no DEBUG define behaviour to test)
- Use `macos-latest` (or pin `macos-14`) instead of parent's `macos-26` (POC has no `device_info_plus` forcing iOS 26.1 SDK)
- Use `flutter-version: '3.41.7'` to match parent (or `3.41.8` per STACK.md — pick one)
- JDK 21 still recommended (forward-compat with future deps; cost is negligible)

**Final POC ci.yml shape:**
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  gates:
    name: Lint / Licence / Headers / Deps
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.7'
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart format --line-length 160 --set-exit-if-changed .
      - run: flutter analyze --fatal-infos --fatal-warnings
      - run: dart run tool/check_headers.dart
      - run: dart run tool/check_licenses.dart
      - run: dart run tool/check_dependencies_md.dart
      - run: dart test tool/test/
      - run: flutter test

  android:
    name: Build Android APK (debug)
    needs: gates
    runs-on: ubuntu-latest
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '21' }
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.7'
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter build apk --debug
      - uses: actions/upload-artifact@v4
        with:
          name: mirk-poc-debug-android-debug-apk
          path: build/app/outputs/flutter-apk/app-debug.apk
          if-no-files-found: error
          retention-days: 14

  ios:
    name: Build iOS (no-codesign, sideloadable)
    needs: gates
    runs-on: macos-14
    timeout-minutes: 35
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.7'
          channel: stable
          cache: true
      - run: flutter pub get
      - name: Remove placeholder Podfile.lock (Windows-dev bootstrap)
        working-directory: ios
        run: |
          if [ -f Podfile.lock ] && ! grep -q "^COCOAPODS:" Podfile.lock; then
            echo "::warning::Placeholder Podfile.lock detected — removing before pod install"
            rm -f Podfile.lock
          fi
      - name: CocoaPods install
        working-directory: ios
        run: pod install
      - name: Build iOS (no-codesign)
        run: flutter build ios --release --no-codesign
      - name: Package unsigned IPA for sideloading
        run: |
          set -euo pipefail
          BUILD_DIR="build/ios/iphoneos"
          if [ ! -d "$BUILD_DIR/Runner.app" ]; then
            echo "::error::Expected Runner.app under $BUILD_DIR after flutter build ios"
            exit 1
          fi
          WORK_DIR="$(mktemp -d)"
          mkdir "$WORK_DIR/Payload"
          cp -R "$BUILD_DIR/Runner.app" "$WORK_DIR/Payload/"
          (cd "$WORK_DIR" && zip -qr "$GITHUB_WORKSPACE/mirk-poc-debug-unsigned.ipa" Payload)
      - uses: actions/upload-artifact@v4
        with:
          name: mirk-poc-debug-ios-unsigned-ipa
          path: mirk-poc-debug-unsigned.ipa
          if-no-files-found: error
          retention-days: 14
```

**Concurrency block** is important — multiple rapid pushes on `main` cancel older runs (saves macos-14 minutes, which are 10× ubuntu cost).

**`if-no-files-found: error`** on artifact uploads — surfaces an empty-artifact regression as a build failure rather than silent "artifact missing."

### Pattern 8: PrivacyInfo.xcprivacy + Info.plist

**PrivacyInfo.xcprivacy** — parent project does NOT currently have one (verified absent from `C:\claude_checkouts\GOSL-MirkFall\ios\Runner\`). STACK.md §iOS sideload toolchain notes prescribes one for `path_provider` + `share_plus` Required Reason API declarations.

**Action for planner:** because the parent file does NOT exist (CONTEXT.md said "copy verbatim from parent" — this was incorrect), the planner must instruct the executor to author one from scratch. Required keys per Apple's Required Reason API documentation:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <!-- path_provider transitively accesses NSFileManager creation/modification timestamps -->
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
        <!-- share_plus may use UserDefaults via UIActivityViewController -->
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
</dict>
</plist>
```

**Info.plist** — POC-specific (drop parent's `NSLocationAlways`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `UIBackgroundModes`):

```xml
<key>CFBundleDisplayName</key>           <string>MirkFall POC</string>
<key>NSLocationWhenInUseUsageDescription</key>
    <string>MirkFall POC utilise ta position pour révéler le brouillard de ta carte d'exploration. Tout reste sur ton téléphone.</string>
<key>ITSAppUsesNonExemptEncryption</key> <false/>
<key>UILaunchStoryboardName</key>        <string>LaunchScreen</string>
<key>UIRequiresFullScreen</key>          <true/>
<key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
```

**Do NOT copy from parent** (parent has these but POC must not):
- `NSLocationAlwaysAndWhenInUseUsageDescription` (out of POC scope)
- `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` (parent has TODO placeholders for Phase 11; POC doesn't reach that)
- `UIBackgroundModes` with `location` / `fetch` (Phase 1 doesn't need background; Phase 2+ might)
- `CADisableMinimumFrameDurationOnPhone` is OPTIONAL for POC; recommended set to `true` so ProMotion can drive 120 Hz (otherwise iOS caps Flutter at 60 Hz on non-Apple-team apps). Sources confirm this is a public Info.plist key, not entitlement-gated.

### Anti-Patterns to Avoid

- **Don't write to `getApplicationDocumentsDirectory()` for general data**: parent uses Documents for logs intentionally (LOG-01 requirement). For other binary blobs (PMTiles cache in Phase 2), use `getApplicationSupportDirectory()` (sandboxed, not iCloud-backed). Pitfall 4 references this.
- **Don't use `IOSink` for the file logger**: parent's documented production-fatal bug. Use `RandomAccessFile` + `flushSync` per record.
- **Don't make `_onRecord` async**: `Stream.listen` doesn't await async callbacks → race → `StateError: StreamSink is bound` → ~99% records lost.
- **Don't use `'/'` string concatenation for paths**: CLAUDE.md mandates `p.join()` everywhere.
- **Don't add `^` to any pubspec dependency**: every direct dep strict-pinned. Parent CLAUDE.md rule.
- **Don't navigate via `context.push()` in Phase 1 flows**: every transition is `context.go()` per CONTEXT.md (full pile reset; no back navigation).
- **Don't catch generic `Exception` in `_onRecord`**: catch only `FileSystemException` (parent comment: avoid infinite loop in zone error handler).
- **Don't add `print()` statements**: lint rule `avoid_print: true` catches these. Use `Logger`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File logging with iOS durability | A custom `IOSink`-based sink | Port parent's `FileLogger` verbatim | Parent's logger is the result of debugging two production-fatal iOS issues (jetsam page-cache loss + `Stream.listen` re-entrancy). Re-deriving will hit the same bugs |
| GOSL header check | A bash/grep loop | Port `tool/check_headers.dart` verbatim | Already handles codegen exclusions, `--help`, exit codes 0/1/2, integration_test/ root, paired tests in tool/test/ |
| License audit gate in CI | `dart_license_checker` | Port `tool/check_licenses.dart` verbatim | Parent's tool has belt-and-braces forbidden-substring scan, manual override system for Linux-only MPL-2.0 transitives, compound SPDX (AND/WITH/OR) handling, placeholder license detection, `LicenseRef-*` escape hatch — comprehensively battle-tested |
| DEPENDENCIES.md freshness | Manual review | Port `tool/check_dependencies_md.dart` verbatim | Already cross-references pubspec.lock against the markdown table parser; section-header aware (won't false-positive on Tooling/CI tables); robust against markdown-lint reflow |
| iOS unsigned IPA packaging | A standalone bash script | Use the parent's CI step (zip Payload/Runner.app) | Already handles missing-file detection, mktemp-based safe workspace, `set -euo pipefail` |
| Permission handling | Hand-rolled `MethodChannel` to `CLLocationManager` | `permission_handler 12.0.1` | Already abstracts iOS/Android; tested by Baseflow; matches parent pin |
| Share sheet | Hand-rolled `MethodChannel` to `UIActivityViewController` | `share_plus 12.0.2` | Same — fluttercommunity.dev, tested |
| Routing | Manual `Navigator` push/pop with `WillPopScope` | `go_router 16.0.0` | Mandated by CLAUDE.md; matches parent |
| Localization | Hand-rolled string maps | `flutter_localizations` + `flutter gen-l10n` | SDK package, BSD-3, no telemetry, generates type-safe `AppLocalizations` accessor |
| Gzip the log file | `package:archive` | `dart:io` `GZipCodec` | Stdlib; no extra dep; sufficient for single-file gzip |
| FPS measurement | A custom render loop with `Stopwatch` | `WidgetsBinding.instance.addPersistentFrameCallback` | Already provides per-frame `Duration` timestamp; this is the documented Flutter API |
| Refresh rate detection | Hardcoded 60 / probing assumption | `WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate` | Pitfall 14 — ProMotion-aware mandatory |

**Key insight:** Phase 1 has zero novel infrastructure. Everything is either a port from parent or a one-line wiring of an existing well-known package. The only "design" work is the placeholder map screen body (a `ColoredBox`) and the bilingual ARB strings.

## Common Pitfalls

(Drawn from `research/PITFALLS.md`; the planner should make these explicit task-verification steps.)

### Pitfall A: Logger filename divergence vs. parent project

**What goes wrong:** Parent uses `yyyymmdd_hhmm.ss_logs.txt` (local time, with a `.` between minute and second — quirky). POC uses `yyyymmddTHHMMSSZ_logs.txt` (UTC ISO-8601 basic, no `.`). A future developer copying parent's `listLogFiles` or the parent's regex-based filename parser will silently break.

**Why it happens:** Filename format is the kind of thing that "works on my machine" until midnight crosses (Pitfall 19) or until a different consumer parses the name.

**How to avoid:**
- Centralise filename construction in `_formatFilenameTimestamp` (single source of truth).
- `listLogFiles` already sorts by `FileStat.modified`, NOT filename — port verbatim, do NOT change to filename-sort even if the new format would sort correctly alphabetically.
- Add a unit test asserting `_formatFilenameTimestamp(DateTime.utc(2026, 4, 30, 14, 25, 3)) == '20260430T142503Z'`.

**Warning signs:**
- Files appearing with both old + new naming on a single device.
- Share button shares a stale file because the listing parser confused the format.

### Pitfall B: BuildContext after await across permission flow

**What goes wrong:** Per CLAUDE.md §Async / BuildContext: every `await` in a widget MUST be followed by `if (!context.mounted) return;` before any further `BuildContext` use. Phase 1 has at least three such points:
1. `Permission.locationWhenInUse.status` (in `initState` chain + on resume)
2. `Permission.locationWhenInUse.request()` (on CTA tap)
3. `Share.shareXFiles(...)` (on share button tap, awaits user picker dismissal)

Missing `mounted` check → "Looking up a deactivated widget's ancestor" crash on rapid background → restore.

**How to avoid:**
- `analysis_options.yaml`: `errors: { use_build_context_synchronously: error }` — promotes from warning to error.
- Code review every PR for the pattern (CLAUDE.md mandate).
- Pre-commit: `flutter analyze --fatal-infos --fatal-warnings` (already in CI gates).

**Warning signs:**
- iOS walk: app crashes on backgrounding mid-permission-flow.
- Stack trace contains "Looking up a deactivated widget's ancestor."

### Pitfall C: SideStore 7-day re-sign + 3-app limit confounds the test loop

**What goes wrong:** Free Apple ID + SideStore caps: 3 apps installed simultaneously, signed for 7 days, 10 distinct App IDs/week. The developer's iPhone might already have parent-MirkFall + another app installed → can't add the POC.

**How to avoid:**
- Document the developer's current SideStore install count BEFORE Phase 1 starts. STATE.md already flags this as a blocker (line 76).
- Apply SideStore's "Disable App Limit" toggle per-install per Pitfall 9.
- Use stable bundle ID `com.thongvan.mirkpoc` (planner: name this in the iOS bundle config) so re-sideloads of the same IPA don't burn through the 10-AppID/week cap.
- Document the WireGuard / pairing-file setup in the repo's README so re-installs don't lose 30 minutes.

**Warning signs:**
- "SideStore can only install 3 apps including itself" at install time.
- App stops launching ("Untrusted Developer") 7 days after sideload — re-sign needed.

### Pitfall D: share_plus + iOS Mail behaviour on sideloaded build is unverified

**What goes wrong:** STACK.md §10 confirms `share_plus` itself works on sideloaded builds (`UIActivityViewController` is a system framework with no provisioning-profile requirement). But Pitfall 11 flags **byte-integrity through Mail's attachment pipeline as unverified at sideload-build scale**. The developer dropped the 50 MB synthetic-log smoke test (CONTEXT.md decision, "this is a POC, just log") so the only signal is the manual UAT walk: send the gzipped log via Mail, verify it arrived.

**How to avoid:**
- Phase 1 manual UAT: developer sideloads the IPA, taps share-logs, picks Mail, sends to themselves, verifies the email arrives with the gzipped attachment intact (file opens, contains JSONL records). This IS the LOG-05 gate per CONTEXT.md.
- Gzip before sharing — keeps the file small enough to dodge most Mail attachment caps.
- Log the file size BEFORE share (`Logger('share').info('Sharing logs: $bytes bytes gzipped')`) so the receiver-side check has a baseline.

**Warning signs:**
- Mail "the attachment is too large" error.
- Received attachment is truncated (size mismatch with the on-device file).
- Accented characters arrive garbled (UTF-8 encoding regression).

### Pitfall E: Hardcoded 60 fps assumption breaks on ProMotion

**What goes wrong:** Pitfall 14 — Pixel 4a is fixed 60 Hz, iPhone 17 Pro is ProMotion variable up to 120 Hz. A POC built assuming 60 Hz will mis-report FPS on ProMotion (looks janky at 60 fps when device wants 120) AND can hit 60 Hz cap because of `CADisableMinimumFrameDurationOnPhone`'s default behaviour.

**How to avoid:**
- FPS overlay reports BOTH measured fps AND device refresh rate per CONTEXT.md `60 fps / 120 Hz` format.
- Set `CADisableMinimumFrameDurationOnPhone=true` in Info.plist (parent does this, line 5-6) so the 120 Hz ceiling is unlocked.
- Never hardcode `Duration(milliseconds: 16)` — use per-frame dt.

**Warning signs:**
- iPhone 17 Pro walk reports `60 fps / 120 Hz` even when the placeholder map screen is static (should be 120/120).
- iPhone 17 Pro reports `30 fps / 120 Hz` and the user perceives jank — accurate.

### Pitfall F: `pub get` resolution differs between Windows-dev and CI Linux/macOS

**What goes wrong:** pubspec.lock committed (BOOT-01) — but if developer re-runs `flutter pub get` on Windows after a transitive change, the resolution might pick a different platform-specific lock entry than CI's Linux runner. CI then sees a "lockfile changed" diff or worse, picks up a different resolution.

**How to avoid:**
- Commit `pubspec.lock` after a clean `flutter pub get` on Windows (developer's primary host).
- CI does NOT regenerate the lockfile (`flutter pub get` reads it without touching it when it's valid).
- If a CI-detected dep mismatch happens, treat as bug — investigate the transitive that's platform-conditional.

**Warning signs:**
- CI reports `pubspec.lock` is dirty after `flutter pub get`.
- Linux-only or macOS-only transitive in lockfile is missing on Windows.

### Pitfall G: Donor BOOT-08 files import packages that aren't in Phase 1's pubspec

**What goes wrong:** The dormant donor files (e.g. `revealed_sdf_builder.dart`, `mirk_projection.dart`, `wisp_particle_system.dart` will land in Phase 4) likely `import 'package:flutter_map/flutter_map.dart';` or `import 'package:latlong2/latlong.dart';` to access `LatLng`. CONTEXT.md `<integration_points>` says these packages ARE declared in Phase 1's pubspec for stable Privacy Manifest. Good. But the donor files are likely also tightly coupled to parent's `MapView` abstraction layer which DOESN'T exist in the POC.

**How to avoid:**
- Phase 1 declares the donor files but does NOT export them from any library file or import them anywhere in `lib/main.dart` chain. They live as dormant source until Phase 2-4 wires them.
- `flutter analyze` may surface unused-import warnings on the dormant files. **Acceptable** — adding `// ignore: unused_element` is wrong; the files just aren't yet referenced by application code. Analyzer doesn't flag unused FILES, only unused declarations within files. Test by running `flutter analyze` once after porting them.
- If a donor file imports something the POC doesn't have (e.g. parent's `MapView` interface), the planner must call out the import-path adaptation in the porting task — adapt the import or stub the missing class. The first donor file ported should be the simplest (e.g. `reveal_disc.dart` — just a value class) to flush out adaptation patterns.

**Warning signs:**
- `flutter analyze` fails on the donor files with unresolved import errors.
- A donor file references a constant not yet ported into `lib/config/constants.dart`.

## Code Examples

(Verified patterns — sources cited inline. Most reference parent project files; URLs are file paths since this is local cross-repo work.)

### Example 1: Parent's `_pruneToSizeLimit` (port verbatim into POC FileLogger)

```dart
// Source: C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\logging\file_logger.dart lines 248-282
static Future<void> _pruneToSizeLimit(Directory logsDir) async {
  final files = <File>[];
  await for (final entity in logsDir.list()) {
    if (entity is File && entity.path.endsWith('_logs.txt')) {
      files.add(entity);
    }
  }
  // Sort oldest-first by mtime so we prune the right files regardless of the
  // filename format (symmetric with listLogFiles using FileStat.modified).
  final byMtime = <(File, int)>[];
  for (final f in files) {
    final s = await f.stat();
    byMtime.add((f, s.modified.millisecondsSinceEpoch));
  }
  byMtime.sort((a, b) => a.$2.compareTo(b.$2));

  int totalBytes = 0;
  final sizes = <int>[];
  for (final entry in byMtime) {
    final s = await entry.$1.length();
    sizes.add(s);
    totalBytes += s;
  }

  var i = 0;
  while (totalBytes > kMaxLogsDirBytes && i < byMtime.length) {
    try {
      await byMtime[i].$1.delete();
      totalBytes -= sizes[i];
    } on FileSystemException {
      // Skip unlinkable file, keep going. Rare edge case (Windows lock).
    }
    i++;
  }
}
```

### Example 2: Parent's synchronous `_onRecord` (port verbatim)

```dart
// Source: C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\logging\file_logger.dart lines 197-224
static void _onRecord(LogRecord rec) {
  final raf = _raf;
  if (raf == null) return;

  final entry = <String, Object?>{
    'ts': rec.time.toIso8601String(),
    'level': rec.level.name,
    'logger': rec.loggerName,
    'msg': rec.message,
    if (rec.error != null) 'error': rec.error.toString(),
    if (rec.stackTrace != null) 'stack': rec.stackTrace.toString(),
  };
  final line = '${jsonEncode(entry)}\n';

  // Catch only [FileSystemException] — the sync API does not raise [StateError].
  // On an I/O failure surface via dart:developer log() and null _raf so
  // subsequent records are silently dropped (avoid infinite loop in zone
  // error handler that would call Logger.shout → _onRecord → recurse).
  try {
    raf.writeStringSync(line);
    raf.flushSync();
  } on FileSystemException catch (e) {
    developer.log('FileLogger record write failed; nulling handle: $e', name: 'FileLogger');
    _raf = null;
  }
}
```

### Example 3: Parent's `FileLoggerLifecycleObserver` (port verbatim, no changes)

```dart
// Source: C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\logging\file_logger_lifecycle_observer.dart full file
class FileLoggerLifecycleObserver with WidgetsBindingObserver {
  FileLoggerLifecycleObserver() : _flushCallback = FileLogger.flush;

  @visibleForTesting
  FileLoggerLifecycleObserver.withFlush(Future<void> Function() flushCallback) : _flushCallback = flushCallback;

  final Future<void> Function() _flushCallback;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) return;
    unawaited(_flushCallback());
  }
}
```

### Example 4: go_router setup with three routes

```dart
// Source: synthesized from STACK.md §11 routing graph + CONTEXT.md decisions
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'permission-gate',
      builder: (context, state) => const PermissionGateScreen(),
    ),
    GoRoute(
      path: '/map',
      name: 'map',
      builder: (context, state) => const MapScreen(),
    ),
    GoRoute(
      path: '/denied',
      name: 'denied',
      builder: (context, state) => const PermissionDeniedScreen(),
    ),
  ],
);
```

All transitions: `context.go('/map')`, `context.go('/denied')` — no `context.push()` in Phase 1 (CONTEXT.md decision).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `IOSink` for file logging | `RandomAccessFile` + `flushSync` | Parent project's BUG-014-era investigation (early 2026) | iOS jetsam doesn't drop log records anymore |
| Async `_onRecord` callback | Synchronous `_onRecord` | Same investigation | Stops `StateError: StreamSink is bound` re-entrancy bug |
| `share_plus 13.x` (latest) | `share_plus 12.0.2` (pinned) | Parent decision late 2025 | Avoids `win32` transitive churn that bit `device_info_plus 13.0.0` |
| Hardcoded 60 fps assumption | `display.refreshRate` query | Flutter 3.27+ / iPhone 13 Pro+ widespread | ProMotion devices need this for honest perf reporting |
| Asset-resource PMTiles loading | Copy-to-`getApplicationSupportDirectory()` on first launch | `vector_map_tiles_pmtiles 1.5.0`'s file-path API constraint | Phase 2 concern, but `path_provider` already in Phase 1 pubspec |
| `vector_map_tiles 9.0.0-beta.8` | `vector_map_tiles 8.0.0` (pinned to flutter_map 7.0.2 chain) | STACK.md §Map renderer dependency chain analysis 2026-04-30 | POC stays on the only fully-resolvable stable chain |
| Per-package manual license audit | `tool/check_licenses.dart` CI gate | Parent project Phase 01 | Catches transitive license regressions on every push |

**Deprecated/outdated:**
- `dart_license_checker --show-transitive-dependencies` — usable but parent's hand-rolled `tool/check_licenses.dart` is more comprehensive (forbidden-substring scan, manual override system, compound SPDX handling). Use parent's tool.
- `print()` for diagnostics — `avoid_print: true` lint rule + `Logger` package replaces it.
- Parent's SharedPreferences-backed verbose toggle — POC drops it (always-verbose).

## Open Questions

1. **Flutter version pin: 3.41.7 (parent) vs 3.41.8 (STACK.md)?**
   - What we know: Both are valid 3.41.x stable hotfixes. Parent runs 3.41.7 in CI.
   - What's unclear: Is there a regression between 3.41.7 and 3.41.8 that affects the POC? (Almost certainly not — these are tiny hotfixes.)
   - Recommendation: **Lock to 3.41.7** for code-donor parity with parent. Easy bump later if needed. Update STACK.md's recommendation accordingly during Phase 1 planning.

2. **macOS runner image: `macos-latest` vs `macos-14`?**
   - What we know: Parent uses `macos-26` because of `device_info_plus 12.4.0`. POC has no `device_info_plus`.
   - What's unclear: Is `macos-latest` (which floats) acceptable, or pin a specific image for reproducibility?
   - Recommendation: **Pin `macos-14`** (Xcode 16, iOS 18 SDK). Sufficient for our deps, deterministic, won't float into a runner image where Apple removes Xcode support. Cheaper minutes than `macos-26` if cost ever matters.

3. **`InfoPlist.strings` for English `NSLocationWhenInUseUsageDescription`?**
   - What we know: CONTEXT.md says "French only is acceptable for v1" if iOS i18n adds friction.
   - What's unclear: How much friction is "InfoPlist.strings localization"?
   - Recommendation: **French only for Phase 1**. The string is shown in the iOS system permission prompt (a one-time UX moment); the rationale screen + denied screen + all in-app strings are bilingual via ARB. The cost of `InfoPlist.strings` is creating `ios/Runner/en.lproj/InfoPlist.strings` + `ios/Runner/fr.lproj/InfoPlist.strings` + setting `CFBundleLocalizations`. Worth the 10 minutes if the planner has slack; otherwise defer (already in CONTEXT.md `<deferred>`).

4. **Bundle identifier name: `com.thongvan.mirkpoc` vs other?**
   - What we know: Pitfall 9 advises a stable bundle ID for SideStore App-ID-cap hygiene. CONTEXT.md does not specify one.
   - What's unclear: User preference.
   - Recommendation: **Planner asks user** during Phase 1 planning. Suggested: `com.thongvan.mirkfall_poc` to clearly distinguish from parent (`com.thongvan.mirkfall` — verify parent actually uses this).

5. **`Fra_Melun.pmtile` source path verification**
   - What we know: PROJECT.md says the source is `C:\claude_checkouts\countries-pmtiles\Fra_Melun.pmtile`.
   - What's unclear: Is this file accessible to the executor, and is the 4 MB size correct?
   - Recommendation: **First Wave 0 task verifies file exists and copies it into `assets/maps/`**. If absent, surface as a blocker.

6. **ARB file column for `app_localizations.dart` codegen**
   - What we know: `flutter gen-l10n` reads `arb-dir`, `template-arb-file`, `output-localization-file` from `l10n.yaml`.
   - What's unclear: Where the generated file lands by default — `.dart_tool/flutter_gen/gen_l10n/` (synthetic package) or `lib/l10n/` (output-dir override).
   - Recommendation: **Use synthetic package** (default) — no codegen output committed; simpler. Set `synthetic-package: true` in `l10n.yaml`. Generated `AppLocalizations` is imported via `package:flutter_gen/gen_l10n/app_localizations.dart`.

## Validation Architecture

> Phase 1 sits at the intersection of "lots of automatable infrastructure" (lint, license, headers, dep tables, file-logger logic) and "validation can ONLY happen on a real iOS device" (sideload, share-to-Mail, FPS overlay legibility, permission flow on iOS specifically). The mix is unusual: ~70% of Phase 1 lines are testable; the LOG-05 gate is unambiguously manual.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (SDK-bundled — no extra dep) + `dart test` for tool/test/* (pure-Dart scripts) |
| Config file | None at Phase 1 (a `dart_test.yaml` is optional; not needed for the test surface) |
| Quick run command | `flutter test` |
| Full suite command | `flutter test && dart test tool/test/` |
| Tool tests separately | `dart test tool/test/` (pure-Dart, no Flutter binding) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BOOT-01 | pubspec strict-pinned, no `^`, lockfile present | unit (tool script) | `dart test tool/test/check_dependencies_md_test.dart` (verifies the parser; the strict-pinning rule is enforced via code review since pubspec contains semver but every entry is X.Y.Z form) — supplementary regex test on pubspec.yaml | Wave 0 (port from parent) |
| BOOT-02 | Every .dart file in lib/test starts with GOSL header | unit (tool script) | `dart test tool/test/check_headers_test.dart` and CI `dart run tool/check_headers.dart` | Wave 0 (port from parent) |
| BOOT-03 | LICENSE file at root contains GOSL v1.0 text | smoke (CI gate) | `test -f LICENSE && grep -q "Good Old Software License" LICENSE` (added as a CI step) | manual write |
| BOOT-04 | analysis_options.yaml strict mode | unit (Flutter analyzer) | `flutter analyze --fatal-infos --fatal-warnings` (CI step) | Wave 0 |
| BOOT-05 | dart format --line-length 160 passes | unit (CI step) | `dart format --line-length 160 --set-exit-if-changed .` | CI step (no test file) |
| BOOT-06 | flutter analyze passes | unit (CI step) | `flutter analyze` | CI step |
| BOOT-07 | Fra_Melun.pmtile bundled at assets/maps/ | smoke | `flutter test test/assets/asset_bundle_test.dart` (rootBundle.load returns ≈ 4 MB ByteData) | Wave 0 (new test file) |
| BOOT-08 | Donor files present, GOSL-headered, parse | unit | covered by `check_headers` + `flutter analyze` once files land | Wave 0 |
| AUDIT-01 | DEPENDENCIES.md row per direct dep | unit (tool script) | `dart test tool/test/check_dependencies_md_test.dart` + CI `dart run tool/check_dependencies_md.dart` | Wave 0 (port from parent) |
| AUDIT-02 | CI fails on non-allowlisted license | unit (tool script) | `dart test tool/test/check_licenses_test.dart` + CI `dart run tool/check_licenses.dart` | Wave 0 (port from parent) |
| AUDIT-03 | Zero auto network egress | manual-only | Audited per-package in DEPENDENCIES.md; cannot be unit-tested in Dart (would need network proxy on real iOS during walk). Review during Phase 1 doc review. | manual review |
| CI-01 | GitHub Actions runs three jobs on push to main | smoke (CI itself) | `gh run list --workflow=ci.yml --limit 1` after push shows three jobs | Wave 0 (workflow file) |
| CI-02 | Lint job runs analyze, format, test | unit (CI step) | Workflow YAML correctness; verify on first push | Wave 0 |
| CI-03 | Build-android produces APK artifact | smoke (CI artifact) | `gh run download $RUN_ID --name mirk-poc-debug-android-debug-apk` returns the APK | Wave 0 |
| CI-04 | Build-ios produces unsigned IPA artifact | smoke (CI artifact) | `gh run download $RUN_ID --name mirk-poc-debug-ios-unsigned-ipa` returns the IPA | Wave 0 |
| CI-05 | Both artifacts visible from run page | smoke (CI artifact) | `gh run view $RUN_ID --log` shows both artifact upload steps green | Wave 0 |
| AUTH-01 | Permission rationale screen on launch | widget | `flutter test test/presentation/screens/permission_gate_screen_test.dart` (renders, finds icon + paragraph + CTA) | Wave 0 (new test file) |
| AUTH-02 | CTA → request locationWhenInUse | widget | `permission_gate_screen_test.dart` with mocked `permission_handler` (use `PermissionHandlerPlatform.instance` override) — assert request invoked on tap | Wave 0 |
| AUTH-03 | On grant → context.go('/map') | widget | Same test file: mock grant response, assert router moves to '/map' | Wave 0 |
| AUTH-04 | On deny → /denied screen with "Open Settings" button | widget | `permission_denied_screen_test.dart` (renders + button calls `openAppSettings`) | Wave 0 |
| AUTH-05 | Info.plist contains correct keys | unit (tool script — port idea from parent's `check_platform_manifests.dart`) | A Phase-1 mini version: `dart test test/tooling/info_plist_keys_test.dart` (parses `ios/Runner/Info.plist`, asserts `NSLocationWhenInUseUsageDescription` present + non-empty, asserts `NSLocationAlwaysAndWhenInUseUsageDescription` ABSENT) | Wave 0 (new test file — simplified vs. parent's full `check_platform_manifests`) |
| AUTH-06 | Info.plist contains `ITSAppUsesNonExemptEncryption=false` | unit (tool script) | Same `info_plist_keys_test.dart` | Wave 0 |
| LOG-01 | Logger writes to `<docs>/logs/{filename}.txt`, one file per session | unit | `flutter test test/infrastructure/logging/file_logger_test.dart` (bootstrap → assert file exists at expected path with expected filename pattern) using `path_provider_platform_interface` mock for documents dir | Wave 0 (new test file — adapt parent's existing tests if any) |
| LOG-02 | Level.ALL, ms-precision timestamps | unit | `file_logger_test.dart` (assert Logger.root.level == Level.ALL after bootstrap; assert sample log line's `ts` field round-trips with millisecond precision) | Wave 0 |
| LOG-03 | Logger initialised before other modules | smoke | Manually verified by `main.dart` ordering; no productive automated test (would need binding-init mock) | manual review |
| LOG-04 | Share button in AppBar visible from any screen | widget | `flutter test test/presentation/widgets/poc_app_bar_test.dart` (every Scaffold variant renders the share IconButton with correct tooltip) | Wave 0 |
| LOG-05 | Share sheet works on SideStore-sideloaded iOS with Mail | manual-only | **CANNOT be automated** — requires (a) signed CI IPA, (b) physical iPhone, (c) SideStore install, (d) Mail app configured, (e) human visual confirmation of received email. This IS the Phase 1 UAT exit gate per CONTEXT.md decision. | manual UAT walk |
| PERF-01 | FPS counter overlay visible, rolling 1-s avg, ProMotion-aware | widget + manual | Widget test: `fps_counter_overlay_test.dart` (renders, contains "fps" + "Hz" text, refresh rate from mocked `PlatformDispatcher`). Manual: visible in iOS walk evidence (screenshot or video). | Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test` (Flutter widget + unit tests; ~5-10 s on a warm cache for Phase 1's small test surface)
- **Per wave merge:** `flutter test && dart test tool/test/` (full suite — adds the tool tests, ~3 s extra)
- **Phase gate:** Full suite green locally + CI all three jobs green on `main` + manual UAT walk (sideload IPA, walk through permission grant on iPhone, share log via Mail, verify email arrived) + verbal "approved" from the developer

### Wave 0 Gaps

The following test infrastructure does not yet exist in this repo (it's a fresh Flutter project) and must be established in Wave 0 before subsequent waves can land application code with tests:

- [ ] `pubspec.yaml` with `dev_dependencies: flutter_test` (SDK) + `flutter_lints 6.0.0` + `yaml 3.1.3`
- [ ] `analysis_options.yaml` (STACK.md §12 verbatim + `use_build_context_synchronously: error`)
- [ ] `tool/check_headers.dart` (port verbatim from parent)
- [ ] `tool/check_licenses.dart` (port verbatim from parent)
- [ ] `tool/check_dependencies_md.dart` (port verbatim from parent)
- [ ] `tool/test/check_headers_test.dart` (port from parent)
- [ ] `tool/test/check_licenses_test.dart` (port from parent)
- [ ] `tool/test/check_dependencies_md_test.dart` (port from parent)
- [ ] `test/infrastructure/logging/file_logger_test.dart` (covers LOG-01, LOG-02 — adapt parent test if any, otherwise write fresh)
- [ ] `test/infrastructure/logging/file_logger_lifecycle_observer_test.dart` (covers FileLoggerLifecycleObserver flush behaviour)
- [ ] `test/infrastructure/logging/file_logger_filename_format_test.dart` (covers POC adaptation #1: UTC ISO-8601 basic)
- [ ] `test/presentation/screens/permission_gate_screen_test.dart` (covers AUTH-01, AUTH-02, AUTH-03)
- [ ] `test/presentation/screens/permission_denied_screen_test.dart` (covers AUTH-04)
- [ ] `test/presentation/widgets/poc_app_bar_test.dart` (covers LOG-04 — share button visible from every screen)
- [ ] `test/presentation/widgets/fps_counter_overlay_test.dart` (covers PERF-01 — renders fps + Hz, ProMotion-aware)
- [ ] `test/assets/asset_bundle_test.dart` (covers BOOT-07 — Fra_Melun.pmtile loadable + size sanity)
- [ ] `test/tooling/info_plist_keys_test.dart` (covers AUTH-05, AUTH-06 — XML-parse Info.plist, assert keys)
- [ ] `.github/workflows/ci.yml` (the workflow itself; covers CI-01 through CI-05 once a push lands)
- [ ] `LICENSE` (covers BOOT-03)
- [ ] `DEPENDENCIES.md` skeleton with `## Direct dependencies`, `## Dev dependencies`, `## Transitive dependencies` sections (covers AUDIT-01 — actual rows added as deps land)
- [ ] `l10n.yaml` + `lib/l10n/app_fr.arb` + `lib/l10n/app_en.arb` (enables AppLocalizations codegen)

**Framework install command:** none — `flutter_test` ships with the SDK; `dart test` for tool tests is also bundled.

## Sources

### Primary (HIGH confidence — direct file inspection)

- `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\logging\file_logger.dart` — full source for the FileLogger to port (296 lines)
- `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\logging\file_logger_lifecycle_observer.dart` — full source for the lifecycle observer (49 lines)
- `C:\claude_checkouts\GOSL-MirkFall\tool\check_licenses.dart` — full source for the license CI gate (337 lines)
- `C:\claude_checkouts\GOSL-MirkFall\tool\check_headers.dart` — partial inspection (verified shape + exclusion list)
- `C:\claude_checkouts\GOSL-MirkFall\tool\check_dependencies_md.dart` — full source for the deps-table CI gate (140 lines)
- `C:\claude_checkouts\GOSL-MirkFall\.github\workflows\ci.yml` — full source for the CI workflow shape (438 lines, with extensive comments documenting JDK 17→21 and macos-14→26 history)
- `C:\claude_checkouts\GOSL-MirkFall\ios\Runner\Info.plist` — current parent Info.plist (84 lines) for reference on POC's stripped-down version
- `C:\claude_checkouts\GOSL-MirkFall\pubspec.yaml` (head) — parent pin verification (Flutter 3.41.7, share_plus 12.0.2, etc.)
- `.planning\research\STACK.md` — the project-level stack research that this Phase 1 research extends (574 lines, comprehensive package audits)
- `.planning\research\PITFALLS.md` — the project-level pitfalls research (737 lines, source for Pitfalls A-G in this document)
- `.planning\research\ARCHITECTURE.md` (head) — confirms the same-Canvas guarantee (no impact on Phase 1, but bounds the placeholder /map screen choice)
- `.planning\PROJECT.md` — project context, parent file paths, GOSL constraints
- `.planning\REQUIREMENTS.md` — the 28 phase requirements
- `.planning\ROADMAP.md` — Phase 1 success criteria
- `.planning\phases\01-foundation\01-CONTEXT.md` — user decisions for this phase

### Secondary (MEDIUM confidence — STACK.md cited URLs, verified at research date)

- pub.dev package pages (Flutter 3.41 line, share_plus 12.0.2, permission_handler 12.0.1, geolocator 14.0.2, go_router 16.0.0, path_provider 2.1.5, logging 1.3.0, path 1.9.1, flutter_lints 6.0.0) — all listed in STACK.md §Sources
- `subosito/flutter-action@v2` (CI step) — listed in STACK.md
- Apple's Required Reason API documentation (NSPrivacyAccessedAPICategoryFileTimestamp, NSPrivacyAccessedAPICategoryUserDefaults reason codes) — Apple Developer docs

### Tertiary (LOW confidence — flagged for verification during Phase 1)

- The `ios/Runner/PrivacyInfo.xcprivacy` content sketch in this document is synthesized from STACK.md §iOS sideload toolchain notes + Apple's Required Reason API doc; it is NOT a verbatim copy of the parent file (parent file does NOT exist — verified by `ls`). The exact reason codes (`C617.1`, `CA92.1`) come from Apple's published list but the planner should re-verify them against Apple's current Required Reason API documentation when authoring the actual file.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every dep version was already verified by STACK.md against pub.dev and the parent project. Only the Flutter version (3.41.7 vs 3.41.8) and macOS image (latest vs 14 vs 26) are open and bounded.
- Architecture: HIGH — port-from-parent for everything except the `/map` placeholder Scaffold (trivial), the FPS counter (well-known Flutter API), and the bilingual ARB setup (standard `flutter gen-l10n` flow).
- Pitfalls: HIGH — comprehensive PITFALLS.md already exists; the seven Phase-1-relevant ones are extracted with prevention/detection mapped to specific tasks.
- Validation: HIGH for unit/widget testable surface (~80% of Phase 1 reqs); HIGH for the manual-only LOG-05 gate (CONTEXT.md explicitly downscaled it; no ambiguity).

**Research date:** 2026-04-30
**Valid until:** 2026-05-30 (30 days — Flutter SDK 3.41.x is on stable and shouldn't churn within this window; pinned dep versions are even more stable. If the developer postpones Phase 1 by >30 days, re-check Flutter stable hotfixes only.)
