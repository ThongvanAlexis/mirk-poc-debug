# Phase 1: Foundation - Context

**Gathered:** 2026-04-30
**Status:** Ready for planning

<domain>
## Phase Boundary

First sideloadable IPA where the developer walks through permission, sees the FPS counter, and shares the session log over Mail. Establishes the iOS feedback loop end-to-end before any map code is written. Covers REQUIREMENTS.md BOOT-01..08, AUDIT-01..03, CI-01..05, AUTH-01..06, LOG-01..05, PERF-01.

Out of scope for this phase: the real map (Phase 2), GPS pipeline (Phase 2), fog (Phase 3), wisps (Phase 4). The `/map` screen exists as a placeholder Scaffold so the walk feels real.

</domain>

<decisions>
## Implementation Decisions

### Localization
- Both French and English via `flutter_localizations` (SDK package, BSD-3, no telemetry)
- ARB files under `lib/l10n/`, generated via `flutter gen-l10n`
- Locale follows device; default fallback = French (developer is French, walks in Melun)
- All in-app strings (rationale screen, denied screen, share button tooltip, FPS counter labels, AppBar title) go through the `AppLocalizations` accessor — no hardcoded user-facing strings
- `Info.plist` `NSLocationWhenInUseUsageDescription`: French string (per AUTH-05); English variant via `InfoPlist.strings` if iOS i18n is straightforward, otherwise French only is acceptable for v1

### Permission flow UX
- **Rationale screen layout**: centered Material icon (`Icons.location_on_outlined`) + one explanatory paragraph (~2 sentences explaining locationWhenInUse → fog of war + "stays on device") + single primary CTA button (`'Autoriser la position'` / `'Allow location'`)
- **Denied screen**: short explanation + single 'Open Settings' button calling `permission_handler.openAppSettings()`. No 'Try Again' button (iOS caches first-prompt result; subsequent in-app requests silently return cached status — misleading UX)
- **Lifecycle resume re-check**: app observes `AppLifecycleState.resumed` and re-checks `Permission.locationWhenInUse.status` on every resume. If granted → auto-navigate to `/map` via `context.go('/map')`. Covers the "user denied → opened Settings → toggled on → returned" path with zero extra taps
- **Grant flow** (AUTH-03): the moment permission becomes `granted` (whether from in-app prompt or post-settings resume), call `context.go('/map')` immediately. No confirmation, no delay, no extra tap

### FPS counter
- **Visibility**: always-on overlay, present on every screen of the POC (permission gate, denied, /map). Pitfall 6 (confirmation bias) wants it captured in walk evidence; POC is debug-only with no production state to hide it from
- **Position**: top-right corner. Avoids Dynamic Island / notch (top-center), iOS home-indicator gesture zone (bottom), and the recenter FAB Phase 2 will add (bottom-right)
- **Display format**: `60 fps / 120 Hz` — current 1-second rolling-average fps, slash, device refresh rate. ProMotion-aware per Pitfall 14 (a bare "32 fps" reading is meaningless without knowing the device wants 60 vs 120)
- **Averaging**: 1-second rolling average per PERF-01. Computed via `WidgetsBinding.instance.addPersistentFrameCallback` (or `SchedulerBinding`) accumulating frame timings, recomputed every ~250 ms display tick
- **Refresh rate source**: `WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate` (or equivalent) — never hardcode 60 or 120

### Logger & share UX
- **Filename format**: UTC ISO-8601 basic: `yyyymmddTHHMMSSZ_logs.txt` (e.g. `20260430T142503Z_logs.txt`). Fixes Pitfall 19 (midnight-cross local-time ambiguity). Diverges from parent project's `yyyymmdd_hhmm.ss_logs.txt` — intentional POC improvement
- **Per-session size**: unbounded write (no per-session rotation). Gzip happens at share time only
- **Across-session retention**: 10 MB total cap on `<app_documents_dir>/logs/` directory, enforced by prune-oldest at bootstrap (port `kMaxLogsDirBytes = 10 MB` constant + `_pruneToSizeLimit` from parent verbatim)
- **File encoding**: UTF-8, no BOM. Set explicitly (do not rely on platform default). Preserves accented French place names round-trip through Mail
- **Share trigger**: `Icons.share` in the Scaffold's AppBar `actions` list, with tooltip (`'Partager les logs'` / `'Share logs'`). Visible on every screen (LOG-04). Tapping → gzip the active log file → invoke `share_plus.shareXFiles([gzippedFile])` → user picks Mail (or Messages, etc.)
- **No PII confirmation dialog**: POC is single-developer, you know what's in the logs. Confirmation taps add friction with no benefit
- **On log write failure**: silent fallback to `dart:developer.log()` only. Catch `FileSystemException`, surface via `dart:developer.log()`, null the `RandomAccessFile` handle to avoid infinite loop in zone error handler. No UI banner, no crash. Matches CLAUDE.md "erreurs non-critiques en périphérie" policy

### Placeholder /map screen (Phase 1 only — Phase 2 replaces body)
- **Scaffold** with AppBar (title `'MirkFall POC'`, share-icon action) + dark-grey solid-color body (e.g. `Colors.grey[850]`) + always-on FPS counter overlay top-right
- No placeholder text, no logo, no GPS readout — Phase 2 swaps the body for `FlutterMap`. Minimum churn between phases
- Same AppBar appears on permission gate and denied screens (LOG-04 mandate: share button visible from every screen). One `Widget _buildAppBar(BuildContext)` helper in a shared `widgets/` file, reused across all three screens

### Phase 1 UAT exit gate
- **No 50 MB synthetic-log smoke test**. Explicitly removed from scope by user direction: "this is a POC, just log, and if it does not work I'll tell you"
- LOG-05 ("Phase 1 smoke test confirms this") softens to: developer sideloads the IPA, taps share-logs, picks Mail, verifies the email arrives with the gzipped log file. Verbal "approved" is the gate
- Update REQUIREMENTS.md LOG-05 wording during Phase 1 planning to drop the "50 MB synthetic-log" specification

### Claude's Discretion
- Exact wording / paragraph copy of the rationale and denied screens (subject to user review during planning if a draft is rejected)
- FPS counter styling: font size, font weight, background opacity, padding, color (legible in any background)
- Dark-grey shade for the placeholder body
- AppBar styling (color, elevation) — match Material 3 defaults unless something obviously wrong
- Whether the AppBar `leading` shows a hamburger / back arrow / nothing on the permission gate
- Tooltip strings for the share button (within the bilingual scope)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets — Port from `C:\claude_checkouts\GOSL-MirkFall`

**`FileLogger` and `FileLoggerLifecycleObserver` — port verbatim with three POC adaptations** (parent path: `lib/infrastructure/logging/{file_logger.dart, file_logger_lifecycle_observer.dart}`):

The parent project's logger is the result of debugging two production-fatal iOS issues. Port the working code, do NOT re-implement from scratch:

1. **Use `RandomAccessFile` opened in `FileMode.writeOnlyAppend`, NOT `IOSink`**.
   - Why: `IOSink.flush()` only drains user-space → kernel page cache; iOS jetsam (foreground RAM pressure) discards the page cache before it reaches flash. `RandomAccessFile.flushSync()` is the real `fsync(2)` per Dart docs — durable to disk
2. **Use synchronous `writeStringSync` + `flushSync` per record. Make `_onRecord` a synchronous function**.
   - Why: `Stream.listen` does NOT await `async` callbacks; an `async` body re-enters itself on back-to-back records → `StateError: StreamSink is bound` → catch nulls the sink → ~99% of records dropped silently for the rest of the session
3. **JSON Lines format**: each record is `jsonEncode({ts, level, logger, msg, error?, stack?}) + '\n'`. Not plain text. Easier to grep, parse, and inspect downstream
4. **Idempotent bootstrap**: closing prior `_raf` + cancelling prior `_subscription` before opening a new file. Covers hot-reload and tests that re-bootstrap
5. **Catch only `FileSystemException`**. On failure: surface message via `dart:developer.log()`, null `_raf` so subsequent records are silently dropped (avoids infinite loop in zone error handler that would call `Logger.shout` → `_onRecord` → recurse)
6. **`FileLoggerLifecycleObserver`** flushes on `paused / inactive / hidden / detached`, no-op on `resumed`. With per-record `flushSync`, the flush is now technically a no-op but kept as a safeguard and to keep call-sites stable
7. **`listLogFiles`** sorts by `FileStat.modified`, NOT by filename. Bug-resistance against future filename-format changes
8. **`_pruneToSizeLimit`** at bootstrap: prune oldest files until total dir size < `kMaxLogsDirBytes` (10 MB). Single-app-instance invariant assumed (POC is mobile-only, fine)
9. **`bootstrap()` MUST be awaited before `runApp()`** — first record after bootstrap captures the `activeFilename` so any read-back can verify path identity (iOS sandbox container UUIDs can shift between launches)
10. **First log line on launch**: `Logger('infrastructure.logging.file_logger').info('FileLogger bootstrap — activeFilename=$_activeFilename')` — already in parent code, port as-is

**Three POC adaptations to the parent code:**

1. **Filename format change**: parent uses local-time `yyyymmdd_hhmm.ss_logs.txt`; POC uses UTC `yyyymmddTHHMMSSZ_logs.txt`. Replace `_formatFilenameTimestamp` body to emit `dt.toUtc()` and ISO-8601 basic format
2. **Always-verbose**: REQUIREMENTS.md LOG-02 mandates `Level.ALL` for the POC. Replace the parent's `Level.ALL`-vs-`Level.INFO` decision logic with hardcoded `Logger.root.level = Level.ALL`
3. **Drop `shared_preferences` dependency**: with always-verbose locked, the parent's `toggleVerbosePref` / `writeVerbosePref` / `readVerbosePref` / `kDebugLoggingPrefsKey` plumbing is unused. Delete those four members. Removes one direct dep + audit row vs. the parent

### Established Patterns — Port from parent
- **GOSL header**: every `.dart` file starts with the 3-line copyright/license header (BOOT-02, see PROJECT.md Constraints)
- **Strict analysis**: `flutter_lints 6.0.0` + `analysis_options.yaml` with `strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`, plus `use_build_context_synchronously: error`. Mirror parent verbatim (BOOT-04, see research/STACK.md §12)
- **`dart format --line-length 160`** in CI (BOOT-05)
- **CI `tool/check_licenses.dart` + `tool/check_dependencies_md.dart`**: port verbatim from parent's `tool/` directory. Allow-list: MIT, BSD-2/3, Apache-2.0, ISC, zlib, CC0, Unlicense (AUDIT-02, CI-02)
- **Three-job CI workflow** (CI-01..05): `lint` (ubuntu) → `build-android` (ubuntu) + `build-ios` (macos) in parallel. Exact YAML drafted in research/STACK.md §CI
- **Unsigned IPA packaging**: `flutter build ios --no-codesign --debug` then manual `zip Payload/Runner.app → unsigned.ipa` per research/STACK.md §CI
- **Pinned versions**: every direct dep in `pubspec.yaml` strict pin (no `^`). `pubspec.lock` committed (BOOT-01, see CLAUDE.md)
- **Path joining**: every filesystem path via `package:path` `p.join()` — never `'/'` concatenation (CLAUDE.md)

### Integration Points
- **`main.dart`**: `WidgetsFlutterBinding.ensureInitialized()` → `await FileLogger.bootstrap()` → `WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver())` → `runZonedGuarded(() => runApp(MirkPocApp()), ...)` per CLAUDE.md error-handling top-level handler
- **`router.dart`**: `GoRouter` with three routes — `/` → `PermissionGateScreen`, `/map` → `MapScreen` (Phase 1: placeholder), `/denied` → `PermissionDeniedScreen`. All transitions use `context.go()` (full pile reset — no back navigation in Phase 1)
- **`Info.plist`**: `NSLocationWhenInUseUsageDescription` (French rationale), `ITSAppUsesNonExemptEncryption=false`, no `Always` permission keys, no camera/mic/photo keys (AUTH-05, AUTH-06)
- **`PrivacyInfo.xcprivacy`**: copy verbatim from parent project's `ios/Runner/PrivacyInfo.xcprivacy` (covers `path_provider` + `share_plus` Required Reason API declarations per research/STACK.md §iOS sideload toolchain notes)
- **`pubspec.yaml`**: dependency list per research/STACK.md §Final pubspec.yaml (Path A — `flutter_map 7.0.2` chain). Phase 1 needs only the subset: `flutter_localizations` (SDK), `permission_handler 12.0.1`, `geolocator 14.0.2` (declared but not yet wired — Phase 2 uses it; declaring it now keeps `Info.plist` Privacy Manifest stable across phases), `path_provider 2.1.5`, `path 1.9.1`, `logging 1.3.0`, `share_plus 12.0.2`, `go_router 16.0.0`, plus `flutter_lints 6.0.0` + `yaml 3.1.3` dev. Map-renderer packages (`flutter_map`, `vector_map_tiles`, `vector_map_tiles_pmtiles`, `vector_tile_renderer`, `pmtiles`, `latlong2`) declared in pubspec for early dependency resolution + DEPENDENCIES.md audit, even if Phase 1 doesn't import them yet
- **`assets/`**: `Fra_Melun.pmtile` (BOOT-07) and `assets/shaders/atmospheric_fog.frag` (BOOT-08) bundled in Phase 1 even though they're consumed in later phases — keeps the IPA size honest from Phase 1 onward, and avoids Phase 2/3 having to re-touch `pubspec.yaml`'s `flutter:` block
- **AppBar reuse**: a single `Widget buildPocAppBar(BuildContext, {String? title})` helper in `lib/presentation/widgets/poc_app_bar.dart`, called from every Scaffold in Phase 1. Embeds the share-logs action

### Files to port verbatim per BOOT-08 (declared as assets/source files in Phase 1, consumed in Phases 3-4)
Per REQUIREMENTS.md BOOT-08, the following parent files land in this repo as part of Phase 1 (so the GOSL header audit, the donor-tree structure, and the asset bundle are all stabilized before the hypothesis test). They are not imported or executed in Phase 1:
- `assets/shaders/atmospheric_fog.frag`
- `lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart`
- `lib/domain/revealed/reveal_disc.dart`
- `lib/domain/mirk/mirk_viewport_bbox.dart`
- `lib/infrastructure/mirk/tile_cell_iteration.dart`
- `lib/infrastructure/mirk/mirk_projection.dart`
- `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart`
- `lib/infrastructure/mirk/animation_helpers.dart`
- Plus relevant `kMirkFog*`, `kMetersPerDegreeLat`, `kEarthRadiusMeters` constants in `lib/config/constants.dart`
- `kMaxLogsDirBytes = 10 * 1024 * 1024` also goes into `lib/config/constants.dart` (used by FileLogger)

</code_context>

<specifics>
## Specific Ideas

- **iOS logger durability**: "we had major issue with making the ios logguer to correctly log, now it's 100% working in that project, you should do it the same way." → Port the parent `FileLogger` + `FileLoggerLifecycleObserver` verbatim with the three documented adaptations. Do NOT re-implement the IOSink/Stream.listen pattern; do NOT re-derive the synchronous-fsync rationale from scratch
- **POC simplicity over ceremony**: "this is a POC, just log, and if it does not work I'll tell you." → Drop the 50 MB synthetic-log smoke test from the Phase 1 UAT exit gate. Verbal confirmation after the first sideload walk suffices
- **Phase 1 placeholder /map screen** stays minimal — empty Scaffold with the AppBar + FPS counter, dark-grey background. The screen exists to prove the iOS feedback loop end-to-end, not to entertain. Phase 2 swaps the body for `FlutterMap` with zero churn elsewhere

</specifics>

<deferred>
## Deferred Ideas

- **In-app debug menu / verbose toggle**: parent project has a SharedPreferences-backed verbose toggle reachable via 7-tap easter egg on the about screen. POC is always-verbose (LOG-02), so the toggle is unnecessary. If a future POC iteration wants a non-verbose mode, port the parent's pattern at that time
- **Custom illustration on rationale screen**: rejected for v1 in favor of a Material icon to avoid commissioning/auditing image assets. If walk evidence later suggests the rationale screen feels too sparse, revisit
- **English-localized `Info.plist` `NSLocationWhenInUseUsageDescription`**: French-only is acceptable for v1 if iOS `InfoPlist.strings` localization adds friction. Revisit if the POC is ever shown to a non-French audience
- **Per-session log file rotation by size**: parent uses across-session 10 MB cap with unbounded per-session writes. POC keeps the same. If a single Phase 3+ walk produces logs that are unmanageable to share even after gzip, revisit per-session rotation then
- **Walk-replay tool** (Pitfall 6 mitigation): record GPS fixes during a walk, replay on Pixel 4a / Windows desktop without re-walking. Useful from Phase 2 onward — out of scope for Phase 1, captured here so Phase 2 planning can pick it up
- **CI license-check failure UX / DEPENDENCIES.md format details**: locked by parent project's `tool/check_licenses.dart` + `tool/check_dependencies_md.dart` (port verbatim). No POC-specific decisions needed
- **App icon design**: out of scope for Phase 1; default Flutter icon is fine for sideloaded debug walks. Revisit at Phase 5 hardening if the developer wants a recognizable home-screen icon

</deferred>

---

*Phase: 01-foundation*
*Context gathered: 2026-04-30*
