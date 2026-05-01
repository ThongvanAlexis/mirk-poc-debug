---
phase: 3
slug: fog-of-war-the-hypothesis
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-01
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (Flutter SDK 3.41.7) + `test: 1.30.0` (already pinned for `tool/test/`) |
| **Config file** | `analysis_options.yaml` (strict-casts/inference/raw-types); no separate test config |
| **Quick run command** | `flutter test test/presentation/widgets/fog_layer_test.dart -r expanded` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~60 seconds full suite at Phase 3 scale (baseline ~5 s pre-Phase-3) |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/{paths added by the task} -r expanded` (≤30 s per-task subset)
- **After every plan wave:** Run `flutter test` (full suite — ≤60 s at Phase 3 scale)
- **Before `/gsd:verify-work`:** Full suite green + `flutter analyze` zero warnings + `dart format --line-length 160 --set-exit-if-changed .` clean + LOC-03 / BOOT-02 CI gates green + manual UAT walk gates (PERF-03/04/05) signed off
- **Max feedback latency:** 60 seconds (full suite); 30 seconds (per-task subset)

---

## Per-Task Verification Map

> Filled in by gsd-planner during plan creation. Each task in each PLAN.md must reference a Test ID below or declare `<manual>` with justification. The planner is responsible for:
> - Mapping each task to a row here (Plan / Wave / Requirement / Test Type / Command)
> - Marking files that don't exist yet with `❌ W0` (Wave 0 will create them)
> - Filling Status to ⬜ pending at plan-creation time

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| _TBD by planner_ | — | — | FOG-01..08, PERF-03..05 | unit / widget / manual | _per task_ | _per task_ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Test files to be created in Wave 0 (before any production code in later waves):

- [ ] `test/presentation/widgets/fog_layer_test.dart` — covers FOG-04 (MobileLayerTransformer ancestor)
- [ ] `test/presentation/widgets/fog_layer_camera_snapshot_test.dart` — covers FOG-07 (single-MapCamera invariant; THE KEYSTONE TEST per CONTEXT.md)
- [ ] `test/presentation/widgets/fog_clip_path_test.dart` — covers FOG-06 (clip-path geometry)
- [ ] `test/domain/revealed/reveal_disc_repository_test.dart` — covers FOG-01 (append / snapshot / ChangeNotifier semantics)
- [ ] `test/domain/revealed/distance_metres_test.dart` — covers FOG-02 defence (`distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km` — degree-vs-meter regression)
- [ ] `test/infrastructure/mirk/sdf/sdf_cache_test.dart` — covers FOG-03 cache hit/miss correctness
- [ ] `test/infrastructure/mirk/sdf_rebuild_logger_test.dart` — covers FOG-03 logger JSONL rollup
- [ ] `test/infrastructure/mirk/shader/fog_shader_uniforms_test.dart` — covers FOG-05 slot count (`totalFloatSlots == 41`); existing donor test from BOOT-08 may already partially cover; verify and extend
- [ ] `test/infrastructure/mirk/frame_delta_probe_test.dart` — covers FOG-08 probe rollup correctness + monotonic-timestamp guard
- [ ] `test/presentation/screens/map_screen_fog_test.dart` — covers MapScreen integration: GPS fix → `discRepository.append`; `_fogShader` lifecycle; FogLayer mounting

**Test seams that need engineering (responsibility of Wave 0 planner):**
- **MapCamera test seam.** Mounting a `FogLayer` in a widget test without a real `FlutterMap` requires either (a) a parent that provides a fake `MapCamera` via the inherited-widget pattern, or (b) a full `pumpWidget(FlutterMap(... children: [FogLayer(...)]))`. Recommend (a) for unit-style FogLayer tests + (b) for the camera-snapshot integration test.
- **FragmentShader test seam.** `ui.FragmentShader` is hard to instantiate in a test environment (the ShaderProgram needs a real GPU). Solution: a `FogShaderRenderer` interface that wraps `setAll` calls; production impl delegates to `FogShaderUniforms.setAll`; test impl records the (slot-index, float-value) pairs. Tests assert the recorded list contains exactly 41 floats + 1 sampler set, and that no `MapCamera` was re-read between calls.
- **Position-stream fake.** Phase 2 already established `_CapturingGeolocatorPlatform` (Plan 02-03). Phase 3 reuses it for the GPS-fix-to-disc-append integration test.

**Framework install:** None needed — `flutter_test` is in the SDK and `test: 1.30.0` is already pinned in `pubspec.yaml`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Pre-walk shader-sanity gate: `/sanity` route renders fog with hardcoded uniforms; circular reveal hole visible; no FileLogger exceptions | Pre-walk gate (Success Criterion 1) | POC has no `flutter_test` golden infrastructure; single screen / single frame — visual confirmation by developer is faster and cheaper than building a golden harness | Sideload IPA on iPhone 17 Pro, navigate to `/sanity`, observe expected fog rendering, check FileLogger for clean run |
| Pan-FPS with fog active ≥ 30 and idle-fog-animation FPS ≥ 50 | PERF-03 | Inherently requires real iPhone 17 Pro at outdoor GPS coordinates (Melun) with developer's hand performing combined gestures | Sideload IPA, walk ≥ 5 min through Melun with ≥ 10 deliberate combined pinch-zoom-and-pan gestures and ≥ 3 recenter taps; observe in-app FPS overlay; persist session log |
| Frame-delta probe (FOG-08): rolling median camera-to-fog-paint delta ≤ 16 ms, p95 ≤ 32 ms, max ≤ 48 ms | PERF-04 | Same as PERF-03 — requires real walk with real gestures on real device | Sideload IPA, walk per PERF-03 protocol, observe in-app frame-delta overlay, grep persisted JSONL session log for the rollup numbers |
| Subjective verdict: no fog slide-then-snap, no white-ellipse artefact during fast pinch-zoom, no perceptible reveal-hole lag behind blue dot, no inversion at any zoom level | PERF-05 | Subjective visual judgement of architectural correctness — no automated proxy exists | Same walk as PERF-03; developer's verbal `approved` at end + written notes in falsification document |
| Falsification criteria document: Criterion A (frame-delta thresholds), Criterion B (subjective lock); Criterion C dropped per locked decisions; written BEFORE the walk and walk evidence appended AFTER | Success Criterion 5 | Document discipline — pre-commit before walk, append-only after | Planner produces falsification document path; Wave 0 commits the pre-walk version; final wave appends walk evidence (probe rollup + subjective notes) before phase verify-work |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify (Wave 0 test files exist) or are listed in Manual-Only above with explicit justification
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (planner enforces during PLAN.md creation)
- [ ] Wave 0 covers all MISSING references — every Wave 0 file above is a Wave 0 task in Plan 01
- [ ] No watch-mode flags (`flutter test` runs once and exits, never `--watch`)
- [ ] Feedback latency < 60 s (full suite) / < 30 s (per-task subset)
- [ ] Falsification document exists in repo BEFORE walk (Criteria A + B written down)
- [ ] Walk evidence appended to falsification document AFTER walk (probe rollup + subjective notes)
- [ ] `nyquist_compliant: true` set in frontmatter once gsd-plan-checker confirms full coverage

**Approval:** pending
