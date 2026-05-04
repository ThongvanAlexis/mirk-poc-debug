---
phase: 04-wisp-particles
walk: 1
date: 2026-05-04
ci_run: 25349106544
sha: 234d712
verdict: TBD
---

# Phase 4: Wisp Particles — Falsification & Walk #1

**Phase:** 04-wisp-particles
**Walk #:** 1
**Date:** 2026-05-04 (skeleton authored; walk pending)
**CI Run:** [25349106544](https://github.com/ThongvanAlexis/mirk-poc-debug/actions/runs/25349106544) (Build iOS GREEN in 3m34s; SHA `234d712`; IPA artifact `mirk-poc-debug-ios-unsigned-ipa` ready for download)
**SHA:** `234d712de79bac93187cae17a5355cc013a11825` (short: `234d712`)
**Verdict:** TBD (filled post-walk by Plan 04-05 Task 3)

## Hypothesis (Phase 4)

The Phase 3.1 cross-pipeline parity discipline — single MapCamera snapshot per build, single canvas-getTransform per paint, single canvas-translate-to-world-frame, single clipPath — generalises to a SECOND visual layer (wisp particles) WITHOUT regressing the Phase 3.1 fog lock and without surfacing new failure modes:

- fp32 precision degradation at C3' extreme distance (~50-100 km from Melun at zoom 13);
- PERF-07 frame-budget overflow under combined fog + 200-wisp render load;
- PERF-08 SDF-cache rebuild-rate regression vs Walk #2 baseline;
- UX-02 rotation gesture leak (canvasTx/Ty drifting from 0).

If true → Phase 4 closes with **CONFIRMED-AFTER-FIX**; Phase 5 (Decision Gate) unblocks.
If false → capture failure mode + iterate per the Phase 3.1 model (no hard cap on walk count; iteration policy follows CONTEXT §carry-forwards).

## Falsification Criteria (must all hold for CONFIRMED)

**Criterion A — Wisp spawn-and-decay visual:** wisps emerge on the disc perimeter (~25 m radius around the GPS-derived disc centre) as new discs land; drift outward radially; fade over ~2.5 s. Captured by direct visual observation during the walk (Steps 2-4 of the walk plan).

**Criterion B — Same-Canvas anchoring (cross-pipeline parity):** during pan + pinch-zoom + combined gesture, wisps stay locked to the underlying map exactly as the fog does. NO parallax between wisps and fog. NO wisp drift relative to the disc that spawned them. Verified visually during walk Steps 3-4 + grep-correlated post-walk via `infrastructure.mirk.wisp` lat/lon/screenX/screenY bounds tracking.

**Criterion C — PERF-07 budget preserved under fog + 200 wisps:** `infrastructure.mirk.frame_delta` rollups show medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48 across ≥ 10 combined gestures. Carry-over from Phase 3.1 Walk #5 baseline (13×/20×/28× headroom on fog-only at Melun centre). Expected: small headroom reduction is acceptable; budget overflow is NOT.

**Criterion D — PERF-08 SDF rebuild rate stable:** `infrastructure.mirk.sdf` rollups show no regression vs Walk #2 baseline (median 68/sec, max 121/sec). Wisp render path must NOT trigger additional SDF rebuilds (Pitfall 4 enforcement: WispParticleSystem MUST NOT be wired into the SDF cache invalidation path).

**Criterion E — C3' extreme-distance regime clean:** developer pans to ~50-100 km from Melun (DEBUG-02 cameraConstraint already removed in Phase 3.1 Plan 03.1-12); wisps render correctly with no fp32 precision artefacts (visible jitter on smooth pan); fog lock preserved. Expected zero wisps spawning at extreme distance (no GPS fixes there) but existing wisps panned into view should render correctly.

**Criterion F — UX-02 rotation gestures are no-ops:** two-finger rotation gestures during pinch-zoom do NOT change `MapCamera.rotation`; `canvasTx`/`canvasTy` stay at 0 across all `infrastructure.mirk.fog_transform` rollups (regression guard for the Phase 3.1 Walk #6 closure invariant; UX-02 walk-time-validated 4th consecutive walk if confirmed).

**Criterion G — WispTransformLogger evidence captured + grep-correlatable:** `infrastructure.mirk.wisp` rollups Mail-shared post-walk; bounds (lat/lon/screenX/screenY) trackable across the walk; spawn rate matches expected ~20 wisps × N new discs / walk-duration cadence; epochSecond joins cleanly with `fog_transform` + `sdf` + `frame_delta` streams (proves the 5th rollup stream — wisp — is wired correctly into the same epochSecond grouping as the four Phase 3.1 streams).

## Walk Plan (interactive sideload session at desk per Phase 3.1 D1 decision)

Sequence:

1. **Cold launch (~30 s):** Launch IPA on iPhone 17 Pro via SideStore; wait for permission grant + first GPS fix; observe FpsCounterOverlay (top:8 right:8) + FrameDeltaProbeOverlay (top:104 right:8). Confirm: zero wisps visible (warmup gate active for first 5 s + no fix yet).

2. **Default-zoom warmup observation (~30 s, z=13 Melun centre):** wait ≥ 5 s after first GPS fix; observe wisps spawning on subsequent fixes. Visually validate Criterion A (spawn at disc perimeter, drift outward, fade ~2.5 s) + Criterion B partial (gentle pan: wisps anchored to map).

3. **Combined-gesture stress (~60 s):** ≥ 10 deliberate combined pinch-zoom-and-pan gestures. Observe Criterion B under load (NO parallax between wisps and fog; wisps + fog move TOGETHER). Observe FrameDeltaProbeOverlay reading green-coded (≤ 16 ms median).

4. **Max-zoom regime (~60 s, z=18-19):** zoom to maximum; pan deliberately. Observe Criterion B at max zoom (FOG-19 fix should hold for fog; wisps observed independently). Observe Criterion C: FrameDeltaProbeOverlay readings under fog + ~200 wisps active.

5. **C3' extreme-distance pan (~90 s):** pan camera to ~50 km from Melun (any direction); pause + observe Criterion E (do existing wisps render correctly when panned back? does any visible jitter appear on stationary wisps?); pan to ~100 km from Melun; pause + observe (the fp32 hypothesis from Pitfall 5 + RESEARCH §Open Question 1); pan back to Melun centre to recover spawn activity.

6. **UX-02 rotation gesture probe (~15 s):** attempt deliberate two-finger rotation gesture. Observe Criterion F (rotation should be a NO-OP; MapCompass stays at 0°; map doesn't rotate; NO un-fogged wedges at viewport corners).

7. **Idle observation (~30 s):** leave the screen idle (no gestures, no GPS movement) for 30 s. Observe: wisp drift CONTINUES even at idle (proves the per-paint dt integration is fresh, NOT frozen — Pitfall 6 prevention). Observe: idle FrameDeltaProbeOverlay stays green.

8. **Mail-share session log:** tap the share-logs button in AppBar; choose Mail; send to self. Verify Mail received with attached `yyyymmddTHHMMSSZ_logs.txt`. On the desk machine: download attachment; grep for the 5 logger streams:
   ```bash
   grep "infrastructure.mirk.fog_transform" log.txt | head
   grep "infrastructure.mirk.sdf" log.txt | head
   grep "infrastructure.mirk.frame_delta" log.txt | head
   grep "infrastructure.mirk.wisp" log.txt | head             # NEW Phase 4
   grep "infrastructure.mirk.dev_marker" log.txt | head
   ```
   Verify the four streams (fog_transform, sdf, frame_delta, wisp) share epochSecond boundaries (pick one epochSecond value; assert all four streams have a rollup at that second). Verify Criterion G: spawn rate matches expectation (~20 wisps × N new discs / walk duration).

## Pre-walk Gate Status

- [x] `flutter test` full suite GREEN (211 tests passed, 1 skipped — captured 2026-05-04T23:24Z)
- [x] `flutter analyze` 0 issues (ran in 2.4 s)
- [x] `dart format --line-length 160 --set-exit-if-changed lib/ test/` clean (96 files, 0 changed)
- [x] `dart run tool/check_headers.dart` GREEN (100 files OK)
- [x] `dart run tool/check_dependencies_md.dart` GREEN (125 packages OK)
- [x] CI run pushed; run-ID `25349106544` + SHA `234d712` captured; build-ios job GREEN; IPA artifact `mirk-poc-debug-ios-unsigned-ipa` available

## Walk Evidence (filled post-walk by Task 3)

**Verdict:** TBD
**Verbatim developer quote:** TBD
**JSONL excerpts:** TBD

### Per-Criterion Verdict Table

| Criterion | Status | Evidence |
|-----------|--------|----------|
| A — Wisp spawn-and-decay visual | TBD | TBD verbal + JSONL spawn rate |
| B — Same-Canvas anchoring (cross-pipeline parity) | TBD | TBD verbal + WispTransformLogger lat/lon/screenX/Y bounds tracking |
| C — PERF-07 budget preserved (≤16/32/48 ms) | TBD | TBD frame_delta rollup excerpt |
| D — PERF-08 SDF rebuild rate stable | TBD | TBD sdf rollup excerpt vs Walk #2 baseline |
| E — C3' extreme-distance regime clean | TBD | TBD verbal + wisp screenXMin/Max bounds at 50-100 km |
| F — UX-02 rotation gestures no-op | TBD | TBD verbal + canvasTx/Ty values from fog_transform rollups |
| G — WispTransformLogger evidence captured + grep-correlatable | TBD | TBD JSONL excerpts + epochSecond join example |

## Carry-forward dispositions

- WISP-01..05 status updates (REQUIREMENTS.md): TBD post-verdict
- PERF-07 + PERF-08 walk-time validation outcome: TBD
- UX-02 + DEBUG-02 carry-over re-validation (4th consecutive walk if CONFIRMED): TBD
- ROADMAP.md Phase 4 status flip: TBD
  - If CONFIRMED → "Complete (HYPOTHESIS CONFIRMED 2026-XX-XX)"; Phase 5 unblocks
  - If PARTIAL → leave In Progress; capture iteration axes
  - If DENIED → "Falsified-in-production"; iteration depends on root-cause analysis
