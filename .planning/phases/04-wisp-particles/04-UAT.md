---
phase: 04-wisp-particles
walk: 1
date: 2026-05-04
tester: developer (solo)
device: iPhone 17 Pro
sideload: SideStore
ci_run: TBD
sha: TBD
ipa_artifact_url: TBD
---

# Phase 4 — Walk #1 UAT Log

**Phase:** 04-wisp-particles
**Walk #:** 1
**Date:** 2026-05-04 (skeleton authored; walk pending)
**Tester:** Developer (solo)
**Device:** iPhone 17 Pro (ProMotion 120 Hz)
**Sideload mechanism:** SideStore
**CI Run:** TBD (filled after push to main; capture via `gh run list --limit 5`)
**SHA:** TBD (filled after `git rev-parse HEAD` post-push)
**IPA artifact URL:** TBD (filled via `gh run view <RUN-ID>` — captures the artifact link)

## Pre-walk software gate evidence

```
$ flutter test
... 211 tests passed, 1 skipped (captured 2026-05-04T23:24Z) ...

$ flutter analyze
No issues found! (ran in 2.4s)

$ dart format --line-length 160 --set-exit-if-changed lib/ test/
Formatted 96 files (0 changed) in 0.22 seconds.

$ dart run tool/check_headers.dart
check_headers: OK (100 files)

$ dart run tool/check_dependencies_md.dart
check_dependencies_md: OK (125 packages)
```

All 5 pre-walk software gates GREEN. CLAUDE.md "Solo dev / Claude is authorized to push directly on main when commits atomic + tests verts localement" mandate satisfied.

## CI run + SHA capture

- `gh run list --limit 5`: TBD
- `gh run view <RUN-ID>` build-ios job status: TBD (expected GREEN; download `build-ios.zip` artifact)
- IPA artifact downloaded + sideloaded via SideStore on iPhone 17 Pro: TBD
- App cold-launched + permission granted: TBD

## Walk steps (1-8 from 04-FALSIFICATION.md walk plan)

### Step 1: Cold launch (~30 s)

- Observed: TBD
- FpsCounterOverlay reading at idle: TBD (expected ~4 fps Flutter no-dirty-frames behaviour — NOT a regression)
- FrameDeltaProbeOverlay reading at idle: TBD (expected medianMs near 0)
- Confirm zero wisps visible (warmup gate active for first 5 s + no GPS fix yet): TBD
- Startup time + any visible "no fog yet" frame: TBD

### Step 2: Default-zoom warmup observation (~30 s, z=13 Melun centre)

- Wait ≥ 5 s after first GPS fix (warmup window passes): TBD
- Wisps emerge AT THE DISC PERIMETER (~25 m radius), NOT at centre or randomly: TBD (Criterion A spawn)
- Wisps drift OUTWARD (radial from spawn point) and fade over ~2.5 s: TBD (Criterion A drift+fade)
- Gentle pan: wisps stay anchored to the map: TBD (Criterion B partial)

### Step 3: Combined-gesture stress (~60 s)

- ≥ 10 deliberate combined pinch-zoom-and-pan gestures performed: TBD
- Criterion B under load: NO parallax between wisps and fog; wisps + fog move TOGETHER: TBD
- FrameDeltaProbeOverlay: medianMs stays green-coded (≤ 16 ms): TBD

### Step 4: Max-zoom regime (~60 s, z=18-19)

- Pinch-zoom to maximum (z=18-19); pan deliberately: TBD
- Criterion B at max zoom (FOG-19 fix holds for fog; wisps observed independently): TBD
- Criterion C: FrameDeltaProbeOverlay readings under fog + ~200 wisps active: TBD
- Wisp spawning at max zoom (disc-perimeter spawn is world-anchored; same physical area = same wisps): TBD

### Step 5: C3' extreme-distance pan (~90 s)

- Pan to ~50 km from Melun (any direction): TBD
- Wisps render correctly when panned back? Any visible jitter on stationary wisps when camera parked? TBD
- Pan to ~100 km from Melun: TBD
- Visible jitter on stationary wisps? (fp32 hypothesis from Pitfall 5 + RESEARCH §Open Question 1): TBD
- Pan back to Melun centre to recover spawn activity: TBD

### Step 6: UX-02 rotation gesture probe (~15 s)

- Deliberate two-finger rotation gesture: TBD
- Criterion F: rotation is a NO-OP (MapCompass stays at 0°; map doesn't rotate): TBD
- NO un-fogged wedges at viewport corners (the Walk #3 regression that UX-02 closed): TBD

### Step 7: Idle observation (~30 s)

- Screen idle (no gestures, no GPS movement) for 30 s: TBD
- Wisp drift CONTINUES even at idle (proves per-paint dt integration fresh — Pitfall 6 prevention): TBD
- Idle FrameDeltaProbeOverlay stays green: TBD

### Step 8: Mail-share session log

- Share-logs button tapped in AppBar; chose Mail; sent to self: TBD
- Mail received with attached `yyyymmddTHHMMSSZ_logs.txt`: TBD
- On desk machine: download attachment; grep performed for the 5 logger streams: TBD

## Mail-shared session log

- Filename: TBD (`yyyymmddTHHMMSSZ_logs.txt`)
- Size: TBD
- Mail received at: TBD
- Logger streams present: `infrastructure.mirk.{fog_transform, sdf, frame_delta, wisp, dev_marker}`
- Sample epochSecond join: TBD (proves grep-correlation works across all 5 streams)

## Verbatim developer quotes

- TBD (filled by Task 3 from the developer's resume-signal)

## Verdict

- TBD (CONFIRMED-AFTER-FIX | ITERATING-WITH-PARTIAL-PROGRESS | DENIED)
- Per-criterion table: see 04-FALSIFICATION.md Walk Evidence section

## Carry-forward dispositions (filled by Task 3)

- WISP-01..05 status flips: TBD
- PERF-07 walk-time validation outcome (medianMs / p95Ms / maxMs measured): TBD
- PERF-08 walk-time validation outcome (SDF rebuild rate vs Walk #2 baseline): TBD
- UX-02 + DEBUG-02 re-validation status: TBD
- ROADMAP.md Phase 4 status: TBD
- STATE.md chronological entry: TBD
