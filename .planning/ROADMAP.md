# Roadmap: MirkFall Same-Canvas POC

## Overview

This POC answers one architectural question: does rendering the MirkFall map, fog-of-war shader, and wisp particles in a single unified Flutter Canvas pipeline eliminate the camera-tracking lag that BUG-014 left unfixed in the parent project? The roadmap front-loads the iOS feedback loop so that every subsequent phase produces a sideloadable IPA the developer can walk on iPhone. Risk de-risking drives the order: vector-tile rendering performance is the second-biggest unknown after the hypothesis itself, so it is gated before the fog work begins. The fog phase carries the falsification criteria; the wisp phase confirms cross-pipeline parity; the final phase converts walk evidence into the formal go/no-go verdict for the MirkFall migration.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation** - Bootstrap, CI, logger, share, FPS counter, permission gate — first walkable IPA
- [ ] **Phase 2: Map (no fog)** - PMTiles, gestures, blue dot, recenter; no-fog FPS gate before fog work
- [ ] **Phase 3: Fog of War — THE HYPOTHESIS** - Same-Canvas fog layer + frame-delta probe + falsification walk
- [ ] **Phase 4: Wisp Particles** - World-locked wisps composited in the same paint pass as fog
- [ ] **Phase 5: Decision Gate** - Final hardening, Pixel 4a sanity walk, formal POC verdict

## Phase Details

### Phase 1: Foundation
**Goal**: First sideloadable IPA where the developer walks through permission, sees the FPS counter, and shares the session log back to themselves over Mail. Establishes the iOS feedback loop end-to-end before any map code is written.
**Depends on**: Nothing (first phase)
**Requirements**: BOOT-01, BOOT-02, BOOT-03, BOOT-04, BOOT-05, BOOT-06, BOOT-07, BOOT-08, AUDIT-01, AUDIT-02, AUDIT-03, CI-01, CI-02, CI-03, CI-04, CI-05, AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06, LOG-01, LOG-02, LOG-03, LOG-04, LOG-05, PERF-01
**Success Criteria** (what must be TRUE):
  1. Developer pushes to `main`; the GitHub Actions run page shows three green jobs (lint on ubuntu, debug APK on ubuntu, unsigned IPA on macos) and the IPA + APK artifacts are downloadable from that run.
  2. Developer sideloads the IPA via SideStore on iPhone 17 Pro, launches the app, and sees the permission rationale screen explaining why `locationWhenInUse` is needed for the fog-of-war.
  3. Developer grants permission and lands on a placeholder map screen with a visible FPS counter (showing fps + the device refresh rate, 120 Hz on ProMotion) in the corner; denying instead routes to a denied screen whose "Open Settings" button rounds-trips through iOS Settings and re-checks permission on resume.
  4. Developer taps the share-logs button, picks Mail, and the session's `yyyymmdd_hhmmss_logs.txt` arrives in their inbox with byte-count matching the on-device file (50 MB synthetic-log smoke test passed at least once with a content-marker at byte 47 MB present in the received attachment).
  5. CI license-check job fails any future PR that introduces a non-allowlisted license (allowlist: MIT, BSD-2/3, Apache 2.0, ISC, zlib, CC0, Unlicense); first-pass `DEPENDENCIES.md` rows present for every direct dependency in `pubspec.yaml`, with telemetry audit showing zero automatic network egress at app launch.
**Plans**: 7 plans
  - [ ] 01-01-PLAN.md — Bootstrap: pubspec, analysis_options, LICENSE, l10n scaffold, donor constants + binary assets
  - [ ] 01-02-PLAN.md — Tooling: port tool/check_* + tool/test/* scripts, DEPENDENCIES.md skeleton, iOS Info.plist + PrivacyInfo.xcprivacy
  - [ ] 01-03-PLAN.md — BOOT-08 donor source files port, three-job CI workflow, REQUIREMENTS.md LOG-05 wording update
  - [ ] 01-04-PLAN.md — FileLogger + FileLoggerLifecycleObserver port-with-three-POC-adaptations + tests
  - [x] 01-05-PLAN.md — buildPocAppBar share-logs helper + FpsCounterOverlay (ProMotion-aware) + widget tests
  - [ ] 01-06-PLAN.md — PermissionGateScreen (lifecycle resume re-check) + PermissionDeniedScreen + widget tests
  - [ ] 01-07-PLAN.md — main wiring: lib/main.dart + app.dart + router.dart + MapScreen placeholder + LOG-05 manual UAT checkpoint

### Phase 2: Map (no fog)
**Goal**: A walkable map that loads `Fra_Melun.pmtile` from `getApplicationSupportDirectory()`, accepts pan/zoom/combined gestures, shows a blue dot following GPS, and recentres on demand — sustaining ≥ 40 fps on iPhone 17 Pro without fog. This is the gate that decides whether `vector_map_tiles` 8.0.0 is performant enough on this PMTiles at zoom 13–15 to make the Phase 3 hypothesis test meaningful.
**Depends on**: Phase 1
**Requirements**: MAP-01, MAP-02, MAP-03, MAP-04, MAP-05, MAP-06, LOC-01, LOC-02, LOC-03, LOC-04, LOC-05, PERF-02
**Success Criteria** (what must be TRUE):
  1. Developer launches the app fresh-installed; the log records `Copied Fra_Melun.pmtile (~4 MB) in <500 ms` exactly once during the permission-grant flow, and subsequent launches do NOT re-copy (idempotent existence check passes).
  2. Developer walks 200 m through central Melun (zoom 13–15); the map renders the bundled tiles with the renderer's default style, the blue dot follows each GPS fix, and the recenter FAB animates the camera to `_lastFix` at zoom 15 (and is disabled while `_lastFix` is null).
  3. Developer performs at least 10 pure pans, 10 pure pinch-zooms, and 10 combined pinch-zoom-and-pan gestures during the walk; the FPS counter shows pan-FPS ≥ 40 sustained on iPhone 17 Pro (PERF-02 gate). If this fails, Phase 3 does not start until label-thinning or another mitigation restores the baseline.
  4. Developer rapidly zooms out (z=15 → 8) and back in (z=8 → 15); tiles repaint without persistent blank flashes (brief decode flicker on cold cache is acceptable; sustained blanks are not).
**Plans**: TBD

### Phase 3: Fog of War — THE HYPOTHESIS
**Goal**: Render the atmospheric fog shader in the same Flutter Canvas as the tile layer, driven by an in-memory disc list and a 256×256 R-channel SDF. Wire the frame-delta self-debug probe. Walk the falsification criteria on iPhone 17 Pro. The phase's deliverable is a binary answer to the architectural hypothesis: same-Canvas eliminates the lag, or it does not. A "denied" outcome here is a valid scientific result that terminates the project; a "confirmed" outcome unlocks Phase 4.
**Depends on**: Phase 2
**Requirements**: FOG-01, FOG-02, FOG-03, FOG-04, FOG-05, FOG-06, FOG-07, FOG-08, PERF-03, PERF-04, PERF-05
**Success Criteria** (what must be TRUE):
  1. Pre-walk gates pass: a unit test asserts `distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km` (not ~111 km, defending against degree-distance regression); a unit test asserts SDF rect, clip path, and shader uniforms all derive from the same `MapCamera` instance captured once per `FogLayer` build (FOG-07 enforced); a shader-sanity screen renders the 41-uniform shader on the iOS device with hardcoded inputs before the walk.
  2. Developer walks ≥ 5 minutes through Melun on iPhone 17 Pro with at least 10 deliberate combined pinch-zoom-and-pan gestures and at least 3 recenter taps; pan-FPS with fog active stays ≥ 30 and idle-fog-animation FPS stays ≥ 50 (PERF-03).
  3. Frame-delta probe (FOG-08) over the same walk reports rolling median camera-to-fog-paint delta ≤ 16 ms, p95 ≤ 32 ms, max ≤ 48 ms across the ≥ 10 combined gestures (PERF-04). The probe values are visible on the on-screen overlay and persisted to the session log.
  4. Developer's subjective verdict at the end of the walk: no visible fog slide-then-snap, no white-ellipse artefact during fast pinch-zoom, no perceptible reveal-hole lag behind the blue dot, and no inversion at any zoom level (PERF-05).
  5. Falsification criteria for the hypothesis (Criterion A: frame-delta thresholds; Criterion B: subjective lock — Criterion C dropped per locked decisions) are written down in the repo before the walk and the walk evidence is appended to the same document at the end.
**Plans**: TBD

### Phase 4: Wisp Particles
**Goal**: Composite the wisp particle system after the fog in the same Canvas, with positions stored in `LatLng` (world space) and projected to screen via the same `MapCamera` snapshot the fog uses. Confirms that the same-Canvas discipline established in Phase 3 generalises to a second visual layer — the cross-pipeline parity check that completes the code-donor package for porting back to MirkFall.
**Depends on**: Phase 3
**Requirements**: WISP-01, WISP-02, WISP-03, WISP-04
**Success Criteria** (what must be TRUE):
  1. A unit test asserts that simulating a 100 m camera pan does NOT change a wisp's logical `LatLng` position, and that the wisp's projected screen Offset moves by the corresponding screen-pixel delta (defending against the verbatim-port pixel-space regression).
  2. Developer launches the app; no wisps appear during the 5 s warm-up before the first GPS fix arrives, and no wisps appear at synthetic (0, 0) coordinates.
  3. Developer walks the same Melun route from Phase 3; wisps spawn along disc perimeters as new discs appear, drift outward over their 2.5 s life, fade out, and remain anchored to the underlying map during pan/zoom/combined gestures. Maximum 200 wisps active simultaneously.
  4. FPS during the walk holds the Phase 3 thresholds (pan-FPS with fog + wisps active ≥ 30 on iPhone 17 Pro); fog lock from Phase 3 is preserved (re-confirming the hypothesis was not regression-broken by the wisp work).
**Plans**: TBD

### Phase 5: Decision Gate
**Goal**: Lock everything down for code-donor port-back to MirkFall and produce the formal POC verdict (hypothesis confirmed / denied → MirkFall migration go / no-go). One final iPhone walk re-runs the Phase 3 + Phase 4 criteria; one Pixel 4a walk satisfies the cross-platform sanity requirement; the verdict document is committed to the repo as the final artefact.
**Depends on**: Phase 4
**Requirements**: PERF-06
**Success Criteria** (what must be TRUE):
  1. Final iPhone 17 Pro walk re-confirms Phase 3 fog lock + Phase 4 wisp anchoring + ≥ 30 fps with fog + wisps active; share-logs round-trip still works; FPS counter still visible.
  2. Pixel 4a (Adreno 618) walk: app launches without crash, fog renders, wisps render, app does not crash during a 5-minute walk; informational FPS recorded in the verdict document for cross-platform reference (no hard pass criterion — PERF-06).
  3. Repository hardening passes: `flutter analyze` zero warnings, `dart format --line-length 160 --set-exit-if-changed` clean, every `.dart` file in `lib/` and `test/` carries the GOSL v1.0 copyright header (re-verified as a CI gate), `DEPENDENCIES.md` covers every package in `pubspec.lock` with current audit dates, and the CI license-check job is green on `main`.
  4. Formal POC verdict document is committed at the repo root: states "hypothesis confirmed" or "hypothesis denied" backed by the Phase 3 frame-delta numbers + subjective walk notes, names the iPhone model and Flutter version, and ends with an explicit MirkFall-migration recommendation (port back / do not port back / port back with caveats).
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 5/7 | In Progress | - |
| 2. Map (no fog) | 0/TBD | Not started | - |
| 3. Fog of War — THE HYPOTHESIS | 0/TBD | Not started | - |
| 4. Wisp Particles | 0/TBD | Not started | - |
| 5. Decision Gate | 0/TBD | Not started | - |

---
*Roadmap created: 2026-04-30*
*Granularity: coarse (5 phases)*
*Coverage: 56/56 v1 requirements mapped*
