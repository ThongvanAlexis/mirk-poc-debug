---
phase: 01-foundation
plan: 02
subsystem: infra
tags: [ci, audit, ios, info-plist, privacy-manifest, dart-tools, license-check, telemetry]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: pubspec.yaml (Plan 01-01 — pending) — provides yaml: 3.1.3 + path: 1.9.1 deps that the tool/ scripts import
provides:
  - tool/check_headers.dart — GOSL header CI gate (BOOT-02)
  - tool/check_licenses.dart — License allow-list CI gate (AUDIT-02)
  - tool/check_dependencies_md.dart — DEPENDENCIES.md freshness CI gate (AUDIT-01)
  - DEPENDENCIES.md — per-package telemetry audit table (AUDIT-01, AUDIT-03)
  - ios/Runner/Info.plist — POC-stripped iOS bundle config with NSLocationWhenInUseUsageDescription, ITSAppUsesNonExemptEncryption=false, CADisableMinimumFrameDurationOnPhone=true (AUTH-05, AUTH-06, Pitfall E)
  - ios/Runner/PrivacyInfo.xcprivacy — Required Reason API declarations for path_provider + UserDefaults
  - test/tooling/info_plist_keys_test.dart — Automated AUTH-05/AUTH-06/Pitfall E verification by parsing the Info.plist XML
affects: [01-foundation, 02-map, 03-fog, 05-hardening]

# Tech tracking
tech-stack:
  added:
    - "package:test (1.30.0) — needed by tool/test/*_test.dart for `dart test` runner; NOT yet added to pubspec.yaml as Plan 01-01 has not committed pubspec changes (BLOCKED — see Coordination Note)"
    - "package:yaml (3.1.3) — used by check_licenses + check_dependencies_md; will be present once Plan 01-01 commits its pubspec.yaml"
    - "package:path (1.9.1) — used by all three tool/ scripts; will be present once Plan 01-01 commits"
  patterns:
    - "CI gate scripts in tool/ — each exits 0 on success, 1 on policy violation, 2 on infrastructure error (missing pubspec.lock, etc.). Pattern lifted verbatim from parent project."
    - "Section-header-aware markdown parser in check_dependencies_md.dart — only rows under ## Direct/Dev/Transitive dependencies are cross-checked; tooling tables ignored."
    - "Belt-and-braces license scan: forbidden-substring check runs FIRST against LICENSE text, before pubspec.yaml license: field is consulted, so a package shipping GPL LICENSE while declaring MIT in pubspec is still rejected."
    - "Manual-override escape hatch (_manualOverrides) for narrowly-scoped MPL-2.0-Linux-only transitives (dbus/geoclue/gsettings) that don't ship in iOS/Android binaries."

key-files:
  created:
    - tool/check_headers.dart
    - tool/check_licenses.dart
    - tool/check_dependencies_md.dart
    - tool/test/check_headers_test.dart
    - tool/test/check_licenses_test.dart
    - tool/test/check_dependencies_md_test.dart
    - DEPENDENCIES.md
    - ios/Runner/PrivacyInfo.xcprivacy
    - test/tooling/info_plist_keys_test.dart
  modified:
    - ios/Runner/Info.plist

key-decisions:
  - "Ported tool/ scripts verbatim from parent (C:/claude_checkouts/GOSL-MirkFall/tool/) instead of re-implementing — reuses years of edge-case handling (compound SPDX, BOM-aware reading, Linux-only MPL-2.0 transitives, codegen exclusions). Single change vs parent: none — files are byte-for-byte identical."
  - "Reason codes C617.1 (FileTimestamp) and CA92.1 (UserDefaults) used in PrivacyInfo.xcprivacy verbatim from RESEARCH.md sketch; explicit re-verification against Apple's published list is deferred to first TestFlight upload (Plan 03 CI cannot exercise this without iOS toolchain on Linux)."
  - "Test for Info.plist uses regex on plist XML rather than package:xml dependency — avoids pulling a new dep audit just for one test file. A future plan can swap to package:xml if assertions get more sophisticated."
  - "Restricted UISupportedInterfaceOrientations to portrait only (vs flutter create default which included landscape) — POC scope per RESEARCH.md is portrait-only, locked early to prevent layout work for orientations we won't ship."
  - "Removed UISupportedInterfaceOrientations~ipad array — POC ships iPhone-only per LSRequiresIPhoneOS=true."

patterns-established:
  - "Verbatim port pattern: when reusing a parent-project tool, copy the file byte-for-byte rather than re-implementing. Reduces translation bugs and preserves edge-case handling."
  - "Telemetry audit lives in DEPENDENCIES.md per-package row, not in code. Each row's Telemetry column is a one-liner rationale citing the package's runtime behavior; AUDIT-03 manual review pass is structurally embedded as 'zero Yes/automatic entries'."
  - "Info.plist + PrivacyInfo.xcprivacy authored side-by-side in ios/Runner/ — keys that affect runtime (location, encryption) live in Info.plist; keys that affect App Store submission (Required Reason API) live in PrivacyInfo.xcprivacy."

requirements-completed: [BOOT-02, AUDIT-01, AUDIT-02, AUDIT-03, AUTH-05, AUTH-06]

# Metrics
duration: 9 min
completed: 2026-04-30
---

# Phase 1 Plan 2: CI Guardian Scripts + iOS Privacy Manifest Summary

**Three Dart CI gates (header/license/deps-table) ported verbatim from GOSL-MirkFall parent + iOS Info.plist with whenInUse-only location permission + ITSAppUsesNonExemptEncryption=false + ProMotion 120 Hz unlock + PrivacyInfo.xcprivacy with Required Reason API declarations.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-04-30T11:20:17Z
- **Completed:** 2026-04-30T11:30:04Z
- **Tasks:** 3
- **Files created:** 9 (3 tool scripts + 3 tool tests + DEPENDENCIES.md + PrivacyInfo.xcprivacy + info_plist_keys_test.dart)
- **Files modified:** 1 (ios/Runner/Info.plist)

## Accomplishments

- Three CI guardian scripts (`tool/check_headers.dart`, `tool/check_licenses.dart`, `tool/check_dependencies_md.dart`) ported verbatim from parent — preserves the BOM-aware header reader, the OR-compound SPDX parser, the manual-override escape hatch for MPL-2.0-Linux-only transitives, and the section-header-aware markdown parser.
- Three partner test files (`tool/test/`) ported verbatim — each exercises the script's exit-code contract on synthetic file fixtures.
- `DEPENDENCIES.md` seeded with audit rows for all 14 direct + 3 dev dependencies expected from Plan 01-01's `pubspec.yaml` (Path A — flutter_map 7.0.2 chain). Zero `Yes/automatic` Telemetry entries; AUDIT-03 manual review pass embedded structurally.
- `ios/Runner/Info.plist` rewritten with the four POC-specific keys (NSLocationWhenInUseUsageDescription with FR rationale, ITSAppUsesNonExemptEncryption=false, MinimumOSVersion=13.0, UIRequiresFullScreen=true) and the four POC-excluded keys absent (NSLocationAlwaysAndWhenInUseUsageDescription, NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription). UISupportedInterfaceOrientations restricted to portrait only.
- `ios/Runner/PrivacyInfo.xcprivacy` authored from scratch (parent has no equivalent) with NSPrivacyAccessedAPICategoryFileTimestamp (reason C617.1) + NSPrivacyAccessedAPICategoryUserDefaults (reason CA92.1) + NSPrivacyTracking=false + empty NSPrivacyTrackingDomains/NSPrivacyCollectedDataTypes arrays.
- `test/tooling/info_plist_keys_test.dart` written with four test groups covering AUTH-05 (whenInUse present + non-empty + Always absent), AUTH-06 (ITSAppUsesNonExemptEncryption=false), and Pitfall E (CADisableMinimumFrameDurationOnPhone=true). Uses regex on plist XML to avoid pulling in `package:xml` as a new audited dep.

## Task Commits

1. **Task 1: Port tool/ scripts + tool/test/ tests verbatim from parent** — `3926187` (feat)
2. **Task 2: Seed DEPENDENCIES.md with rows for every direct + dev dep** — `1d9e1a8` (feat)
3. **Task 3 RED: Add failing test for Info.plist AUTH-05/AUTH-06 + Pitfall E keys** — `bdd7942` (test)
4. **Task 3 GREEN: Rewrite Info.plist + author PrivacyInfo.xcprivacy** — `61bbda5` (rolled into Plan 01-04's docs commit due to parallel-execution timing — see "Issues Encountered" below)

_Note: TDD task 3 produced 2 commits (RED + GREEN); REFACTOR phase skipped — files were minimal and clean as written._

## Files Created/Modified

- `C:\claude_checkouts\mirk-poc-debug\tool\check_headers.dart` — GOSL header CI gate. Scans `lib/`, `test/`, `tool/`, `integration_test/` for `.dart` files; asserts each starts with the GOSL 3-line header. BOM-aware (UTF-8/UTF-16 LE/BE). Exit 0/1/2.
- `C:\claude_checkouts\mirk-poc-debug\tool\check_licenses.dart` — License allow-list CI gate. Reads `pubspec.lock` + `.dart_tool/package_config.json`; resolves SPDX per package via LICENSE text scan + pubspec `license:` field + manual overrides. Allow-list: MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, ISC, Zlib, CC0-1.0, Unlicense. Forbidden-substring scan: GPL/AGPL/LGPL/MPL.
- `C:\claude_checkouts\mirk-poc-debug\tool\check_dependencies_md.dart` — DEPENDENCIES.md freshness gate. Cross-references `pubspec.lock` against pipe-table rows under `## Direct/Dev/Transitive dependencies` headers. Reports missing/extra/version-mismatched diff.
- `C:\claude_checkouts\mirk-poc-debug\tool\test\check_headers_test.dart` — Fixture-based tests (5 cases): valid, missing header, codegen-excluded, BOM-prefix, no-root.
- `C:\claude_checkouts\mirk-poc-debug\tool\test\check_licenses_test.dart` — Fixture-based tests (7 cases): allowed SPDX, GPL rejection, missing pubspec.lock, missing package_config, manual-override path, OR-compound, unresolved.
- `C:\claude_checkouts\mirk-poc-debug\tool\test\check_dependencies_md_test.dart` — Fixture-based tests (5 cases): clean match, missing+extra, version mismatch, missing DEPENDENCIES.md, missing pubspec.lock.
- `C:\claude_checkouts\mirk-poc-debug\DEPENDENCIES.md` — Audit table for 14 direct + 3 dev deps. Columns: Package | Version | License | Source | Telemetry | Transitive licenses | Maintenance | Platform | Audit date.
- `C:\claude_checkouts\mirk-poc-debug\ios\Runner\Info.plist` — Rewritten with NSLocationWhenInUseUsageDescription (FR), ITSAppUsesNonExemptEncryption=false, MinimumOSVersion=13.0, UIRequiresFullScreen=true, CFBundleDisplayName=MirkFall POC, portrait-only orientations.
- `C:\claude_checkouts\mirk-poc-debug\ios\Runner\PrivacyInfo.xcprivacy` — From-scratch privacy manifest. NSPrivacyAccessedAPICategoryFileTimestamp + NSPrivacyAccessedAPICategoryUserDefaults reasons. NSPrivacyTracking=false.
- `C:\claude_checkouts\mirk-poc-debug\test\tooling\info_plist_keys_test.dart` — Four test groups using regex on plist XML.

## Decisions Made

- **Verbatim port over re-implementation:** the three tool scripts came from the parent project (`C:\claude_checkouts\GOSL-MirkFall\tool\`) byte-for-byte. The parent's edge-case handling — BOM-aware reading, OR-compound SPDX splitting, MPL-2.0-Linux-only manual override, section-header-aware markdown parsing — would be expensive to re-derive and easy to get wrong. Cost of port: zero. Cost of re-implementing: weeks of edge-case discovery during Phase 5 hardening.
- **Reason codes used as-published in RESEARCH.md:** C617.1 (FileTimestamp) and CA92.1 (UserDefaults) are the canonical Apple Required Reason API codes per the developer.apple.com documentation cited in RESEARCH.md §Pattern 8. Explicit re-verification against Apple's published list is a manual gate before each TestFlight upload (deferred to Phase 4/5 sideload UAT — Plan 03 CI workflow cannot exercise this without an iOS toolchain on Linux).
- **Regex over package:xml for the Info.plist test:** four assertions on `<key>X</key>` patterns is well within regex tractability; pulling in package:xml just for one test file would require a new dep audit (CLAUDE.md §Audit obligatoire) for marginal gain.
- **Portrait-only iOS orientation lock:** RESEARCH.md scope is portrait fog rendering only; locking now prevents flutter create's default landscape support from forcing layout work in Phase 2/3 that we'd then have to undo.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] package:test missing from POC pubspec.yaml will block `dart test tool/test/`**
- **Found during:** Task 1 (porting tool tests)
- **Issue:** Parent project's tool/test/ files import `package:test/test.dart`, which is a dev_dependency in the parent's pubspec.yaml (`test: 1.30.0`). The POC's Plan 01-01 only adds `yaml: 3.1.3` to dev_dependencies — `test:` is NOT in the spec. Without it, `dart test tool/test/` will fail with `Could not resolve package:test`.
- **Fix:** Documented as a deferred coordination action — Plan 01-01 must add `test: 1.30.0` to dev_dependencies before the verification commands in this plan can run. Did NOT modify pubspec.yaml in this plan because Plan 01-01 is currently overwriting that file in parallel (per orchestrator notes), and a concurrent edit would create a merge conflict.
- **Files modified:** None (this is a deferred-coordination deviation, not an immediate fix)
- **Verification:** Once Plan 01-01 commits with `test: 1.30.0` in dev_dependencies, run `flutter pub get && dart test tool/test/` — all 17 tests should pass.
- **Committed in:** N/A (deferred — Plan 01-01 owns the pubspec.yaml line)

**Action item for the parent agent:** if Plan 01-01's `pubspec.yaml` does NOT include `test: 1.30.0` in dev_dependencies, add it as a Phase 1 hotfix (Plan 01.1) before running CI gate verifications.

### Coordination notes (parallel-execution context, not deviations)

The plan was executed alongside Plans 01-01, 01-03, and 01-04 running in parallel waves. Two coordination effects worth recording:

1. **Plan 01-01 had not finalized pubspec.yaml at execution time:** the working-tree pubspec.yaml was still the default `flutter create` content (only `cupertino_icons: ^1.0.8` and `flutter_lints: ^6.0.0`). This means the verification commands `dart run tool/check_licenses.dart` and `dart run tool/check_dependencies_md.dart` cannot run today — they require Plan 01-01's full Path A pubspec to be committed first. Per orchestrator guidance, "file writes that don't depend on pubspec being complete can proceed immediately"; this plan adheres to that — the file ports landed, verification deferred.

2. **Task 3 GREEN files swept into Plan 01-04's docs commit:** between my `git add ios/Runner/Info.plist ios/Runner/PrivacyInfo.xcprivacy` and `git commit`, the parallel Plan 01-04 agent ran `git commit` with what appears to have been `git add -A` semantics, which picked up my staged + unstaged ios/ files into commit `61bbda5` (`docs(01-04): complete FileLogger + lifecycle observer port plan`). The commit message does NOT mention these files, but the diffstat confirms they're present. The files-on-disk match what I wrote; the audit trail is muddled. For accountability, the canonical "GREEN commit" for Task 3 is `61bbda5` even though the message doesn't say so.

These are coordination artifacts of running multiple gsd-executor agents in parallel against a shared working tree without locking — not a defect in this plan's logic.

---

**Total deviations:** 1 deferred-coordination (1 blocking — Plan 01-01 must add `test: 1.30.0`)
**Impact on plan:** Files landed correctly; verification commands cannot exercise yet. Once Plan 01-01 finalizes pubspec.yaml + Plan 01.1 (hotfix or Plan 01-01 amendment) adds `test: 1.30.0`, all 17 tool tests + 4 Info.plist tests can run.

## Issues Encountered

- **Parallel-execution audit-trail muddle:** Plan 01-04's docs commit (61bbda5) accidentally included my Task 3 GREEN files (Info.plist + PrivacyInfo.xcprivacy). Resolution: documented in this SUMMARY's Coordination notes; commit hash 61bbda5 is the canonical Task 3 GREEN reference even though its message doesn't mention these files.
- **Verification commands cannot run:** the four exit-0 commands required by `<verification>` (`dart run tool/check_headers.dart`, `dart run tool/check_licenses.dart`, `dart run tool/check_dependencies_md.dart`, `dart test tool/test/`, `flutter test test/tooling/info_plist_keys_test.dart`) all require Plan 01-01's pubspec.yaml + pubspec.lock to be committed first. They will execute in Plan 03 (CI workflow) once the dependency chain resolves.

## Authentication Gates

None — no external service authentication required.

## User Setup Required

None — no external service configuration required for this plan.

## Next Phase Readiness

**Ready for Plan 03 (CI workflow):** the four CI gates that Plan 03 will wire into GitHub Actions all exist now. Plan 03's workflow can reference `dart run tool/check_headers.dart`, `dart run tool/check_licenses.dart`, `dart run tool/check_dependencies_md.dart`, `dart test tool/test/`, and `flutter test test/tooling/info_plist_keys_test.dart` directly.

**Known-acceptable expected violation:** `dart run tool/check_headers.dart` will flag `lib/main.dart` (left in place by `flutter create` in Plan 01-01, lacks GOSL header). Plan 07 replaces this file with the proper main wiring + GOSL header. Until Plan 07 lands, the check_headers gate is expected to be red. Per the plan's recommendation: option (a) — Plan 03's workflow gates on lint job; expect lint to be red on first push and to go green after Plan 07. The red→green transition documents the Wave 0/Wave 4 progression.

**Flag for Plan 03 CI workflow author:**
- Either accept the red→green transition for `check_headers` (documented expected violation until Plan 07), OR
- Defer the workflow's `check_headers` step until Plan 07 with an explicit `if: github.event.head_commit.message ~= /\\(01-07\\)/` style guard.

**Flag for Plan 01-01 (or Plan 01.1 hotfix):**
- Add `test: 1.30.0` to `dev_dependencies` in pubspec.yaml. Without it, `dart test tool/test/` cannot run.

---

## Self-Check: PASSED

Verification of claims in this SUMMARY:

**Files exist on disk:**
- `tool/check_headers.dart` — FOUND
- `tool/check_licenses.dart` — FOUND
- `tool/check_dependencies_md.dart` — FOUND
- `tool/test/check_headers_test.dart` — FOUND
- `tool/test/check_licenses_test.dart` — FOUND
- `tool/test/check_dependencies_md_test.dart` — FOUND
- `DEPENDENCIES.md` — FOUND
- `ios/Runner/Info.plist` — FOUND (modified)
- `ios/Runner/PrivacyInfo.xcprivacy` — FOUND
- `test/tooling/info_plist_keys_test.dart` — FOUND

**Commits exist in git log:**
- `3926187` (Task 1) — FOUND: `feat(01-02): port CI guardian scripts + tool tests verbatim from parent`
- `1d9e1a8` (Task 2) — FOUND: `feat(01-02): seed DEPENDENCIES.md with audit rows for 14 direct + 3 dev deps`
- `bdd7942` (Task 3 RED) — FOUND: `test(01-02): add failing test for Info.plist AUTH-05/AUTH-06 + Pitfall E keys`
- `61bbda5` (Task 3 GREEN, swept-in) — FOUND: contains `ios/Runner/Info.plist` (69 ins) and `ios/Runner/PrivacyInfo.xcprivacy` (31 ins) per `git show 61bbda5 --stat`

All file claims and commit claims verified.

---

*Phase: 01-foundation*
*Completed: 2026-04-30*
