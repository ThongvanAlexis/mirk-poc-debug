---
phase: 5
slug: decision-gate
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-05
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 5 is **non-feature work** (verdict + hardening + sanity walks). Existing test infrastructure + 7 CI gates cover every automatable success criterion; PERF-06 closure is manual-only by definition (sideload walk on physical Pixel 4a).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (SDK) + `package:test` 1.30.0 (for `dart test tool/test/`) |
| **Config file** | `analysis_options.yaml` + defaults (no `dart_test.yaml`) |
| **Quick run command** | `flutter test --plain-name <pattern>` |
| **Full suite command** | `flutter test && dart test tool/test/` (211+ flutter tests + 18 tool tests) |
| **Estimated runtime** | ~90 seconds (full suite); ~2 seconds (quick) |
| **CI workflow** | `.github/workflows/ci.yml` — 7 gates (format, analyze, GOSL header, license allow-list, DEPENDENCIES.md freshness, tool tests, flutter tests) |

---

## Sampling Rate

- **After every task commit:** `dart format --line-length 160 --set-exit-if-changed <touched files>` + `flutter analyze` (touched files); for tool changes: `dart test tool/test/check_<X>_test.dart`
- **After every plan wave:** Full hardening sweep:
  ```
  dart format --line-length 160 --set-exit-if-changed . \
    && flutter analyze --fatal-infos --fatal-warnings \
    && flutter test \
    && dart test tool/test/ \
    && dart run tool/check_headers.dart \
    && dart run tool/check_licenses.dart \
    && dart run tool/check_dependencies_md.dart
  ```
- **Before each Phase 5 walk:** Full suite must be green on `main` HEAD; CI run must be green; APK/IPA pulled from CI artefacts (not local build).
- **Before VERDICT.md commit:** Both walk-evidence files must exist and be linked from VERDICT.md.
- **Max feedback latency:** ~90 seconds (full suite); ~5 seconds (per-tool check).

---

## Per-Task Verification Map

*Task IDs finalised 2026-05-05 by /gsd:plan-phase 5. Pattern: 05-NN-T where NN = plan number, T = task number within plan.*

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-1 | 01 (DEPENDENCIES re-audit + hardening sweep) | 1 | SC #3 (audit dates current + 7-gate hardening) | unit/CI | `flutter test && flutter analyze --fatal-infos --fatal-warnings && dart format --line-length 160 --set-exit-if-changed . && dart run tool/check_headers.dart && dart run tool/check_licenses.dart && dart run tool/check_dependencies_md.dart && dart test tool/test/` | ✅ existing | ⬜ pending |
| 05-02-1 | 02 (iPhone Walk #1 — pre-walk skeleton) | 2 | SC #1 prep (gates + IPA download + skeleton docs) | unit/CI | `flutter test && flutter analyze --fatal-infos --fatal-warnings && dart run tool/check_headers.dart && dart run tool/check_dependencies_md.dart && test -f .planning/phases/05-decision-gate/05-FALSIFICATION-1.md` | ✅ existing | ⬜ pending |
| 05-02-2 | 02 (iPhone Walk #1 — sideload + walk + Mail-share) | 2 | SC #1 (re-confirm fog + wisps + share-logs + FPS counter + C3' + UX-02 + Mail-share) | manual-only | sideload via SideStore + WalkSimulator AppBar + 8-step walk + Mail-share | manual-only | ⬜ pending |
| 05-02-3 | 02 (iPhone Walk #1 — JSONL extract + verdict) | 2 | SC #1 evidence (5 streams + per-criterion verdict) | doc-presence + grep | `test -s walk-evidence/iphone-walk-1/frame_delta.jsonl && grep -qE "verdict: (CONFIRMED-AFTER-FIX\|ITERATING\|DENIED)" .planning/phases/05-decision-gate/05-FALSIFICATION-1.md` | created by walk | ⬜ pending |
| 05-03-1 | 03 (Pixel 4a Walk #1 — pre-walk + APK + Pitfall 1 logcat) | 2 | PERF-06 prep (gates + APK + 30 s logcat sanity) | unit/CI + adb | `flutter test && adb devices && adb install -r <apk>` + 30 s logcat capture | ✅ existing + manual | ⬜ pending |
| 05-03-2 | 03 (Pixel 4a Walk #1 — sideload + walk + Mail-share) | 2 | PERF-06 / SC #2 (cross-platform sanity) | manual-only | adb install + WalkSimulator AppBar + 10-step walk + Android sharesheet (Gmail) | manual-only | ⬜ pending |
| 05-03-3 | 03 (Pixel 4a Walk #1 — JSONL extract + verdict) | 2 | PERF-06 evidence (5 streams + soft-criterion outcome) | doc-presence + grep | `grep -qE "verdict: (CONFIRMED-PERF-06\|LAUNCH-CRASH-CAVEAT\|PARTIAL-PERF-06\|OTHER)" .planning/phases/05-decision-gate/05-PIXEL4A-FALSIFICATION-1.md && test -f .planning/phases/05-decision-gate/walk-evidence/pixel4a-walk-1/initial-launch-logcat.txt` | created by walk | ⬜ pending |
| 05-04-1 | 04 (VERDICT.md authoring) | 3 | SC #4 (verdict doc committed at repo root) | doc-presence + plan-checker review | `test -f VERDICT.md && grep -q "PORT BACK" VERDICT.md && grep -q "HYPOTHESIS CONFIRMED-AFTER-FIX" VERDICT.md && grep -q "iPhone 17 Pro" VERDICT.md && grep -q "Pixel 4a" VERDICT.md && grep -q "3.41.7" VERDICT.md` | manual (authored in this plan) | ⬜ pending |
| 05-04-2 | 04 (PORTBACK.md authoring) | 3 | SC #4 (portback doc committed at repo root) | doc-presence + plan-checker review | `test -f PORTBACK.md && grep -q "ABI extensions" PORTBACK.md && grep -q "uPixelOrigin" PORTBACK.md && grep -q "uZoomScale" PORTBACK.md` | manual (authored in this plan) | ⬜ pending |
| 05-05-1 | 05 (STATE/ROADMAP/REQUIREMENTS cascade) | 4 | (closure) | doc-presence + grep | `grep -q "Phase 5.*Complete" .planning/ROADMAP.md && grep -q "POC CLOSED" .planning/ROADMAP.md && grep -qE "PERF-06.*Complete" .planning/REQUIREMENTS.md` | manual | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*All "manual-only" rows are inherent to PERF-06 (cross-platform sanity is by definition device-bound) and SC #4 (verdict authoring is a human judgement call against walk evidence).*

---

## Wave 0 Requirements

**None — existing test infrastructure covers all Phase 5 requirements.**

- Phase 5 ships zero new feature code; zero RED-cycle tests required.
- The 7 existing CI gates (`.github/workflows/ci.yml`) cover every automatable "hardening passes" success criterion.
- `tool/check_headers.dart` + `tool/check_licenses.dart` + `tool/check_dependencies_md.dart` are present, GOSL-headered, and tested under `tool/test/`.
- WalkSimulator (`lib/infrastructure/location/walk_simulator.dart`, commit `eec9087`) is production-exposed via AppBar — covers the simulated-walk leg of both Phase 5 walks.
- Mail-share + JSONL streams (FOG-19, fog/wisp logging) already exercised in P3.1 + P4 walks.

*Wave 0 is marked complete in frontmatter (`wave_0_complete: true`) since no setup work is required.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| iPhone 17 Pro fog lock + wisp anchoring + ≥ 30 fps + share-logs round-trip + FPS counter visible | SC #1 | Physical device walk on real iPhone 17 Pro hardware; reconfirms P3.1 + P4 closure under combined load | (1) `gh run download <run-id> --name mirk-poc-debug-ios-debug-ipa`; (2) sideload via AltStore/Sideloadly; (3) launch app, enable WalkSimulator from AppBar; (4) drive 5-min loop with fog + wisps + FPS overlay visible; (5) Mail-share logs at end; (6) save mail .zip → `.planning/phases/05-decision-gate/walk-evidence/iphone-walk-1/`; (7) grep JSONL for fog frame-deltas, wisp coords, FPS samples; (8) write `05-FALSIFICATION-1.md` per P3.1 template |
| Pixel 4a (Adreno 618) launch + fog renders + wisps render + 5-min walk no crash + informational FPS | PERF-06 / SC #2 | Physical device walk on real Pixel 4a hardware; cross-platform sanity gate; Adreno 618 + Impeller is documented risk territory | (1) `gh run download <run-id> --name mirk-poc-debug-android-debug-apk`; (2) `adb install`; (3) pre-launch sanity: `adb logcat \| grep -E "Flutter\|Impeller\|Vulkan\|SIGSEGV"` for 30 s after app launch; (4) if launches: enable WalkSimulator, run 5-min loop, Mail-share logs; (5) if crashes/glitches: capture logcat, screenshot, document outcome as VERDICT caveat (not a verdict-blocker — PERF-06 is informational); (6) write `05-PIXEL4A-FALSIFICATION-1.md` |
| VERDICT.md content correctness (hypothesis confirmed/denied + frame-delta numbers + iPhone model + Flutter version + MirkFall recommendation) | SC #4 | Human judgement call against walk evidence; cannot be auto-generated | Plan-checker review: verify all 6 sections present (header, hypothesis statement, evidence, walk results, caveats, MirkFall recommendation); cross-check frame-delta numbers against Phase 3.1 closure-walk JSONL; cross-check Flutter version against `pubspec.yaml` Flutter pin; cross-check iPhone model against walk-evidence file |
| PORTBACK.md content correctness (9 sections covering ABI, shaders, Wisp pipeline, etc.) | SC #4 | Human authoring against P3.1 + P4 implementation | Plan-checker review: verify all 9 sections present per CONTEXT spec; cross-check ABI uniform list against `lib/.../foggy_canvas_painter.dart` + atmospheric_fog.frag; cross-check Wisp pipeline notes against P4 plans |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or are manual-only by-design (PERF-06 + SC #4 are inherently device-bound / human-judgement)
- [x] Sampling continuity: every wave has at least one CI-automated check (per-task or per-wave)
- [x] Wave 0 covers all MISSING references — N/A, none missing (`wave_0_complete: true`)
- [x] No watch-mode flags in commands above
- [x] Feedback latency < 120 s (full suite ~90 s)
- [x] `nyquist_compliant: true` set in frontmatter — flipped 2026-05-05 by /gsd:plan-phase 5; task IDs finalised across 5 plans / 4 waves

**Approval:** APPROVED 2026-05-05 — Per-Task Verification Map task IDs finalised; nyquist_compliant flipped true; ready for /gsd:execute-phase 5.
