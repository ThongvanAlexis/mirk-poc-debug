# Phase 3 Falsification — Same-Canvas Fog Hypothesis

**Created:** 2026-05-01
**Phase:** 03-fog-of-war-the-hypothesis
**Walked on:** _pending_
**Verdict:** _pending_

## Hypothesis

Rendering the MirkFall map, fog-of-war shader, and (in Phase 4) wisp particles
in a single unified Flutter Canvas pipeline eliminates the camera-tracking
lag that BUG-014 left unfixed in the parent project. **Confirmed** means the
POC ports back to MirkFall; **denied** means the POC is the formal
architectural counter-evidence and the migration does not happen.

## Falsification Criteria (written BEFORE the walk)

### Criterion A — Frame-delta probe thresholds (PERF-04, quantitative)

The FOG-08 frame-delta probe rolling rollups across ≥ 10 deliberate combined
pinch-zoom-and-pan gestures over a ≥ 5 minute walk on iPhone 17 Pro must satisfy:

- **Median camera-to-fog-paint delta ≤ 16 ms** (1 frame at 60 Hz; 2 frames at 120 Hz)
- **p95 ≤ 32 ms**
- **max ≤ 48 ms**

Persisted to the session log as 1-second JSONL rollups via `Logger('infrastructure.mirk.frame_delta')`.

### Criterion B — Subjective visual lock (PERF-05)

Developer's verbal verdict at end of walk:

- No fog slide-then-snap behind the map during pan
- No white-ellipse artefact during fast pinch-zoom
- No perceptible reveal-hole lag behind the blue dot
- No inversion (fog appearing where reveal should be) at any zoom level

### Criterion C — DROPPED

Parent-FPS comparison was the original Criterion C; the planner dropped it
per the locked roadmap decisions (POC stands on absolute FPS + lock-correctness
alone). Recorded here for traceability — do not reinstate without revising
the roadmap.

## Walk Plan

- **Where:** Central Melun (lat 48.5397, lon 2.6553 area; same theatre as Phase 2 walk).
- **Duration:** ≥ 5 minutes continuous walk with the IPA running and the device awake.
- **Gestures:** ≥ 10 deliberate combined pinch-zoom-and-pan gestures, ≥ 3 recenter taps.
- **Pre-walk gate:** open `/sanity` route on the sideloaded build first; confirm the fog renders with a circular reveal hole visible (proves the SDF→shader path); confirm zero shader-compile exceptions in the FileLogger output.
- **Pre-walk gate (unit tests):** all Phase 3 unit tests green on `flutter test` (degree-distance regression test; single-MapCamera-snapshot test; FogShaderUniforms.totalFloatSlots == 41; SdfCache hit/miss; FrameDeltaProbe rollup correctness).
- **In-app HUD during walk:** FpsCounterOverlay (top:8, right:8) + MapCompass (top:56, right:8) + FrameDeltaProbeOverlay (top:104, right:8) — three lines: `med {N} ms / p95 {N} ms / max {N} ms`, colour-coded green/yellow/red against Criterion A.
- **Post-walk:** share the session log file via Mail (LOG-04 round-trip); paste the relevant frame-delta probe lines + SDF rebuild lines + FPS readings + screenshots into the "Walk Evidence" section below; write the subjective verdict (Criterion B) by hand.

## Walk Evidence (filled AFTER the walk by Plan 03-08)

_pending_

### Probe rollup (frame-delta JSONL — `Logger('infrastructure.mirk.frame_delta')`)

_paste relevant 1-second rollup lines here_

### SDF rebuild rollup (`Logger('infrastructure.mirk.sdf')`)

_paste relevant 1-second rollup lines here_

### FPS observations

_free-form notes from the on-screen FPS counter during pan / pinch / combined gestures / idle_

### Subjective verdict (Criterion B)

_developer's free-form notes; one bullet per Criterion B sub-claim_

## Verdict

_pending — written after walk_

- [ ] Criterion A passed?
- [ ] Criterion B passed?

**Outcome:** _confirmed_ / _denied_ / _confirmed-with-caveats_

**MirkFall migration recommendation:** _pending_
