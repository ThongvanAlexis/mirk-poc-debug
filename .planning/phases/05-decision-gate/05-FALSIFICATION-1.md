---
phase: 05-decision-gate
walk: 1
device: iPhone 17 Pro
date: TBD
ci_run: 25383915800
sha: 3326f4b4e183b5b0bb41c600943cdc6bc0453163
verdict: TBD
---

# Phase 5 Decision Gate — iPhone 17 Pro Walk #1 — Falsification

## Hypothesis (Phase 5 closure-walk)

The Phase 3.1 + Phase 4 layered fix bundle (Plans 03.1-02 → 03.1-04 → 03.1-05 → 03.1-07 → 03.1-08 → 03.1-10 → 03.1-12 → 03.1-14 + Plans 04-01..04-04 + 4 inline post-Plan-04-04 follow-ups: `41c8acd` kPocMaxZoom 15→20, `2613da8` kPocInitialZoom 13→19, `849a6e1` auto-recenter on first GPS fix, `eec9087` WalkSimulator) preserves CONFIRMED-AFTER-FIX behaviour at Phase 5 closure scope: fog locks during pan + pinch-zoom + combined-gesture + C3' extreme-distance + UX-02 rotation-no-op regimes; wisp particles spawn / drift / fade / anchor under the same regimes; PERF-07 budget holds; PERF-08 SDF rebuild rate is unregressed; Mail-share + 5-stream grep-correlation closes Phase 4 Walk #1's deferred Criterion E + Criterion G.

If true: Phase 5 iPhone leg closes; Plan 04 authors VERDICT.md.
If false: capture failure mode + iterate per the Phase 3.1 model (Plan 5.1 inserted phase via `/gsd:plan-phase 5 --gaps` follow-up). NO HARD CAP on walk count per CONTEXT §Iteration policy.

## Falsification Criteria (must all hold for CONFIRMED-AFTER-FIX-FULL)

**Criterion A — Phase 3 fog re-confirm:** fog renders + locks during pan + pinch-zoom + combined-gesture; no slide-then-snap; no white ellipse; no reveal-hole lag behind blue dot; no inversion at any zoom level. Captured by direct visual observation + verbatim developer quote.

**Criterion B — Phase 4 wisp re-confirm:** wisps spawn on disc perimeter (5 s warmup gate active); drift outward over 2.5 s; fade; remain anchored to underlying map during pan + pinch-zoom + combined-gesture. NO parallax between wisps and fog. NO drift relative to spawning disc.

**Criterion C — PERF-07 budget preserved under fog + 200 wisps:** `infrastructure.mirk.frame_delta` rollups show `medianMs ≤ 16`, `p95Ms ≤ 32`, `maxMs ≤ 48` (these are the CONTEXT-locked thresholds; ROADMAP's `≥ 30 fps` is legacy text — PERF-07 is authoritative).

**Criterion D — PERF-08 SDF rebuild rate stable:** `infrastructure.mirk.sdf` rollups show no regression vs Walk #2 baseline (median 68/sec, max 121/sec).

**Criterion E — C3' extreme-distance regime clean (closing P4 Walk #1 deferred):** developer pans to ~50–100 km from Melun (DEBUG-02 cameraConstraint already removed); wisps + fog render correctly with no fp32 precision artefacts; visible lock preserved. `infrastructure.mirk.fog_transform.uOffsetXMax` exceeds ~5M raw px (Walk #5 baseline maxed at 4.26M = MAX zoom at Melun centre).

**Criterion F — UX-02 rotation gestures are no-ops:** two-finger rotation gestures are inert; `canvasTx`/`canvasTy` stay `0.000000` across ALL `infrastructure.mirk.fog_transform` rollups (regression guard for the Phase 3.1 closure invariant).

**Criterion G — Mail-share + 5-stream grep-correlation (closing P4 Walk #1 deferred):** post-walk Mail-share transmits the session log; 5 streams (frame_delta + fog_transform + sdf + wisp + dev_marker) extracted; epochSecond joins cleanly across all 5 (1-Hz wall-clock-aligned by design).

## Walk Plan (interactive sideload session at desk per CONTEXT §Final iPhone walk scope)

Free-form regime — developer judgement on gesture mix. Coverage targets:
  1. Cold launch IPA on iPhone 17 Pro (SideStore + paired Mac pairing-file). Wait for permission grant + first GPS fix; observe FpsCounterOverlay + FrameDeltaProbeOverlay + initial blue dot.
  2. Default-zoom (z=19 per `kPocInitialZoom` post-`2613da8`) baseline observation: wait 5 s for warmup; tap WalkSimulator AppBar action; pick a bearing; let wisps emerge on subsequent fixes.
  3. Pan + pinch-zoom + combined-gesture coverage at default zoom. Observe Criterion A + B + C + D in real time via overlays.
  4. Max-zoom regime (z up to `kPocMaxZoom = 20`): zoom in; pan; observe Criterion B + C.
  5. C3' extreme-distance regime: increase WalkSimulator speed via slider OR pan manually past Melun limits; sustain one-direction pan until visibly far from Melun on the basemap (~50–100 km equivalent at z 13–15). Observe Criterion E.
  6. UX-02 rotation gesture probe: deliberate two-finger rotation gesture at any zoom. Confirm Criterion F (rotation gesture is a no-op — basemap orientation does not change).
  7. Idle observation: leave WalkSimulator running but do NOT touch the screen for 30 s. Confirm wisp drift continues per-paint (not frozen).
  8. End walk: tap share-logs button (always-visible AppBar action) → Mail → developer's address → send. Confirm email received within ~1 minute.

## Pre-walk Gate Status (filled by Task 1)

- [x] flutter test full suite GREEN (218 tests passed, 1 skipped)
- [x] flutter analyze 0 issues (ran in 2.3s)
- [x] dart format --set-exit-if-changed clean (98 files, 0 changed)
- [x] dart run tool/check_headers.dart GREEN (102 files)
- [x] dart run tool/check_dependencies_md.dart GREEN (125 packages)
- [x] dart run tool/check_licenses.dart GREEN (125 packages)
- [x] dart test tool/test/ GREEN (18 tool tests)
- [x] CI run on closing SHA all-jobs GREEN (run `25383915800`: Lint / License / Headers / Deps + Build Android APK (debug) + Build iOS (no-codesign, sideloadable) all `success`)
- [x] iOS unsigned IPA artefact downloaded; SHA256 captured (`7c38323b42e29237931d4916e65baea934a49f46af681e42c74d8b99e50efa2d`; size 11,663,244 bytes; saved to `.uat-tmp/p05-02-ipa/mirk-poc-debug-unsigned.ipa`)

## Walk Evidence (filled post-walk by Task 3)

**Verdict:** TBD
**Verbatim developer quote:** TBD
**JSONL excerpts (5 streams):** TBD — see `walk-evidence/iphone-walk-1/`
**Per-criterion verdict table:** TBD

| Criterion | Status | Evidence |
| --- | --- | --- |
| A — Phase 3 fog re-confirm | TBD | Verbatim verdict + medianMs from frame_delta rollups |
| B — Phase 4 wisp re-confirm | TBD | Verbatim verdict + wisp lat/lon bounds from infrastructure.mirk.wisp |
| C — PERF-07 budget | TBD | medianMs / p95Ms / maxMs from infrastructure.mirk.frame_delta |
| D — PERF-08 SDF rebuild rate | TBD | rebuildCount/sec from infrastructure.mirk.sdf |
| E — C3' extreme-distance (closing P4 deferred) | TBD | uOffsetX max + visual lock @ ~50–100 km from Melun |
| F — UX-02 rotation no-op | TBD | canvasTx/Ty == 0.0 across all infrastructure.mirk.fog_transform rollups |
| G — Mail-share grep-correlation (closing P4 deferred) | TBD | epochSecond joins across 5 streams |

## Carry-forward dispositions (filled post-verdict)

- WISP-01..05 walk-time validation extension: TBD
- PERF-07 + PERF-08 walk-time re-validation: TBD
- UX-02 + DEBUG-02 carry-over re-validation: TBD
- Phase 4 deferred Criterion E + G closure: TBD
- ROADMAP.md Phase 5 status flip: TBD
