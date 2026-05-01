---
phase: 03-fog-of-war-the-hypothesis
plan: 08
type: uat
status: pending
source: [03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md, 03-05-SUMMARY.md, 03-06-SUMMARY.md, 03-07-SUMMARY.md]
started: 2026-05-01T17:12:54Z
ci_run: 25224334312
ci_sha: 280dd04fbe3b361e247614021360c616fec742f0
device: iPhone 17 Pro (ProMotion 120 Hz, A19 Pro)
location: central Melun (48.5397, 2.6553)
exit_gate: developer's resume signal containing PERF-04 numbers + PERF-03 FPS notes + PERF-05 subjective verdict
verdict: _pending_
walked: _pending_
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
- [ ] `/sanity` smoke test on sideloaded IPA — fog renders with circular reveal hole at viewport centre, **no `severe` / `Failed to load fog shader` lines in FileLogger output** — _pending — Task 2 (developer)_

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

_pending — filled after walk_

### Frame-delta probe rollups (PERF-04, Criterion A — `infrastructure.mirk.frame_delta` JSONL)

```
<paste relevant 1-second JSONL rollup lines from the walk's combined-gesture window here>
```

| Stat   | Observed | Threshold | Pass / Fail |
| ------ | -------- | --------- | ----------- |
| median | _pending_ | ≤ 16 ms  | _pending_   |
| p95    | _pending_ | ≤ 32 ms  | _pending_   |
| max    | _pending_ | ≤ 48 ms  | _pending_   |

### SDF rebuild rollups (`infrastructure.mirk.sdf` JSONL)

```
<paste relevant 1-second JSONL rollup lines from the walk here>
```

### FPS observations (PERF-03)

_free-form notes from FpsCounterOverlay during pan / pinch / combined gestures / idle-with-fog_

| Activity              | FPS observed | PERF-03 threshold | Pass / Fail |
| --------------------- | ------------ | ----------------- | ----------- |
| pan (fog active)      | _pending_    | ≥ 30 fps          | _pending_   |
| idle (fog animating)  | _pending_    | ≥ 50 fps          | _pending_   |
| pinch (fog active)    | _pending_    | sanity check      | _pending_   |
| combined (fog active) | _pending_    | sanity check      | _pending_   |

### Subjective verdict (PERF-05, Criterion B)

- **Fog slide-then-snap during pan?** _pending — yes/no + notes_
- **White-ellipse during fast pinch-zoom?** _pending — yes/no + notes_
- **Reveal-hole lag behind blue dot?** _pending — yes/no + notes_
- **Inversion at any zoom level?** _pending — yes/no + notes_

## Verdict

**Verdict:** _pending — confirmed / denied / confirmed-with-caveats_

**Walked at (UTC):** _pending_

**Developer's verbatim words:** _pending_

**Interpretation:**

- **Criterion A (PERF-04):** _pending_
- **Criterion B (PERF-05):** _pending_
- **PERF-03 (FPS):** _pending_

**Phase 3 readiness / Phase 4 unblock OR project termination:** _pending_

See `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md`
for the formal verdict and MirkFall migration recommendation.

## Deviations / Surprises

_pending — filled post-walk_

## Summary

total: 13 thresholds (Criterion A × 3 + Criterion B × 4 + PERF-03 × 2 + walk-protocol × 3 + exit gate)
passed: _pending_
failed: _pending_
pending: 13
skipped: 0

## Gaps

<!-- APPEND only if walk reveals issues; YAML format for /gsd:plan-phase --gaps -->

_pending — only filled if the walk surfaces gaps that need a Phase 3.1 mitigation plan or a re-design._
