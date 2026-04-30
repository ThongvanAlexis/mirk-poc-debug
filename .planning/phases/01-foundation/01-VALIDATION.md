---
phase: 1
slug: foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-30
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Source of truth for the per-requirement test map is the **Validation Architecture** section of `01-RESEARCH.md` (lines 1033-1112); this file restates the contract in the planner-consumable shape and is updated as plans land.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (SDK-bundled, BSD-3, no extra dep) + `dart test` for `tool/test/*` (pure-Dart scripts, no Flutter binding) |
| **Config file** | None at Phase 1 (a `dart_test.yaml` is optional; not needed for the test surface). `analysis_options.yaml` is in scope but landed via Wave 0. |
| **Quick run command** | `flutter test` |
| **Full suite command** | `flutter test && dart test tool/test/` |
| **Estimated runtime** | ~5-10 s warm cache (`flutter test`) + ~3 s (`dart test tool/test/`) ≈ ~13 s total |

---

## Sampling Rate

- **After every task commit:** Run `flutter test`
- **After every plan wave:** Run `flutter test && dart test tool/test/`
- **Before `/gsd:verify-work`:** Full suite green locally + CI all three jobs green on `main` + manual UAT walk (sideload IPA → permission grant on iPhone 17 Pro → share log via Mail → verify email arrived) + verbal "approved"
- **Max feedback latency:** ~15 seconds (full suite)

---

## Per-Task Verification Map

> Filled out by the planner once tasks are decomposed. Each row maps a `{N}-{plan}-{task}` task ID to its requirement, test type, and the automated command (or manual instructions). Pre-decomposition, the per-requirement coverage from `01-RESEARCH.md` §Validation Architecture stands.

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| _filled by planner_ | — | — | — | — | — | — | ⬜ pending |

**Pre-decomposition coverage (from research):**

| Req ID | Test Type | Automated Command | File Exists |
|--------|-----------|-------------------|-------------|
| BOOT-01 | unit (tool script) | `dart test tool/test/check_dependencies_md_test.dart` + supplementary regex on `pubspec.yaml` | ❌ W0 (port from parent) |
| BOOT-02 | unit (tool script) | `dart test tool/test/check_headers_test.dart` + CI `dart run tool/check_headers.dart` | ❌ W0 (port from parent) |
| BOOT-03 | smoke (CI gate) | `test -f LICENSE && grep -q "Good Old Software License" LICENSE` (CI step) | ❌ W0 (manual write) |
| BOOT-04 | unit (analyzer) | `flutter analyze --fatal-infos --fatal-warnings` (CI step) | ❌ W0 |
| BOOT-05 | unit (CI step) | `dart format --line-length 160 --set-exit-if-changed .` | ❌ W0 |
| BOOT-06 | unit (CI step) | `flutter analyze` | ❌ W0 |
| BOOT-07 | smoke | `flutter test test/assets/asset_bundle_test.dart` | ❌ W0 (new test file) |
| BOOT-08 | unit | covered by `check_headers` + `flutter analyze` once files land | ❌ W0 |
| AUDIT-01 | unit (tool script) | `dart test tool/test/check_dependencies_md_test.dart` + CI runner | ❌ W0 (port from parent) |
| AUDIT-02 | unit (tool script) | `dart test tool/test/check_licenses_test.dart` + CI runner | ❌ W0 (port from parent) |
| AUDIT-03 | manual-only | per-package telemetry audit captured in `DEPENDENCIES.md`; cannot be unit-tested in Dart | manual review |
| CI-01 | smoke (CI itself) | `gh run list --workflow=ci.yml --limit 1` after push shows three jobs | ❌ W0 (workflow file) |
| CI-02 | unit (CI step) | workflow YAML correctness; verify on first push | ❌ W0 |
| CI-03 | smoke (CI artifact) | `gh run download $RUN_ID --name mirk-poc-debug-android-debug-apk` returns the APK | ❌ W0 |
| CI-04 | smoke (CI artifact) | `gh run download $RUN_ID --name mirk-poc-debug-ios-unsigned-ipa` returns the IPA | ❌ W0 |
| CI-05 | smoke (CI artifact) | `gh run view $RUN_ID --log` shows both artifact upload steps green | ❌ W0 |
| AUTH-01 | widget | `flutter test test/presentation/screens/permission_gate_screen_test.dart` (renders icon + paragraph + CTA) | ❌ W0 (new test file) |
| AUTH-02 | widget | same file with mocked `permission_handler` — assert request invoked on tap | ❌ W0 |
| AUTH-03 | widget | same file: mock grant response, assert router moves to `/map` | ❌ W0 |
| AUTH-04 | widget | `permission_denied_screen_test.dart` — renders + button calls `openAppSettings` | ❌ W0 |
| AUTH-05 | unit (tool script) | `dart test test/tooling/info_plist_keys_test.dart` (parses Info.plist, asserts `NSLocationWhenInUseUsageDescription` present + `NSLocationAlwaysAndWhenInUseUsageDescription` absent) | ❌ W0 (new test file) |
| AUTH-06 | unit (tool script) | same `info_plist_keys_test.dart` (asserts `ITSAppUsesNonExemptEncryption=false`) | ❌ W0 |
| LOG-01 | unit | `flutter test test/infrastructure/logging/file_logger_test.dart` (bootstrap → file exists at expected path with expected filename pattern) using `path_provider_platform_interface` mock | ❌ W0 (new test file) |
| LOG-02 | unit | same file — assert `Logger.root.level == Level.ALL`; assert ms-precision `ts` field round-trips | ❌ W0 |
| LOG-03 | smoke | manually verified by `main.dart` ordering; no productive automated test | manual review |
| LOG-04 | widget | `flutter test test/presentation/widgets/poc_app_bar_test.dart` — every Scaffold variant renders the share IconButton with correct tooltip | ❌ W0 |
| LOG-05 | manual-only | sideload IPA → tap share → pick Mail → verify email arrived with gzipped log file. **This IS the Phase 1 UAT exit gate** per CONTEXT.md decision. | manual UAT walk |
| PERF-01 | widget + manual | `fps_counter_overlay_test.dart` (renders, contains "fps" + "Hz", refresh rate from mocked `PlatformDispatcher`) + manual screenshot/video evidence on iPhone 17 Pro | ❌ W0 |

---

## Wave 0 Requirements

Establish before any application code lands (fresh Flutter repo — no test infrastructure exists yet):

- [ ] `pubspec.yaml` with `dev_dependencies: flutter_test` (SDK) + `flutter_lints 6.0.0` + `yaml 3.1.3`
- [ ] `analysis_options.yaml` (STACK.md §12 verbatim + `use_build_context_synchronously: error`)
- [ ] `tool/check_headers.dart` (port verbatim from parent `C:\claude_checkouts\GOSL-MirkFall\tool\check_headers.dart`)
- [ ] `tool/check_licenses.dart` (port verbatim from parent)
- [ ] `tool/check_dependencies_md.dart` (port verbatim from parent)
- [ ] `tool/test/check_headers_test.dart` (port from parent)
- [ ] `tool/test/check_licenses_test.dart` (port from parent)
- [ ] `tool/test/check_dependencies_md_test.dart` (port from parent)
- [ ] `test/infrastructure/logging/file_logger_test.dart` — covers LOG-01, LOG-02
- [ ] `test/infrastructure/logging/file_logger_lifecycle_observer_test.dart` — covers FileLoggerLifecycleObserver flush behaviour
- [ ] `test/infrastructure/logging/file_logger_filename_format_test.dart` — covers POC adaptation #1 (UTC ISO-8601 basic)
- [ ] `test/presentation/screens/permission_gate_screen_test.dart` — covers AUTH-01, AUTH-02, AUTH-03
- [ ] `test/presentation/screens/permission_denied_screen_test.dart` — covers AUTH-04
- [ ] `test/presentation/widgets/poc_app_bar_test.dart` — covers LOG-04
- [ ] `test/presentation/widgets/fps_counter_overlay_test.dart` — covers PERF-01
- [ ] `test/assets/asset_bundle_test.dart` — covers BOOT-07 (Fra_Melun.pmtile loadable + size sanity)
- [ ] `test/tooling/info_plist_keys_test.dart` — covers AUTH-05, AUTH-06
- [ ] `.github/workflows/ci.yml` — covers CI-01 through CI-05 (CI itself is the verifier once a push lands)
- [ ] `LICENSE` (GOSL v1.0 text) — covers BOOT-03
- [ ] `DEPENDENCIES.md` skeleton with `## Direct dependencies`, `## Dev dependencies`, `## Transitive dependencies` sections — covers AUDIT-01 (rows added as deps land)
- [ ] `l10n.yaml` + `lib/l10n/app_fr.arb` + `lib/l10n/app_en.arb` — enables `AppLocalizations` codegen

**Framework install command:** none — `flutter_test` ships with the SDK; `dart test` for tool tests is also bundled.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Zero auto network egress at launch | AUDIT-03 | No in-Dart way to assert this; would need an external network proxy on the iOS device. Captured per-package in `DEPENDENCIES.md` telemetry rows; reviewed during Phase 1 doc review. | (1) For each direct dep in pubspec, inspect source for network calls at construction / app-launch path. (2) Record finding in `DEPENDENCIES.md` "Telemetry" column. (3) Doc-review pass: confirm zero `Yes/automatic` rows. |
| Logger init order before other modules | LOG-03 | Would require a binding-init mock to assert; not productive. Verified by reading `main.dart` ordering. | Read `lib/main.dart`: confirm `await FileLogger.bootstrap()` is the first `await` after `WidgetsFlutterBinding.ensureInitialized()` and before any other module call. |
| Share-to-Mail end-to-end on sideloaded iOS | LOG-05 | Requires (a) signed CI IPA, (b) physical iPhone 17 Pro, (c) SideStore install, (d) Mail app configured, (e) human visual confirmation. **This IS the Phase 1 UAT exit gate** per CONTEXT.md decision. | (1) Push to `main`, wait for CI green. (2) `gh run download $RUN_ID --name mirk-poc-debug-ios-unsigned-ipa`. (3) Sideload via SideStore on iPhone 17 Pro. (4) Launch → grant permission → land on `/map`. (5) Tap share button → pick Mail → send to self. (6) Verify email arrives with gzipped `yyyymmddTHHMMSSZ_logs.txt.gz` attachment. (7) Reply "approved". |
| FPS counter visible + correct refresh rate label on iPhone 17 Pro (ProMotion) | PERF-01 (visual) | Widget test asserts the strings render; only on-device can confirm legibility, position (top-right not occluded), and that the `120 Hz` label matches actual ProMotion. | During the UAT walk: screenshot or short video showing `60 fps / 120 Hz` (or the live current fps) overlay top-right on the `/map` screen. |
| Permission deny → "Open Settings" round-trip on iOS | AUTH-04 (round-trip) | Widget test asserts `openAppSettings()` is invoked; only on-device can confirm the actual round-trip through iOS Settings + lifecycle re-check on resume. | During the UAT walk: deny on first prompt → land on `/denied` → tap "Open Settings" → confirm iOS Settings opens at the app page → toggle permission ON → return to app → confirm auto-navigate to `/map` (lifecycle resume re-check). |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15 s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
