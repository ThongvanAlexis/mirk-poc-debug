---
phase: 4
slug: wisp-particles
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-04
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (bundled with Flutter SDK) |
| **Config file** | `pubspec.yaml` (dev_dependencies → flutter_test) |
| **Quick run command** | `flutter test test/wisp/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/wisp/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| {filled by gsd-planner} | | | | | | | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/wisp/wisp_particle_test.dart` — stubs for WISP-01 (LatLng position storage), WISP-02 (kinematic units in m/s)
- [ ] `test/wisp/wisp_particle_system_test.dart` — stubs for WISP-03 (spawn-on-new-disc gating, no-fix warm-up gate)
- [ ] `test/wisp/wisp_pan_invariance_test.dart` — Success Criterion #1: 100 m camera pan does NOT change wisp LatLng; projected screen Offset moves by corresponding pixel delta
- [ ] `test/wisp/wisp_no_fix_warmup_test.dart` — Success Criterion #2: no wisps during 5 s warm-up; no wisps at synthetic (0, 0)
- [ ] `test/wisp/wisp_transform_logger_test.dart` — stubs for WISP-05 (1-Hz JSONL rollup, FIFO drop, sync flush, dual-clock)
- [ ] `test/wisp/fog_painter_with_wisps_test.dart` — Wave 1 widget test: paint sequence (fog → wisps), FOG-07 single-snapshot keystone preserved with wisps active
- [ ] `lib/config/constants.dart` — add `kMirkPocWisp*` constants (max-active=200, life-seconds=2.5, etc.)

*Wave 0 ships the test stubs + constants BEFORE any production wisp code lands. Each test starts as a `skip:` or `markPending`-style placeholder; subsequent waves un-skip as features land.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Wisps spawn along disc perimeters as new discs appear | WISP-03 / SC #3 | Visual quality + spawn-pattern correctness require human eye | Sideload session in central Melun; pan to a fresh area; visually confirm wisps emerge at the disc rim, not centre or randomly |
| Wisps drift outward over 2.5 s life and fade out | WISP-02 / SC #3 | Drift trajectory + alpha-curve aesthetic require human eye | Sideload session; observe a single wisp lifecycle; confirm 2.5 s duration, outward direction, fade-to-zero alpha |
| Wisps remain anchored to underlying map during pan/zoom | WISP-01 / SC #3 | Cross-pipeline parity check (the phase goal) is a perceptual claim about visual coherence with fog | Sideload session; pan and pinch-zoom while wisps are active; confirm wisps track the same map features the fog tracks (no parallax against fog) |
| PERF-07 thresholds met: medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48 with fog + 200 wisps | PERF-07 / SC #4 | Frame timing must be measured under real device load; emulator timings are not authoritative | Sideload session ≥60 s; collect `infrastructure.mirk.frame_delta` JSONL; compute median/p95/max; assert thresholds |
| PERF-08 SDF cache thrash baseline preserved (rebuildCount/sec median 68, max 121) | PERF-08 / SC #5 | SDF cache is exercised by user-driven pan/zoom, not synthetic input | Same sideload session; collect `infrastructure.mirk.sdf` JSONL; assert no regression vs Walk #2 baseline |
| C3' extreme-distance regime: wisps render correctly at 50–100 km from Melun, no fp32 artefacts, fog lock preserved | DEBUG-02 / SC #6 | fp32 precision artefacts are observable visual phenomena; cannot be unit-tested without simulating the projection pipeline end-to-end | Sideload session; pan to ~50 km then ~100 km from Melun; confirm wisps render without jitter; collect `infrastructure.mirk.wisp` JSONL `screenXMin/Max` deltas; verify per-frame projection delta < 0.5 px when camera is stationary |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30 s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
