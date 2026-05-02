---
phase: 03-fog-of-war-the-hypothesis
plan: 08
type: uat
status: failed
source: [03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md, 03-05-SUMMARY.md, 03-06-SUMMARY.md, 03-07-SUMMARY.md]
started: 2026-05-01T17:12:54Z
ci_run: 25224334312
ci_sha: 280dd04fbe3b361e247614021360c616fec742f0
device: iPhone 17 Pro (ProMotion 120 Hz, A19 Pro)
location: central Melun (48.5397, 2.6553)
exit_gate: developer's resume signal containing PERF-04 numbers + PERF-03 FPS notes + PERF-05 subjective verdict
verdict: denied
walked: 2026-05-01
---

# Phase 3 UAT — Falsification Walk (PERF-03 / PERF-04 / PERF-05)

**Gate:** This is the binary answer to the same-Canvas fog hypothesis. A
verbal `approved` (with PERF-04 numbers + PERF-03 FPS notes + PERF-05
subjective verdict) confirms the hypothesis and unblocks Phase 4. A
`denied` (Criterion A or B fails) makes the POC the formal counter-evidence
and **terminates** the project — MirkFall does not migrate.

This UAT mirrors the shape of `.planning/phases/02-map-no-fog/02-UAT.md`
(Phase 2's PERF-02 walk) but the gates are different — Phase 3 measures
fog-locked-to-map quality instead of bare-map FPS.

## Build Under Test

| Field        | Value                                                                     |
| ------------ | ------------------------------------------------------------------------- |
| CI run       | `25224334312`                                                             |
| Run URL      | https://github.com/ThongvanAlexis/mirk-poc-debug/actions/runs/25224334312 |
| HEAD SHA     | `280dd04fbe3b361e247614021360c616fec742f0` (`280dd04`) on `main`          |
| iOS artifact | `mirk-poc-debug-ios-unsigned-ipa` (~11.5 MB) — downloaded to `.uat-tmp/mirk-poc-debug-unsigned.ipa` |
| Gates job    | success                                                                   |
| Android job  | success (APK also available — Android is not in scope for PERF-03/04/05)  |
| iOS job      | success                                                                   |
| Tests        | 126 GREEN locally (Windows) on commit `280dd04`                           |

## Pre-walk Gates

- [x] `flutter test` full suite GREEN — **126 GREEN / 0 SKIPPED / 0 RED** locally on `280dd04`
- [x] `flutter analyze --fatal-infos` 0 warnings — **No issues found** (4.3s)
- [x] `dart format --line-length 160 --set-exit-if-changed lib/ test/` clean — **69 files, 0 changed** (0.17s)
- [x] `dart test tool/test/` GREEN — **18 tests** (LOC-03 + BOOT-02 + license-check) all pass
- [x] CI run for head commit `280dd04` GREEN (gates + android + ios) — run `25224334312`, all 3 jobs success
- [x] IPA artifact downloaded — at `.uat-tmp/mirk-poc-debug-unsigned.ipa` (11.5 MB)
- [x] `/sanity` smoke test on sideloaded IPA — fog renders on iPhone 17 Pro; developer reports seeing "mirk" on the walk screen, which implies the shader compiled and the SDF→shader path executed end-to-end (the `/sanity` route uses the SAME `FogShaderUniforms.setAll` path as `FogLayer`, so a successful render on the walk screen retroactively confirms the sanity gate). No `severe` / `Failed to load fog shader` log entries surfaced before the walk was aborted on visual grounds.

## Walk Protocol

- **Where:** Central Melun (48.5397, 2.6553) — same theatre as the Phase 2 walk.
- **Duration target:** ≥ 5 minutes continuous walk on iPhone 17 Pro.
- **Gestures target:**
  - **≥ 10 deliberate combined pinch-zoom-and-pan** (rotate + pinch + pan simultaneously; the worst-case stress on the same-Canvas hypothesis).
  - **≥ 3 recenter taps** (the FAB).
  - **≥ 1 full pan** from one edge of the Melun PMTiles bbox to the other.
  - **≥ 1 zoom-out to z10** (min) and back to z15 (max).
- **HUD visible during walk:**
  - `FpsCounterOverlay` at `top: 8 / right: 8` (Phase 1 PERF-01).
  - `MapCompass` at `top: 56 / right: 8` (Phase 2 LOC-04 cousin).
  - `FrameDeltaProbeOverlay` at `top: 104 / right: 8` (Phase 3 FOG-08 user-facing) — three colour-coded lines `med / p95 / max`, green/yellow/red against Criterion A.
- **Pre-walk shader-sanity gate (BEFORE the walk):**
  1. Sideload the IPA via SideStore on iPhone 17 Pro.
  2. Open the app; grant location permission.
  3. On `/map`, tap the AppBar `Icons.science` button → navigate to `/sanity`.
  4. Confirm the screen renders fog with a circular reveal hole visible somewhere centred on screen (the synthetic 80 m disc). Fog should look "atmospheric" (cool indigo palette per `kMirkFog*` constants).
  5. Tap share-logs → Mail → open the `.txt.gz` on desktop. **`grep -E 'severe|Failed to load fog shader'` MUST return zero matches.** Any shader-compile error → ABORT the walk; the IPA is broken; raise + stop.
  6. Return to `/map`.
- **Post-walk:**
  1. Share session log via Mail (LOG-04 / `share_plus`).
  2. Open `.txt.gz` on desktop, gunzip, inspect JSONL.
  3. `grep 'infrastructure.mirk.frame_delta'` → paste the 1-second JSONL rollups during the ≥ 10 combined-gesture seconds (typically 10–20 lines).
  4. `grep 'infrastructure.mirk.sdf'` → paste the SDF rebuild rollup lines.
  5. Note the FPS-counter readings observed during pan / pinch / combined / idle.
  6. Subjective verdict (Criterion B) — one sentence per Criterion B sub-claim.

## Falsification Thresholds (LOCKED before walk — see 03-FALSIFICATION.md for the formal source)

| Metric                                        | Threshold                                                            | Pass / Fail | Source                                |
| --------------------------------------------- | -------------------------------------------------------------------- | ----------- | ------------------------------------- |
| **PERF-04 median frame-delta** (Criterion A)  | **≤ 16 ms** (1 frame at 60 Hz; 2 frames at 120 Hz)                   | > 16 → FAIL | `infrastructure.mirk.frame_delta` JSONL |
| **PERF-04 p95 frame-delta** (Criterion A)     | **≤ 32 ms**                                                          | > 32 → FAIL | `infrastructure.mirk.frame_delta` JSONL |
| **PERF-04 max frame-delta** (Criterion A)     | **≤ 48 ms**                                                          | > 48 → FAIL | `infrastructure.mirk.frame_delta` JSONL |
| **PERF-03 pan-FPS with fog active**           | **≥ 30 fps** sustained during ≥ 5 s pan window                       | < 30 → FAIL | FpsCounterOverlay readings            |
| **PERF-03 idle-fog-animation FPS**            | **≥ 50 fps** observed during idle-with-fog state                     | < 50 → FAIL | FpsCounterOverlay readings            |
| **PERF-05 subjective — fog slide-then-snap**  | None observed during pan                                             | observed → FAIL | Developer's eyes during walk       |
| **PERF-05 subjective — white-ellipse**        | None observed during fast pinch-zoom                                 | observed → FAIL | Developer's eyes during walk       |
| **PERF-05 subjective — reveal-hole lag**      | Reveal hole stays centred on blue dot, no perceptible trail          | observed → FAIL | Developer's eyes during walk       |
| **PERF-05 subjective — inversion**            | Fog never appears where reveal should be (or vice versa) at any zoom | observed → FAIL | Developer's eyes during walk       |
| **Combined gestures performed**               | ≥ 10                                                                 | < 10 → FAIL (insufficient evidence) | Plan 03-08 task spec     |
| **Recenter taps performed**                   | ≥ 3                                                                  | < 3 → FAIL (insufficient evidence)  | Plan 03-08 task spec     |
| **Walk duration**                             | ≥ 5 minutes continuous                                               | < 5 → FAIL (insufficient evidence)  | Plan 03-08 task spec     |
| **Exit gate**                                 | Developer reports `confirmed` / `denied` / `confirmed-with-caveats`  | anything else → still pending | Phase 1 LOG-05 pattern        |

**Falsification clause:** Criterion A (PERF-04) AND Criterion B (PERF-05)
must BOTH pass for the verdict to be `confirmed`. If only one passes, the
verdict is `confirmed-with-caveats` AND the caveats are documented in the
falsification doc. If both fail, the verdict is `denied` and the POC
terminates.

## Walk Evidence

**Walk aborted on visual grounds.** The developer observed that fog rendered on screen but did NOT translate when the map panned (only the blue dot moved); the `/sanity` shader-compile gate had passed, but Criterion B's translation lock was so badly violated that the walk was terminated before quantitative evidence (frame-delta probe rollups, SDF rebuild rollups, per-gesture FPS readings) could be collected. Per the Plan 03-08 falsification clause, Criterion B's failure alone delivers a `denied` verdict; Criterion A is unmeasured-and-moot.

### Frame-delta probe rollups (PERF-04, Criterion A — `infrastructure.mirk.frame_delta` JSONL)

**[~] NOT CAPTURED.** The walk was aborted on visual grounds before the ≥ 10 combined-gesture seconds of probe-rollup evidence could be recorded. The static-fog-during-pan failure mode itself denies Criterion B, which obviates the Criterion A measurement (a frame-delta of ~0 ms is meaningless on a fog surface that doesn't translate at all — the camera-to-fog-paint delta would measure correctly while the fog's *position* would still be wrong relative to the world).

| Stat   | Observed   | Threshold | Pass / Fail |
| ------ | ---------- | --------- | ----------- |
| median | not measured | ≤ 16 ms  | **[~] N/A — walk aborted on Criterion B failure**   |
| p95    | not measured | ≤ 32 ms  | **[~] N/A — walk aborted on Criterion B failure**   |
| max    | not measured | ≤ 48 ms  | **[~] N/A — walk aborted on Criterion B failure**   |

### SDF rebuild rollups (`infrastructure.mirk.sdf` JSONL)

**[~] NOT CAPTURED.** Same reason — walk aborted before the ≥ 5 minute log capture. The pre-walk `/sanity` route did successfully exercise the synthetic-80 m-disc SDF→shader path (the developer saw fog), so the SDF builder + `SdfCache` + `SdfRebuildLogger` pipeline is software-functional; the failure is downstream of SDF construction, in the same-Canvas paint path's *consumption* of the SDF.

### FPS observations (PERF-03)

**[~] NOT CAPTURED** as fine-grained per-gesture readings. The walk was aborted on visual grounds before the FPS counter could be deliberately observed during pan / pinch / combined / idle-with-fog states. PERF-03 is unmeasured-and-moot for this walk: even a sustained 120 fps render of a fog that does not translate with the camera would still falsify the hypothesis, because the failure mode is *correctness* (lock to camera), not *throughput* (fps).

| Activity              | FPS observed   | PERF-03 threshold | Pass / Fail |
| --------------------- | -------------- | ----------------- | ----------- |
| pan (fog active)      | not measured   | ≥ 30 fps          | **[~] N/A — walk aborted**   |
| idle (fog animating)  | not measured   | ≥ 50 fps          | **[~] N/A — walk aborted**   |
| pinch (fog active)    | not measured   | sanity check      | **[~] N/A — walk aborted**   |
| combined (fog active) | not measured   | sanity check      | **[~] N/A — walk aborted**   |

### Subjective verdict (PERF-05, Criterion B)

**Developer's verbatim words:** *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*

- **Fog slide-then-snap during pan?** **✗ FAIL** — actual failure mode is *worse than* slide-then-snap: the fog is **static** relative to the screen while the map translates beneath it. There is no "slide" because the fog never moves with the map at all; it stays pinned to the screen on every pan gesture, which means it slides *relative to the world* permanently.
- **White-ellipse during fast pinch-zoom?** **N/A** — fast pinch-zoom evidence was not deliberately exercised before the walk was aborted on the translation failure. Moot given Criterion B was already denied.
- **Reveal-hole lag behind blue dot?** **✗ FAIL (strongly implied).** The reveal disc is anchored to GPS world-coordinates. If the fog surface stays static during pan while the blue-dot CircleLayer correctly translates with the map (as the developer observed), the reveal hole — which lives in the fog's coordinate system — also stays static on screen, leaving the blue dot to walk *out of* its reveal hole. This is reveal-hole lag in its most extreme form: permanent, not transient.
- **Inversion at any zoom level?** **✗ FAIL (likely).** A static fog over a translating map necessarily produces inversion: areas the user previously revealed (reveal disc baked into SDF at world coordinates A) appear fogged after pan (because the fog samples in screen-space, not world-space), and previously-fogged terrain (world coordinates B that translated under the static reveal disc) shows reveal where there should be fog. Direct visual confirmation was not collected before the walk aborted, but the geometry forces this outcome from the static-fog-during-pan observation.

## Verdict

**Verdict:** **DENIED.**

**Walked at:** 2026-05-01 on iPhone 17 Pro against CI run `25224334312` (SHA `280dd04`) in central Melun.

**Developer's verbatim words:** *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*

**Interpretation:**

- **Criterion A (PERF-04):** **Not measured.** Frame-delta probe rollups were not captured because the walk was aborted on Criterion B's visual failure before the ≥ 10 combined-gesture seconds of evidence could be collected. Per the falsification clause ("Criterion A AND Criterion B must BOTH pass for `confirmed`; either failing → `denied`"), Criterion B's failure alone is sufficient for the `denied` verdict; the absence of Criterion A measurement does not weaken the verdict.
- **Criterion B (PERF-05):** **FAILED.** Three of four sub-claims fail (slide-then-snap manifested as worse-than-slide-then-snap *static* fog; reveal-hole lag is permanent; inversion is geometrically forced by the static-fog-during-pan observation). The fourth (white-ellipse during fast pinch-zoom) was not deliberately exercised, but the translation failure denies Criterion B unilaterally.
- **PERF-03 (FPS):** **Not measured.** The walk was aborted before deliberate FPS observation. Moot for the verdict because the failure mode is *correctness* (camera lock), not *throughput* (frames per second).

**Phase 3 readiness / Phase 4 unblock OR project termination:**

The same-Canvas fog hypothesis is **falsified as currently implemented** in Plans 03-01..03-07. Phase 4 (wisp particles) does NOT unblock — the wisp work would inherit the same broken transform path as the fog. The project does NOT formally terminate at this point: the failure mode is plausibly fixable and does not invalidate the *underlying* same-Canvas premise (rendering map + fog in a single Flutter Canvas pipeline). What is falsified is the *specific implementation* of the same-Canvas pipeline that Plans 03-04..03-07 shipped, particularly the assumption that placing `FogLayer` as a child of `FlutterMap` between `VectorTileLayer` and the blue-dot `CircleLayer` would automatically share the tile layer's translation transform. The recommended next step is a **Phase 3.1 gap-closure** investigation phase to diagnose the camera-translation propagation path (three diagnostic possibilities outlined in 03-FALSIFICATION.md). If Phase 3.1 produces a fix, Phase 3 reopens for a re-walk; if Phase 3.1 confirms the failure is unfixable inside `flutter_map`'s 7.0.2 architecture, the project terminates per the original CONTEXT.md plan.

See `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md`
for the formal verdict and MirkFall migration recommendation (DO NOT PORT BACK as-implemented; three diagnostic possibilities for Phase 3.1).

## Deviations / Surprises

The most consequential surprise is that the **structural FOG-04 widget test passed (Plan 03-05 GREEN tests confirm `find.descendant(of: FogLayer, matching: MobileLayerTransformer)` returns one match) but the behavioural consequence — that placing `FogLayer` inside `MobileLayerTransformer` gives it the tile layer's Canvas translation transform — does not follow.** The structural test is a necessary-but-not-sufficient gate for the same-Canvas hypothesis: widget-tree containment does not imply Canvas-transform sharing. This is a permanent diagnostic lesson for Phase 3.1 and any future port-back attempt: structural tests on `flutter_map` custom layers must be paired with behavioural tests that assert the painter's `Canvas.getTransform()` matches the tile layer's at the same paint frame.

A second surprise is that **rotation gestures DO transform the fog surface** (per the developer's verbatim "it can be rotated tho"), even though translation gestures do not. This is itself a strong diagnostic signal — it suggests the fog *does* share the camera's rotation transform but not its translation transform. Possible explanations:

1. `MobileLayerTransformer` may apply rotation at the widget layer (via a `Transform.rotate`) but translation via a separate Canvas matrix that the painter's local Canvas does not inherit.
2. The painter's read of `MapCamera` happens at build time, and `flutter_map` may issue a `setState`/rebuild on rotation events but not on translation events (which may go through a more direct `markNeedsPaint` path on the tile layer alone).

Both possibilities point at Phase 3.1's diagnostic work.

## Summary

total: 13 thresholds (Criterion A × 3 + Criterion B × 4 + PERF-03 × 2 + walk-protocol × 3 + exit gate)
passed: 0 (no quantitative threshold passed; the `/sanity` pre-walk gate is a separate gate that did pass)
failed: 4 (Criterion B sub-claims: slide-then-snap, reveal-hole lag, inversion all FAIL; exit gate FAIL — verdict is `denied` rather than `approved`)
pending: 0
skipped: 9 (Criterion A × 3 + PERF-03 × 2 + Criterion B white-ellipse + walk-protocol × 3 — all unmeasured because walk aborted on visual grounds; not pending, not failing — deliberately not collected because moot given the Criterion B verdict)

## Gaps

<!-- APPEND only if walk reveals issues; YAML format for /gsd:plan-phase --gaps -->

```yaml
gaps:
  - id: GAP-PHASE-3.1-CAMERA-TRANSFORM
    severity: blocker
    summary: |
      Same-Canvas fog hypothesis falsified for translation: fog renders correctly
      and rotates with the camera, but does NOT translate with the camera during
      pan gestures. Plans 03-04..03-07 shipped a structurally-correct widget tree
      (FogLayer is a descendant of MobileLayerTransformer per Plan 03-05's GREEN
      FOG-04 test) but the painter's Canvas does not inherit the tile layer's
      translation transform. Phase 3.1 gap-closure required before any port-back
      to MirkFall; three diagnostic possibilities outlined in 03-FALSIFICATION.md.
    next_action: |
      Plan Phase 3.1 with three diagnostic tasks:
        1. Log Canvas.getTransform() in FogPainter.paint() vs the tile-layer's
           transform at the same frame; confirm/deny transform-bypass.
        2. Inspect flutter_map 7.0.2 MobileLayerTransformer source; determine
           whether it applies translation via Transform widget vs Canvas matrix.
        3. Log MapCamera.center in FogLayer.build() vs FogPainter.paint()
           during a pan gesture; determine whether build() is called during pan
           (i.e., whether the painter holds a stale build-time camera snapshot).
      The diagnostic must answer: "does the painter receive an updated camera
      between pan-driven repaint cycles?" That answer determines whether the fix
      is camera-staleness (listen to MapController + markNeedsPaint) or
      transform-bypass (wrap painter in Transform.translate or apply
      canvas.translate inside paint()).
    owner: Phase 3.1 planner (`/gsd:plan-phase 3.1` after this verdict commit)
    blocked_phases: [04-wisp-particles, 05-decision-gate]
  - id: GAP-FOG-04-STRUCTURAL-TEST-INSUFFICIENT
    severity: lesson-learned
    summary: |
      Plan 03-05's FOG-04 test asserts find.descendant(of: FogLayer, matching:
      MobileLayerTransformer) returns one match. This is a structural test
      (widget-tree containment) and was treated as a same-Canvas-keystone gate.
      Walk evidence shows structural containment does NOT imply Canvas-transform
      sharing. Future port-back work to MirkFall, AND any Phase 3.1 fix attempt,
      must add a behavioural test that asserts the painter's
      Canvas.getTransform() matches the tile layer's at the same paint frame.
      The structural-only test should be retained but augmented, not replaced.
    next_action: |
      Phase 3.1 planner adds a behavioural-transform-equality test alongside the
      existing structural FOG-04 test in fog_layer_test.dart. The behavioural
      test must use a real flutter_map context (not a fake), trigger a pan, and
      assert canvas-transform parity at paint time.
    owner: Phase 3.1 planner
    blocked_phases: [04-wisp-particles]
```
