---
phase: 01-foundation
plan: 01
subsystem: infra
tags: [bootstrap, pubspec, path-a, flutter-3.41.7, l10n, gosl-license, donor-constants, assets, ios-bundle-id, sidestore]

# Dependency graph
requires: []
provides:
  - "pubspec.yaml — strict-pinned Path A chain (flutter_map 7.0.2 + 13 other direct deps + 4 dev deps including test 1.30.0)"
  - "pubspec.lock — committed reproducible resolution (104 transitive packages)"
  - "analysis_options.yaml — strict-mode + use_build_context_synchronously: error"
  - "LICENSE — GOSL v1.0 verbatim from parent (BOOT-03)"
  - "l10n.yaml + lib/l10n/app_fr.arb + lib/l10n/app_en.arb — bilingual l10n wired with FR template (synthetic-package flag dropped per Flutter 3.41 deprecation)"
  - "lib/config/constants.dart — donor constants subset (kMaxLogsDirBytes, kMetersPerDegreeLat, kEarthRadiusMeters, kMirkFog* family + kMirkFogSdfResolution)"
  - "assets/maps/Fra_Melun.pmtile (4.0 MB) + assets/shaders/atmospheric_fog.frag — bundled binary assets (BOOT-07, BOOT-08 dormant)"
  - "test/assets/asset_bundle_test.dart — 5 passing tests verifying assets + constants"
  - "Bundle ID locked: com.thongvan.mirkPocDebug (iOS) + com.thongvan.mirk_poc_debug (Android applicationId) — referenced by Plan 07's SideStore UAT instructions"
affects: [01-02, 01-03, 01-04, 01-05, 01-06, 01-07, 02-map, 03-fog]

# Tech tracking
tech-stack:
  added:
    - "flutter_map 7.0.2 (Path A)"
    - "vector_map_tiles 8.0.0"
    - "vector_map_tiles_pmtiles 1.5.0"
    - "vector_tile_renderer 5.2.0"
    - "pmtiles 1.2.0"
    - "latlong2 0.9.1"
    - "permission_handler 12.0.1"
    - "geolocator 14.0.2"
    - "path_provider 2.1.5"
    - "go_router 16.0.0"
    - "logging 1.3.0"
    - "path 1.9.1"
    - "share_plus 12.0.2"
    - "cupertino_icons 1.0.9"
    - "flutter_lints 6.0.0"
    - "yaml 3.1.3"
    - "test 1.30.0 (added per Plan 01-02 coordination flag)"
  patterns:
    - "Strict-pinned dependency graph: zero `^` characters in dependencies/dev_dependencies — pubspec.lock committed for reproducibility (CLAUDE.md mandate, BOOT-01)"
    - "GOSL header on every new .dart file (3-line copyright + license + see-LICENSE-file)"
    - "Donor constants subset port: parent's ~880-line constants.dart filtered to ~30 constants actually referenced by Phase 1 + BOOT-08 donor files. Avoids dragging Phase 2+ tunables into the POC."
    - "l10n via real (non-synthetic) package output: Flutter 3.41 removed the synthetic-package flag, so generated app_localizations*.dart land in lib/l10n/ (gitignored) and import path is `package:mirk_poc_debug/l10n/...` instead of `package:flutter_gen/gen_l10n/...`"
    - "Compiled-shader asset verification: `flutter: shaders:` block compiles GLSL → IPLR binary at build time, so asset_bundle_test verifies via `rootBundle.load(...)` + IPLR magic-byte check rather than `loadString(...)` text grep"

key-files:
  created:
    - "C:/claude_checkouts/mirk-poc-debug/pubspec.yaml (rewritten from default)"
    - "C:/claude_checkouts/mirk-poc-debug/pubspec.lock (committed)"
    - "C:/claude_checkouts/mirk-poc-debug/analysis_options.yaml (rewritten)"
    - "C:/claude_checkouts/mirk-poc-debug/LICENSE"
    - "C:/claude_checkouts/mirk-poc-debug/.gitignore (augmented)"
    - "C:/claude_checkouts/mirk-poc-debug/l10n.yaml"
    - "C:/claude_checkouts/mirk-poc-debug/lib/l10n/app_fr.arb"
    - "C:/claude_checkouts/mirk-poc-debug/lib/l10n/app_en.arb"
    - "C:/claude_checkouts/mirk-poc-debug/lib/config/constants.dart"
    - "C:/claude_checkouts/mirk-poc-debug/assets/maps/Fra_Melun.pmtile"
    - "C:/claude_checkouts/mirk-poc-debug/assets/shaders/atmospheric_fog.frag"
    - "C:/claude_checkouts/mirk-poc-debug/test/assets/asset_bundle_test.dart"
    - "C:/claude_checkouts/mirk-poc-debug/.planning/phases/01-foundation/deferred-items.md"
  modified:
    - "C:/claude_checkouts/mirk-poc-debug/.gitignore (augmented to gitignore generated lib/l10n/app_localizations*.dart)"

key-decisions:
  - "Adopted existing Flutter scaffold instead of running `flutter create`. Bundle ID com.thongvan.mirkPocDebug already in place from prior session and matched the user-approved checkpoint default; re-running flutter create would have either no-op'd or risked overwriting parallel-wave files (ios/Runner/Info.plist + ios/Runner/PrivacyInfo.xcprivacy from Plan 01-02)."
  - "Added `test: 1.30.0` to dev_dependencies per Plan 01-02 coordination flag — without it, `dart test tool/test/` cannot resolve `package:test/test.dart`."
  - "Dropped `synthetic-package: true` from l10n.yaml. Flutter 3.41 rejects this flag (removed feature); generated AppLocalizations now land in `lib/l10n/app_localizations*.dart` (gitignored). Import path for downstream plans changes from `package:flutter_gen/gen_l10n/...` to `package:mirk_poc_debug/l10n/...`."
  - "Constants port subset: 30 constants from parent's 880-line constants.dart, scoped to what Phase 1 + BOOT-08 donor files actually reference. Phase 2/3+ constants (DB pragmas, candlelight tunables, download throttling, etc.) deliberately NOT ported — they would be dead code in the POC."
  - "Asset bundle test for atmospheric_fog.frag: load as binary + verify IPLR magic header rather than grep for 'void main' on the source. Flutter compiles `shaders:` GLSL into IPLR (Impeller Linker Representation) binary at build time, so the bundled asset is binary, not text."

patterns-established:
  - "Strict-pinned pubspec graph (no ranges) is the contract every Phase 1+ dep must honour. CLAUDE.md mandate."
  - "Donor constants subset pattern: when porting from parent, filter to actually-referenced constants. Reduces audit surface and prevents Phase 2+ subsystems from leaking into the POC's test-mode."
  - "Compiled-shader asset verification idiom: `rootBundle.load(...)` + IPLR magic-byte check. Phase 3 will use `FragmentProgram.fromAsset(...)` at runtime — same loading mechanism."
  - "Bundle ID lock pattern: surface SideStore App-ID quota cost in a Pre-Task checkpoint BEFORE flutter create runs, not after Plan 07's first sideload. Cost of confirming-now is zero; cost of confirming-after is a 7-day cooldown."

requirements-completed: [BOOT-01, BOOT-03, BOOT-04, BOOT-05, BOOT-06, BOOT-07]

# Metrics
duration: 7 min
completed: 2026-04-30
---

# Phase 1 Plan 01: Foundation Bootstrap Summary

**Strict-pinned Path A pubspec.yaml (flutter_map 7.0.2 + 13 other direct deps + test 1.30.0 in dev_deps), strict-mode analysis_options, GOSL v1.0 LICENSE, bilingual l10n, donor constants subset, and binary assets bundled — `flutter pub get` resolves 104 packages cleanly with bundle ID com.thongvan.mirkPocDebug locked.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-30T16:28:20Z
- **Completed:** 2026-04-30T16:35:49Z
- **Tasks:** 3 (Pre-Task checkpoint resolved separately by user)
- **Files created:** 12 (pubspec.yaml + pubspec.lock + analysis_options.yaml + LICENSE + .gitignore + l10n.yaml + 2 ARBs + constants.dart + 2 binary assets + 1 test file)
- **Files modified:** 1 (.gitignore — augmented for generated l10n files)

## Accomplishments

- **Bundle ID locked: `com.thongvan.mirkPocDebug`** (iOS) and `com.thongvan.mirk_poc_debug` (Android applicationId). User approved the proposed default at the Pre-Task checkpoint. Plan 07's UAT instructions for SideStore sideload should reference this exact iOS bundle ID.

- **pubspec.yaml rewritten** with strict-pinned Path A chain per RESEARCH.md §Final pubspec.yaml. 14 direct deps + 4 dev_deps, zero `^` characters, `pubspec.lock` committed. `flutter pub get` resolves 104 transitive packages cleanly.

- **`test: 1.30.0` added to dev_dependencies** per the coordination flag from Plan 01-02 SUMMARY. Without it, `dart test tool/test/` cannot resolve `package:test/test.dart`. Plan 01-02's tool tests + the wider tool test runner now have the dep they need.

- **analysis_options.yaml** rewritten with strict mode (`strict-casts`, `strict-inference`, `strict-raw-types` all true) + `use_build_context_synchronously: error` per STACK.md §12 + RESEARCH.md Pitfall B. CI's `--fatal-infos --fatal-warnings` posture is now enforceable.

- **LICENSE** at repo root carries the GOSL v1.0 text verbatim from `C:/claude_checkouts/GOSL-MirkFall/LICENSE.md`. Plain text file (no `.md` extension) per REQUIREMENTS.md BOOT-03.

- **.gitignore** keeps `pubspec.lock` committed (CLAUDE.md mandate) and gitignores generated l10n files (Flutter 3.41 writes them into lib/l10n/ not .dart_tool/).

- **Bilingual l10n** wired: `l10n.yaml` + `lib/l10n/app_fr.arb` + `lib/l10n/app_en.arb` with all six expected keys (appTitle, permissionRationaleParagraph, permissionRationaleCta, permissionDeniedParagraph, permissionDeniedOpenSettings, shareLogsTooltip). French is the template per CONTEXT.md fallback decision. `flutter gen-l10n` succeeds and produces `app_localizations.dart` + `app_localizations_en.dart` + `app_localizations_fr.dart` locally.

- **lib/config/constants.dart** seeded with the donor constants subset:
  - `kMaxLogsDirBytes` (10 MB) — for FileLogger prune (Plan 01-04)
  - `kMetersPerDegreeLat` (111 320) and `kEarthRadiusMeters` (6 371 008.8) — for reveal_disc + revealed_sdf_builder + tile_cell_iteration (Plan 01-03 BOOT-08 donors)
  - `kMirkFogSdfResolution` (256) + 33 `kMirkFog*` palette/drift/scale/curl/light/hue/boundary constants — for fog_shader_uniforms (Plan 01-03 BOOT-08 donors). Values preserved verbatim from parent's 2026-04-26 tuner walk N+M bake.

- **Binary assets bundled**: `Fra_Melun.pmtile` (4.0 MB, md5 identical to source from `C:/claude_checkouts/countries-pmtiles/`) + `atmospheric_fog.frag` (17.3 KB, md5 identical to parent shader). Both wired through `flutter: assets:` and `flutter: shaders:` blocks in pubspec.yaml.

- **5-test asset_bundle_test.dart passes**: confirms Fra_Melun.pmtile bundled and 3-5 MB; atmospheric_fog.frag compiled to IPLR binary and recognised; constants exposed at expected values.

## Task Commits

Each task was committed atomically:

1. **Task 1 (plan-numbered): Adopt scaffold + pubspec.yaml + analysis_options.yaml + LICENSE + .gitignore** — `4f0fa26` (feat)
2. **Task 2 (plan-numbered): l10n.yaml + lib/l10n/app_fr.arb + lib/l10n/app_en.arb** — `1b7187f` (feat)
3. **Task 3 (plan-numbered): assets/maps/Fra_Melun.pmtile + assets/shaders/atmospheric_fog.frag + lib/config/constants.dart + test/assets/asset_bundle_test.dart** — `6c4e02b` (feat)

**Plan metadata:** TBD (committed at end of this run via gsd-tools).

_Note: TDD task 3 (plan-marked `tdd="true"`) collapsed RED+GREEN into a single feat commit — a verbatim port of binary assets + constants doesn't have a meaningful "minimal failing test → minimal passing impl" cycle. The test was written alongside the source files and passed first run for 4/5 cases (the 5th case required a Rule 1 deviation — see Deviations section)._

## Files Created/Modified

- `pubspec.yaml` — Strict-pinned Path A chain (14 direct + 4 dev deps).
- `pubspec.lock` — Reproducible resolution (committed).
- `analysis_options.yaml` — Strict mode + use_build_context_synchronously: error.
- `LICENSE` — GOSL v1.0 verbatim from parent.
- `.gitignore` — Flutter default + generated l10n exclusions + pubspec.lock-committed comment.
- `l10n.yaml` — gen-l10n config (synthetic-package flag dropped — Flutter 3.41 deprecation).
- `lib/l10n/app_fr.arb` — French template (6 keys).
- `lib/l10n/app_en.arb` — English variant (6 keys).
- `lib/config/constants.dart` — 30 donor constants ported.
- `assets/maps/Fra_Melun.pmtile` — 4.0 MB MVT bundle.
- `assets/shaders/atmospheric_fog.frag` — 17.3 KB GLSL donor.
- `test/assets/asset_bundle_test.dart` — 5 passing tests.
- `.planning/phases/01-foundation/deferred-items.md` — Plan 01-04 sibling items + l10n import path note.

## Decisions Made

- **Skipped `flutter create`; adopted the existing scaffold.** The orchestrator instructed: scaffold from prior session is on disk, bundle ID matches the user-approved default, re-running flutter create risks overwriting Plan 01-02's parallel-wave Info.plist edits. Adopted as-is. Verified `com.thongvan.mirkPocDebug` in `ios/Runner.xcodeproj/project.pbxproj` and `com.thongvan.mirk_poc_debug` in `android/app/build.gradle.kts`.
- **Added `test: 1.30.0` to dev_dependencies** per Plan 01-02 coordination flag. Plan 01-02's `tool/test/check_*_test.dart` files import `package:test/test.dart`; without this dep, `dart test tool/test/` fails. The pin matches what the parent project carries.
- **Constants port: subset only.** The parent's `lib/config/constants.dart` is ~880 lines covering Phase 2-9 subsystems (SQLite pragmas, download throttling, candlelight renderer, heavenly clouds, wisp particles, MapLibre source IDs, etc.). The POC ports only the constants the Phase 1 + BOOT-08 donor files actually reference (~30 constants). This avoids dragging dead-code subsystems into the POC's audit surface and keeps `flutter analyze` clean.
- **Asset test for shader uses binary verification.** Flutter's `shaders:` pubspec block compiles GLSL → IPLR (Impeller Linker Representation) binary at build time. The plan's original test sketch called `loadString` and grepped for `void main`, which would fail at runtime with `FormatException: Invalid UTF-8 byte` because the asset is binary. Fixed by loading via `rootBundle.load(...)` and asserting the IPLR magic header. This is also the correct Phase 3 idiom — at runtime fog uses `FragmentProgram.fromAsset(...)`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Skipped `flutter create` step in Task 1 (plan-numbered)**
- **Found during:** Task 1 (plan-numbered) — the orchestrator's continuation prompt explicitly instructed: "scaffold already present from prior session, do NOT delete and re-run flutter create".
- **Issue:** Re-running `flutter create` would have either no-op'd (since a scaffold already exists) or, worse, overwritten files that Plan 01-02 had already committed in parallel (ios/Runner/Info.plist with the AUTH-05/AUTH-06/Pitfall E keys; ios/Runner/PrivacyInfo.xcprivacy with the Required Reason API declarations). Both files would be reset to the flutter-create defaults, undoing Plan 01-02's work.
- **Fix:** Adopted the existing scaffold as-is. Verified bundle ID matches user-approved default. Staged and committed all untracked scaffold files in Task 1's commit alongside the pubspec/analysis/license/gitignore rewrites.
- **Files modified:** none beyond what the plan specified for Task 1 (the existing scaffold files were just brought under git tracking).
- **Verification:** `git log --oneline -5` shows 4f0fa26 created at the right place; bundle ID grep across `ios/Runner.xcodeproj/project.pbxproj` and `android/app/build.gradle.kts` confirms the user-approved values are intact.
- **Committed in:** 4f0fa26 (Task 1 commit).

**2. [Rule 3 - Blocking] Dropped `synthetic-package: true` from l10n.yaml**
- **Found during:** Task 2 (plan-numbered).
- **Issue:** `flutter gen-l10n` failed with `l10n.yaml: Cannot enable "synthetic-package", this feature has been removed. See http://flutter.dev/to/flutter-gen-deprecation.` Flutter 3.41 removed the synthetic-package mechanism and now writes generated l10n files alongside the .arb sources in lib/l10n/.
- **Fix:** Removed the `synthetic-package: true` line from l10n.yaml. Augmented .gitignore to exclude the generated `lib/l10n/app_localizations.dart` + `lib/l10n/app_localizations_*.dart` files (codegen artefacts, rebuilt on every `flutter pub get`).
- **Files modified:** `l10n.yaml`, `.gitignore`.
- **Verification:** `flutter gen-l10n` now succeeds without errors and generates the three expected files in `lib/l10n/`.
- **Committed in:** 1b7187f (Task 2 commit).
- **Downstream impact:** Plans 01-05 (permission gate UI) and 01-07 (main.dart wiring) need to import `package:mirk_poc_debug/l10n/app_localizations.dart` instead of the planning-prompt-suggested `package:flutter_gen/gen_l10n/app_localizations.dart`. Documented in `.planning/phases/01-foundation/deferred-items.md`.

**3. [Rule 1 - Bug] Asset bundle test for atmospheric_fog.frag rewritten for binary IPLR verification**
- **Found during:** Task 3 (plan-numbered) — test execution.
- **Issue:** The plan's test sketch called `rootBundle.loadString('assets/shaders/atmospheric_fog.frag')` and asserted `source contains 'void main'`. This failed at runtime with `FormatException: Invalid UTF-8 byte (at offset 44)`. Root cause: Flutter's `shaders:` pubspec block compiles GLSL source files into IPLR (Impeller Linker Representation) binary packages at build time. The bundled asset is binary (`\x1C\x00\x00\x00IPLR...`), not the original text. `loadString` cannot decode it as UTF-8.
- **Fix:** Replaced the `loadString` + grep test with a `rootBundle.load(...)` + IPLR magic-byte assertion (bytes 4-7 = ASCII "IPLR"). This is the correct Flutter idiom — at runtime in Phase 3, the shader is loaded via `FragmentProgram.fromAsset(...)` rather than as text, and the test now mirrors that loading mechanism.
- **Files modified:** `test/assets/asset_bundle_test.dart`.
- **Verification:** `flutter test test/assets/asset_bundle_test.dart` — all 5 tests green.
- **Committed in:** 6c4e02b (Task 3 commit).

---

**Total deviations:** 3 auto-fixed (2 blocking — orchestrator-directed scaffold-adoption + Flutter 3.41 l10n flag removal; 1 bug — incorrect plan test assumption about shader bundling).
**Impact on plan:** All deliverables landed correctly. The synthetic-package change has a downstream import-path implication for Plans 01-05 and 01-07 (documented in deferred-items.md). The asset-bundle test deviation actually produces a stronger test (verifies the build pipeline output, not just source-file presence).

## Issues Encountered

- **`flutter analyze --fatal-infos --fatal-warnings` not yet exit-0 against the wave-1 tree.** Three info-level issues remain in Plan 01-04 sibling files (FileLogger lifecycle observer's unnecessary import; FileLogger test's two transitive-package imports). All belong to Plan 01-04, not Plan 01-01. Documented in `.planning/phases/01-foundation/deferred-items.md` for the verifier / Plan 01-07 author. Plan 01-01's own files report zero analyze issues.
- **`lib/main.dart` from `flutter create` lacks the GOSL header** and contains some questionable scaffolding code patterns (e.g. reliance on type inference in `colorScheme: .fromSeed(...)`). The plan explicitly defers this fix — Plan 07 owns the final `main.dart` content. `tool/check_headers.dart` from Plan 01-02 will flag this file as expected (red→green transition documented across Plans 01-02 and 01-03 SUMMARYs).

## Authentication Gates

None — no external service authentication required for this plan. The Pre-Task checkpoint (bundle ID confirmation) was a `human-verify` decision gate, not an auth gate. User approved the proposed `com.thongvan.mirkPocDebug` default without override.

## User Setup Required

None — no external service configuration required for this plan. The first user-setup gate of Phase 1 will appear in Plan 07 (SideStore sideload UAT walk).

## Next Phase Readiness

- **Wave 0 + Wave 1 sibling plans (01-02, 01-03, 01-04) now have the deps they need.** Plan 01-04's FileLogger imports (`logging`, `path`, `path_provider`, `package:mirk_poc_debug/config/constants.dart::kMaxLogsDirBytes`) all resolve. Plan 01-02's tool tests (`package:test`, `package:yaml`, `package:path`) all resolve. Plan 01-03's BOOT-08 donor files (`logging`, `package:mirk_poc_debug/...` paths, `kMetersPerDegreeLat` + `kEarthRadiusMeters` + `kMirkFogSdfResolution`) all resolve.
- **Verifier sanity check:** `flutter pub get && flutter test test/assets/asset_bundle_test.dart && flutter test test/infrastructure/logging/ && flutter test test/tooling/info_plist_keys_test.dart && dart test tool/test/` should now run end-to-end. The asset_bundle_test (5) is green from this plan's execution; the others should now compile and run since their dependency chain is in place.
- **Plan 02 (next phase, map subsystem)** can rely on `flutter_map: 7.0.2` + `vector_map_tiles: 8.0.0` + `vector_map_tiles_pmtiles: 1.5.0` + `pmtiles: 1.2.0` being in pubspec.lock at the exact pinned versions; the bundled `assets/maps/Fra_Melun.pmtile` is loadable via `rootBundle.load(...)` for the first map screen.
- **Plans 01-05 (permission gate UI) and 01-07 (main.dart wiring) — heads-up:** the l10n import path is `package:mirk_poc_debug/l10n/app_localizations.dart`, NOT `package:flutter_gen/gen_l10n/app_localizations.dart` as some planning prompts may suggest. Synthetic-package mechanism removed in Flutter 3.41.

---

## Self-Check: PASSED

All claimed files exist on disk; all claimed task commits exist in git history.

**Files verified:**
- `pubspec.yaml` (FOUND, 1565 bytes — strict-pinned)
- `pubspec.lock` (FOUND, 30234 bytes — committed)
- `analysis_options.yaml` (FOUND — strict mode)
- `LICENSE` (FOUND — `grep -q "Good Old Software License"` exits 0)
- `.gitignore` (FOUND — augmented)
- `l10n.yaml` (FOUND)
- `lib/l10n/app_fr.arb` (FOUND — 6 keys)
- `lib/l10n/app_en.arb` (FOUND — 6 keys)
- `lib/config/constants.dart` (FOUND — kMaxLogsDirBytes / kMetersPerDegreeLat / kEarthRadiusMeters present)
- `assets/maps/Fra_Melun.pmtile` (FOUND — 4 176 302 bytes)
- `assets/shaders/atmospheric_fog.frag` (FOUND — 17 667 bytes)
- `test/assets/asset_bundle_test.dart` (FOUND — 5 tests pass)
- `.planning/phases/01-foundation/deferred-items.md` (FOUND)
- `.planning/phases/01-foundation/01-01-SUMMARY.md` (FOUND — this file)

**Commits verified:**
- `4f0fa26` (Task 1 plan-numbered: feat(01-01) — scaffold + pubspec + analysis + LICENSE + .gitignore) — FOUND in git log
- `1b7187f` (Task 2 plan-numbered: feat(01-01) — l10n.yaml + ARBs) — FOUND
- `6c4e02b` (Task 3 plan-numbered: feat(01-01) — assets + constants + test) — FOUND

**Verification commands:**
- `flutter pub get` — exit 0 (Got dependencies! 104 transitive packages)
- `flutter gen-l10n` — exit 0 (3 generated dart files in lib/l10n/)
- `flutter analyze lib/config/constants.dart` — `No issues found!`
- `flutter test test/assets/asset_bundle_test.dart` — 5/5 tests pass

---
*Phase: 01-foundation*
*Completed: 2026-04-30*
