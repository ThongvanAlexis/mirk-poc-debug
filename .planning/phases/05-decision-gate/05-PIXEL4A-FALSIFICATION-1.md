---
phase: 05-decision-gate
walk: 1
device: Pixel 4a (Adreno 618, Android 13)
date: 2026-05-DD                     # filled in Task 3 with actual walk date
ci_run: 25383915800
sha: 3326f4b4e183b5b0bb41c600943cdc6bc0453163
verdict: TBD                          # filled in Task 3 — CONFIRMED-PERF-06-CLEAN | CONFIRMED-PERF-06-IMPELLER-FALLBACK | LAUNCH-CRASH-CAVEAT-DOCUMENTED | PARTIAL-PERF-06 | OTHER
backend: TBD                          # Vulkan-Impeller | OpenGL ES fallback | Skia | crash-no-render
---

# Phase 5 Decision Gate — Pixel 4a Walk #1 — Falsification (PERF-06)

## Hypothesis (Phase 5 cross-platform sanity)

The layered Phase 3.1 + Phase 4 fix bundle (validated on iPhone 17 Pro under PERF-07 hard thresholds) renders fog + wisps under PERF-06's soft criteria on Pixel 4a (Adreno 618, Android 13). PERF-06 is **informational** — the bar is "app launches + fog renders + wisps render + 5-min walk no crash + informational FPS captured" with **NO hard pass threshold**.

If true: PERF-06 closes; VERDICT.md cites Adreno 618 quantitative numbers as the cross-platform reference.
If false (launch crash / fog-renders-but-wisps-don't / etc.): caveat documented in VERDICT.md per CONTEXT §Caveat policy. PERF-06 still resolves (it's informational) — the failure-mode is the deliverable.

Per CONTEXT §Pixel 4a walk shape — Phase 5 treats Pixel 4a with the same rigor as iPhone (Mail-share + same regimes including C3' + same metric capture) BUT the verdict-blocker semantics differ: an iPhone Criterion failure can trigger Phase 5.1 iteration; a Pixel 4a launch crash documents a CAVEAT in VERDICT.md (per Pitfall 1 — Adreno 6xx Impeller fallback is known Flutter behavior).

## Falsification Criteria (PERF-06 soft criteria — captured outcome ≠ hard pass)

**Criterion P1 — App cold-launches without SIGSEGV / FATAL crash within 30 s** (Pitfall 1 guard).
Soft-pass condition: 30 s logcat slice contains zero `SIGSEGV` / `FATAL` lines.
Outcome shapes: PASS (clean launch) | IMPELLER-FALLBACK (clean but `[INFO:flutter/...impeller fallback...]` present) | CRASH (`SIGSEGV` / `FATAL` lines present).

**Criterion P2 — Fog renders correctly on the basemap** at default zoom; visible lock during gentle pan; no black-fog / never-rendered failure mode.
Soft-pass condition: developer's verbatim verdict mentions fog visible and locked to map.

**Criterion P3 — Wisps render correctly** after 5-s warmup; spawn on disc perimeter as new GPS fixes arrive (synthetic via WalkSimulator); drift + fade visible; remain anchored to map during pan.
Soft-pass condition: developer's verbatim verdict mentions wisps visible + spawning + drifting + `wisp.jsonl` non-empty.

**Criterion P4 — 5-min WalkSimulator-driven walk completes without crash** at default + max zoom + C3' extreme-distance regimes.
Soft-pass condition: walk session lasts ≥ 5 min wall-clock, no app exit / native crash.

**Criterion P5 — Informational FPS captured:** `infrastructure.mirk.frame_delta` JSONL rollups Mail-shared post-walk. medianMs / p95Ms / maxMs values documented for VERDICT.md cross-platform reference summary line. **NO hard threshold.**
Soft-pass condition: `frame_delta.jsonl` non-empty after extraction.

**Criterion P6 — UX-02 rotation no-op holds on Android** (cross-platform regression guard for FOG-16 path-(a) discipline).
Soft-pass condition: all `fog_transform.jsonl` rollups have `canvasTx == 0 && canvasTy == 0`.

**Criterion P7 — C3' extreme-distance behaviour matches iPhone:** Adreno 618 fp32 precision behaviour at ~50–100 km from Melun; observed visual lock + `uOffsetXMax` JSONL evidence.
Soft-pass condition: `uOffsetXMax >> 4M` reached during walk; no precision-induced visual artefacts observed.

## Walk Plan (Pixel 4a sideload session at desk per CONTEXT §Pixel 4a walk shape)

Sequence (mirror of iPhone walk):
  1. Pre-walk: `adb devices`; confirm Pixel 4a connected. `adb install -r` the closing-SHA APK. `adb logcat -c` then start logcat capture.
  2. Cold launch via `adb shell monkey ...`; observe 30 s with logcat running. Pitfall 1 disposition.
  3. (If launch clean) Grant location permission; observe FpsCounterOverlay + FrameDeltaProbeOverlay + initial blue dot.
  4. Default-zoom baseline: tap WalkSimulator AppBar action; pick a bearing. Observe Criterion P2 + P3 + P5.
  5. Pan + pinch-zoom + combined-gesture coverage at default zoom.
  6. Max-zoom regime (`kPocMaxZoom = 20`).
  7. C3' extreme-distance: pan to ~50–100 km from Melun (DEBUG-02 unconstrained). Observe Criterion P7.
  8. UX-02 rotation gesture probe (Criterion P6).
  9. 5-min sustained walk under WalkSimulator (Criterion P4).
  10. End walk: tap share-logs → Android sharesheet → Gmail (per Pitfall 3) → developer's address → send. Confirm email received.

## Pre-walk Gate Status

- [x] flutter test full suite GREEN (218 passed, 1 skipped — local re-run 2026-05-05T15:06Z)
- [x] flutter analyze 0 issues (`No issues found! (ran in 2.5s)`)
- [x] dart format --set-exit-if-changed clean (98 files, 0 changed)
- [x] dart run tool/check_headers.dart GREEN (102 files)
- [x] dart run tool/check_dependencies_md.dart GREEN (125 packages)
- [x] dart run tool/check_licenses.dart GREEN (125 packages)
- [x] dart test tool/test/ GREEN (18 passed)
- [x] CI run on closing SHA all-jobs GREEN (run `25383915800` — `success`)
- [x] Android debug APK artefact downloaded (`/tmp/p5-pixel-apk/app-debug.apk`, 161 MB)
- [ ] Pixel 4a connected via adb; package installed                                  # filled at checkpoint resume
- [ ] 30 s post-cold-launch logcat captured; Pitfall 1 disposition recorded           # filled at checkpoint resume

## Walk Evidence (filled by Task 3)

**Verdict:** TBD (CONFIRMED-PERF-06-CLEAN | CONFIRMED-PERF-06-IMPELLER-FALLBACK | LAUNCH-CRASH-CAVEAT-DOCUMENTED | PARTIAL-PERF-06 | OTHER)
**Verbatim developer quote:** TBD
**Backend used:** TBD (Vulkan-Impeller | OpenGL ES | Skia | crash-no-render)
**JSONL excerpts (5 streams):** TBD — see `walk-evidence/pixel4a-walk-1/`
**Per-criterion outcome table:** TBD

| Criterion | Soft-pass condition | Walk #1 captured | Outcome |
|-----------|--------------------|------------------|---------|
| P1 — App launches without SIGSEGV / FATAL | logcat clean | TBD | TBD |
| P2 — Fog renders | verbatim verdict mentions fog visible | TBD | TBD |
| P3 — Wisps render | verbatim + wisp.jsonl non-empty | TBD | TBD |
| P4 — 5-min walk no crash | verbatim + log timestamps span ≥ 5 min | TBD | TBD |
| P5 — Informational FPS captured | medianMs / p95Ms / maxMs from frame_delta.jsonl | TBD | TBD |
| P6 — UX-02 rotation no-op | canvasTxAllZero && canvasTyAllZero | TBD | TBD |
| P7 — C3' extreme-distance | uOffsetXMax >> 4M | TBD | TBD |

## Carry-forward dispositions

- **REQUIREMENTS.md PERF-06 row update** (Plan 05 cascade): TBD
  - Clean / Impeller-fallback branch → flips to `Complete — Verified-by-walk (P05-03 Walk #1)`.
  - Crash branch → flips to `Complete — Caveat-documented (P05-03 Walk #1: Pitfall 1 Adreno 618 Impeller crash)`.
  - PARTIAL branch → flips to `Complete — Verified-by-walk-with-caveats (P05-03 Walk #1: <list>)`.

- **VERDICT.md Pixel 4a quantitative summary line** (Plan 04 input): TBD — exact 5-line table cell:
  ```
  | Pixel 4a (Adreno 618, Android 13) | <backend> | medianMs <X> / p95Ms <Y> / maxMs <Z> | "<verbatim quote>" | <crash status> |
  ```

- **VERDICT.md caveats list inheritance** (Plan 04 input): TBD — list each soft-criterion fail or backend-fallback observation that Plan 04 should add to the caveats list.
