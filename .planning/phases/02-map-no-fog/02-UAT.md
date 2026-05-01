---
phase: 02-map-no-fog
plan: 06
type: uat
status: testing
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md, 02-04-SUMMARY.md, 02-05-SUMMARY.md]
started: 2026-05-01T11:31:18Z
updated: 2026-05-01T11:31:18Z
ci_run: 25212559648
ci_sha: 46b8fcc62e618ab846f3881860f57ee86758fa5f
device: iPhone 17 Pro (ProMotion 120 Hz)
location: central Melun (48.5397, 2.6553)
exit_gate: verbal `approved` from developer (mirroring Phase 1 LOG-05 pattern)
---

# Phase 2 UAT — PERF-02 Walk (no fog)

**Gate:** Pan-FPS without fog **≥ 40 fps sustained** on iPhone 17 Pro at zoom
13–15 over a 200 m walk through central Melun. Verbal `approved` is the
exit signal. A FAIL here forces a Phase 2.1 (label-thinning mitigation)
INSERTED between Phase 2 and Phase 3 — see Verdict section.

This is the highest-probability project-blocking risk (per STATE.md
Blockers/Concerns). If pan-FPS without fog is already sub-40, there's no
headroom left for the Phase 3 fog shader. The walk IS the research.

## Build Under Test

| Field        | Value                                                                         |
|--------------|-------------------------------------------------------------------------------|
| CI run       | `25212559648`                                                                 |
| Run URL      | https://github.com/ThongvanAlexis/mirk-poc-debug/actions/runs/25212559648     |
| HEAD SHA     | `46b8fcc62e618ab846f3881860f57ee86758fa5f` (`46b8fcc`) on `main`              |
| iOS artifact | `mirk-poc-debug-ios-unsigned-ipa` (~11.5 MB, not expired)                     |
| Gates job    | success                                                                        |
| Android job  | success (APK also available — Android is not in scope for PERF-02)            |
| iOS job      | success                                                                        |
| Tests        | 94/94 GREEN locally (Windows) and on Linux CI                                 |

## Pre-walk Falsification Thresholds (LOCKED before walk)

These thresholds are written before the walk begins. Crossing any of the
PERF-02 / first-launch-log / subsequent-launch-log / gesture-floor lines
is a FAIL — no soft fails, no after-the-fact softening. The verbal
`approved` exit gate is the AND of all of them.

| Metric                                       | Threshold                                                                                                       | Pass / Fail                              | Source                                  |
|----------------------------------------------|-----------------------------------------------------------------------------------------------------------------|------------------------------------------|-----------------------------------------|
| **PERF-02 sustained pan-FPS**                | **≥ 40 fps** sustained over a ≥ 5 s window during pure-pan at zoom 13–15                                        | sustained < 40 → **FAIL** → triggers 2.1 | REQUIREMENTS.md PERF-02                 |
| FPS counter visible & ProMotion-aware        | Counter shows `<value> fps / 120 Hz` (Phase 1 PERF-01 already verified)                                         | absent or `60 Hz` → FAIL                 | Phase 1 PERF-01                         |
| **First-launch copy log (exactly 1 match)**  | Exactly one match for regex `^Copied Fra_Melun\.pmtile \(~\d+\.\d MB\) in \d+ ms$` in JSONL log                 | 0 or ≥ 2 matches → FAIL                  | ROADMAP Phase 2 SC #1, MAP-01           |
| **Subsequent-launch copy log (zero matches)**| Zero matches for that same regex on any cold-launch after the first                                             | ≥ 1 match → FAIL (idempotency broken)    | CONTEXT.md §2 mandate                   |
| **Pure-pan gestures performed**              | **≥ 10** one-finger drags without zoom change during the walk                                                   | < 10 → FAIL (insufficient evidence)      | Plan 02-06 task spec                    |
| **Pure pinch-zoom gestures performed**       | **≥ 10** pinch in/out without concurrent drag during the walk                                                   | < 10 → FAIL (insufficient evidence)      | Plan 02-06 task spec                    |
| **Combined pinch+drag gestures performed**   | **≥ 10** simultaneous pinch+drag during the walk                                                                | < 10 → FAIL (insufficient evidence)      | MAP-06, Plan 02-06 task spec            |
| Blue dot tracking (LOC-01..02 sanity)        | Blue dot visible during walk and updates as GPS fixes arrive                                                    | absent or never updates → FAIL           | LOC-01, LOC-02                          |
| Recenter FAB (LOC-04 sanity)                 | Tap animates camera to `_lastFix` at zoom 15 over ~500 ms with `Curves.easeInOut`                               | no animation or wrong target → FAIL      | LOC-04                                  |
| Rapid zoom out/in (z=15 → 8 → 15)            | Tiles repaint without **sustained** blank flashes (brief decode flicker on cold cache acceptable)               | sustained blank → FAIL                   | ROADMAP Phase 2 SC #4                   |
| Pan inertia / fling                          | Enabled (default `InteractiveFlag.all`)                                                                         | inertia missing → FAIL                   | flutter_map default                     |
| Rotation gesture                             | Two-finger twist rotates the map; compass icon glyph syncs                                                      | rotation broken → FAIL                   | CONTEXT decision                        |
| Compass tap (LOC-04 cousin)                  | Snap-to-north tween over ~250 ms via `mapCompassShortestPathToNorth` formula                                    | no snap or > 1 s lag → FAIL              | Plan 02-04                              |
| **Exit gate**                                | Developer says `approved` (or describes the failure mode for the FAIL path)                                     | anything else → still pending            | Phase 1 LOG-05 pattern                  |

**Falsification clause for PERF-02:** if the FPS counter sits sustained
below 40 during routine pan at z=14–15, this is a hard FAIL. We do NOT
re-classify it as a "soft" fail or "needs more data" — the gate inserts
Phase 2.1 (label thinning) before Phase 3 can begin. One brief sub-40 dip
during a hard pinch (decode bound — RESEARCH §Pitfall 1 acknowledges this
class of dip) is acceptable; *sustained* sub-40 over a ≥ 5 s pan window
is not.

## Walk Plan (~200 m, central Melun, zoom 13–15)

**Sideload preparation:**

1. Download IPA from CI run artifact:
   ```bash
   gh run download 25212559648 --name mirk-poc-debug-ios-unsigned-ipa --dir .uat-tmp/
   ```
   Or via the run page: https://github.com/ThongvanAlexis/mirk-poc-debug/actions/runs/25212559648
2. Drop `mirk-poc-debug-unsigned.ipa` into SideStore on iPhone 17 Pro and
   re-sign. CFBundleName is already `MirkPocDebug` (Plan 01-07 commit
   `b9c092d`), so the SideStore re-sign step accepts it.
3. **Delete any prior install first** to exercise the MAP-01 first-launch
   copy path. Otherwise the `<app_support>/maps/Fra_Melun.pmtile` from a
   prior session survives and the first-launch copy log line will not fire.

**Pre-walk log capture (MUST do before walking):**

1. Cold-launch the app fresh-installed.
2. Tap the location-permission CTA → grant "While Using App" → app navigates
   to `/map`.
3. Open the share-logs button (top-right app bar IconButton) → Mail → send
   to self → wait for inbox → open the `.txt.gz` attachment, gunzip, and
   inspect the JSONL.
4. Confirm exactly one log line matches the first-launch copy regex
   `^Copied Fra_Melun\.pmtile \(~\d+\.\d MB\) in \d+ ms$`.
5. Quit the app fully (swipe up from app switcher) → cold-launch again →
   re-share the new log via Mail → confirm ZERO matches for that regex on
   the second launch (idempotency — CONTEXT mandate).

**Walk protocol (200 m at zoom 13–15):**

Walk a roughly 200 m loop through central Melun while keeping the map
between zoom 13 and zoom 15. During the walk, perform AT LEAST:

- 10 **pure pans** — one-finger drags without zoom change.
- 10 **pure pinch-zooms** — pinch in/out without concurrent drag.
- 10 **combined gestures** — pinch + drag simultaneously (tests MAP-06
  combined-gesture handling and the race-disabled flag).
- 3 recenter-FAB taps — verify the camera animates smoothly to `_lastFix`
  over ~500 ms (LOC-04).
- 1 rotate gesture (two-finger twist) followed by a compass tap — verify
  the compass icon glyph rotates with the map and the snap-to-north tween
  fires over ~250 ms.

Continuously read the **FpsCounterOverlay** in the top-right corner. The
PERF-02 gate is **sustained ≥ 40 fps over a ≥ 5 s pan window**. Brief
sub-40 dips during hard pinches are acceptable per RESEARCH §Pitfall 1;
sustained sub-40 during routine pan is FAIL.

At the walk's end, perform a **rapid zoom out/in** test: 4–5 quick
pinches z=15 → z=8, then 4–5 pinches back z=8 → z=15. Watch for
sustained blank-tile flashes (NOT acceptable) vs. brief 1–2 frame decode
flicker on cold cache (acceptable).

**Post-walk log capture:**

After the walk, share the final log via Mail → archive it for the FPS
sample table below. The post-walk JSONL should contain:
- The first-launch copy line (from the very first cold-launch, before the
  quit-and-reopen).
- ZERO subsequent copy lines.
- Multiple `domain.location` GPS fix log lines (Plan 02-03 emits one per
  fix at distanceFilter = 5 m).
- `flutter.error` / `zone.error` lines should be absent (no top-level
  errors during the walk).

## Walk Evidence (filled DURING / AFTER walk)

> Developer fills these slots while walking (FPS samples) and immediately
> after the walk (log excerpts, gesture tally, deviations, verdict).
> Empty slots = walk not yet performed or evidence not yet captured.

### FPS samples (rolling 5 s windows)

| Zoom | Activity                          | FPS observed | Window length | PASS / FAIL vs ≥ 40 |
|------|-----------------------------------|--------------|---------------|---------------------|
| 13   | pure pan                          | _<fill>_     | _<fill>_ s    | _<fill>_            |
| 14   | pure pan                          | _<fill>_     | _<fill>_ s    | _<fill>_            |
| 15   | pure pan                          | _<fill>_     | _<fill>_ s    | _<fill>_            |
| 13   | pure pinch-zoom                   | _<fill>_     | _<fill>_ s    | _<fill>_            |
| 14   | pure pinch-zoom                   | _<fill>_     | _<fill>_ s    | _<fill>_            |
| 15   | pure pinch-zoom                   | _<fill>_     | _<fill>_ s    | _<fill>_            |
| 13–15| combined pinch + drag             | _<fill>_     | _<fill>_ s    | _<fill>_            |
| 15→8 | rapid zoom-out                    | _<fill>_     | _<fill>_ s    | n/a (decode-bound)  |
| 8→15 | rapid zoom-in                     | _<fill>_     | _<fill>_ s    | n/a (decode-bound)  |

### First-launch copy log excerpt

```
<paste the exact JSONL line(s) matching the regex
 ^Copied Fra_Melun\.pmtile \(~\d+\.\d MB\) in \d+ ms$
 from the first-launch log here>
```

Match count on first launch: _<fill — must be exactly 1>_

### Subsequent-launch log excerpt (idempotency)

```
<paste the relevant section of the second-launch log here, OR write
 "no matches — idempotent skip confirmed" if the line is absent>
```

Match count on second launch: _<fill — must be exactly 0>_

### Gesture tally during the walk

| Gesture                         | Floor | Performed | PASS / FAIL |
|---------------------------------|-------|-----------|-------------|
| Pure pan                        | ≥ 10  | _<fill>_  | _<fill>_    |
| Pure pinch-zoom                 | ≥ 10  | _<fill>_  | _<fill>_    |
| Combined pinch + drag           | ≥ 10  | _<fill>_  | _<fill>_    |
| Recenter FAB tap                | ≥ 3   | _<fill>_  | _<fill>_    |
| Rotate + compass-tap snap       | ≥ 1   | _<fill>_  | _<fill>_    |

### Sanity-check observations

- **Blue dot tracking quality:** _<smooth / jittery / lost / never appeared>_
- **Recenter FAB animation:** _<smooth ~500 ms easeInOut / instant snap / no movement>_
- **Compass glyph rotation:** _<tracks map / static / wrong direction>_
- **Compass snap-to-north:** _<~250 ms tween observed / instant / > 1 s lag>_
- **Rapid-zoom flash behaviour:** _<acceptable brief flicker / sustained blanks>_
- **Top-level errors during walk:** _<none / list any flutter.error or zone.error lines from log>_

## Verdict

> Developer fills this section after the walk. Either verbal `approved`
> (PERF-02 PASS, Phase 3 unblocked) OR detailed FAIL diagnosis with
> FPS-per-zoom-level numbers and recommended mitigation.

**Verdict:** _<approved | FAIL — see diagnosis below>_

**Walked at (UTC):** _<fill>_

### If FAIL — diagnosis & mitigation

Capture FPS per zoom level so Phase 2.1 has a baseline:

- z=13: _<N>_ fps sustained
- z=14: _<N>_ fps sustained (likely below 40 — POI density max in central Melun)
- z=15: _<N>_ fps sustained

Recommended mitigation (per RESEARCH §Pitfall 1 fallback path):

- [ ] Wrap `ProtomapsThemes.lightV3()` in a custom theme-layer-filter
      builder that drops `places_*` and `roads_label_*` layers at
      zoom < 14.
- [ ] Insert **Phase 2.1 (label-thinning mitigation)** between Phase 2
      and Phase 3 via `/gsd:plan-phase 02.1`.
- [ ] Re-walk PERF-02 at the end of Phase 2.1 against this same UAT.md
      (status flips back to `testing` for the re-walk).

## Deviations / Surprises

> Anything unexpected during the walk worth flagging for downstream phases
> (Phase 3 fog work, Phase 5 retrospective). Examples: GPS jumpiness in
> urban canyons, a tap-target collision, a compass quirk, an unexpected
> log line, a rare race in combined gestures.

_<fill after walk; or write "none" if the walk was clean>_

## Summary

total: 13 thresholds (PERF-02 + 12 sanity gates)
passed: _<fill after walk>_
failed: _<fill after walk>_
pending: 13
skipped: 0

## Gaps

<!-- APPEND only if walk reveals issues; YAML format for /gsd:plan-phase --gaps -->
<!-- If walk is verbal-`approved` clean, leave this section as "none". -->

_<empty until walk evidence indicates a gap; on FAIL, append YAML entries
  matching the templates/UAT.md gaps schema, including a `truth`,
  `status: failed`, `reason` with the developer's verbatim words,
  `severity` inferred per the templates/UAT.md severity guide, and
  `test` referencing which threshold row failed>_
