# Requirements: MirkFall Same-Canvas POC

**Defined:** 2026-04-30
**Core Value:** The fog-of-war stays perfectly locked to the map during pan, zoom, and combined gestures on a sideloaded iOS build.

Requirements are user-centric, testable, atomic. The POC's only question is the architectural hypothesis (single Canvas → no fog/map lag) — every requirement either proves that hypothesis or makes the iOS UAT walks investigable from a Windows dev box.

## v1 Requirements

### Bootstrap

- [x] **BOOT-01**: Flutter project initialised with SDK pin `3.41.7` and Dart `3.11.x`; `pubspec.yaml` strictly version-pinned (no `^`); `pubspec.lock` committed
- [x] **BOOT-02**: Every `.dart` file in `lib/` and `test/` starts with the GOSL v1.0 copyright header (`// Copyright (c) 2026 THONGVAN Alexis` / `// Licensed under the Good Old Software License v1.0` / `// See LICENSE file for details`)
- [x] **BOOT-03**: `LICENSE` file at repo root contains the GOSL v1.0 text
- [x] **BOOT-04**: `analysis_options.yaml` enforces `strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`; uses `flutter_lints 6.0.0`
- [x] **BOOT-05**: `dart format --line-length 160 --set-exit-if-changed .` passes
- [x] **BOOT-06**: `flutter analyze` passes with no warnings
- [x] **BOOT-07**: `Fra_Melun.pmtile` (4 MB MVT vector) bundled as a Flutter asset under `assets/maps/`
- [x] **BOOT-08**: Battle-tested files ported verbatim from MirkFall: `atmospheric_fog.frag`, `revealed_sdf_builder.dart`, `reveal_disc.dart`, `mirk_viewport_bbox.dart`, `tile_cell_iteration.dart`, `mirk_projection.dart`, `fog_shader_uniforms.dart`, `animation_helpers.dart`, plus relevant `kMirkFog*` / `kMetersPerDegreeLat` / `kEarthRadiusMeters` constants

### Dependency Audit

- [x] **AUDIT-01**: `DEPENDENCIES.md` at repo root lists every direct dependency with: name, pinned version, license, telemetry audit (auto network egress: yes/no, what it does), transitive license summary, maintenance signal (last release, contributors), platform compatibility (iOS + Android), audit date
- [x] **AUDIT-02**: CI fails the build if any direct or transitive dependency carries a non-acceptable license (allow-list: MIT, BSD-2/3, Apache 2.0, ISC, zlib, CC0, Unlicense)
- [x] **AUDIT-03**: Zero packages perform automatic network egress on app launch (no analytics, no crash reporting, no attribution SDKs, no remote config, no update checks)

### CI

- [x] **CI-01**: GitHub Actions workflow on every push to `main` runs three jobs: lint (ubuntu-latest), build-android (ubuntu-latest), build-ios (macos-latest)
- [x] **CI-02**: Lint job runs `flutter analyze`, `dart format --line-length 160 --set-exit-if-changed`, `flutter test`
- [x] **CI-03**: Build-android job produces a debug APK downloadable as a workflow artifact
- [x] **CI-04**: Build-ios job produces an unsigned IPA (sideloadable via SideStore) downloadable as a workflow artifact
- [x] **CI-05**: Both APK and IPA artifacts are visible from the GitHub Actions run page on every push

### Permissions

- [x] **AUTH-01**: On launch, the app shows a permission rationale screen explaining why `locationWhenInUse` is required for the fog-of-war
- [x] **AUTH-02**: When the user accepts the rationale, the app requests `Permission.locationWhenInUse` via `permission_handler`
- [x] **AUTH-03**: On grant, the app navigates to the map screen via `context.go('/map')` (full pile reset — there's nowhere to go back to)
- [x] **AUTH-04**: On deny, the app shows a denied screen with a button that opens system settings via `permission_handler.openAppSettings()` _(software-complete per Plan 01-06; Plan 01-07 sideload UAT confirmed deny → /denied → Open Settings → iOS Settings page works correctly. Cross-restart auto-resume routing bug — toggle Location ON in iOS Settings + return to app should auto-nav from /denied to /map but stays on /denied — deferred per `.planning/phases/01-foundation/deferred-items.md` and reference pattern in `docs/flutter-ios-specifics.md` §5.6. Not blocking POC closure.)_
- [x] **AUTH-05**: `ios/Runner/Info.plist` contains `NSLocationWhenInUseUsageDescription` with a non-empty rationale string; no `NSLocationAlwaysAndWhenInUseUsageDescription` (out of scope)
- [x] **AUTH-06**: `ios/Runner/Info.plist` contains `ITSAppUsesNonExemptEncryption=false`

### Map

- [x] **MAP-01**: On first launch (after permission grant), `Fra_Melun.pmtile` is copied from `rootBundle` to `<getApplicationSupportDirectory()>/maps/Fra_Melun.pmtile` exactly once; subsequent launches detect the existing file and skip the copy
- [x] **MAP-02**: The map screen renders the bundled PMTiles via `flutter_map 7.0.2` + `vector_map_tiles 8.0.0` + `vector_map_tiles_pmtiles 1.5.0`, with the renderer's default style
- [x] **MAP-03**: Initial camera centred on Melun (lat `48.5397`, lon `2.6553`, zoom `13`)
- [x] **MAP-04**: User can pan the map with one-finger drag
- [x] **MAP-05**: User can zoom the map with pinch gesture
- [x] **MAP-06**: User can perform combined pan+zoom (pinch + drag simultaneously) and the map responds smoothly

### Location & Recenter

- [x] **LOC-01**: After permission grant, the app subscribes to `Geolocator.getPositionStream` with a sensible accuracy/distance filter
- [x] **LOC-02**: A blue dot (radius 7 px, fill `#2b7cd6`, white stroke 2 px) is rendered at the user's current position on the map and updates on each GPS fix
- [x] **LOC-03**: The most-recent GPS fix is cached in memory as `_lastFix`; the app does NOT call `Geolocator.getLastKnownPosition()` (unreliable on iOS — known plugin issue)
- [x] **LOC-04**: A floating action button on the map screen animates the camera to `_lastFix` at zoom 15
- [x] **LOC-05**: When `_lastFix` is null (no fix yet received), the recenter button is disabled (or shows a spinner)

### Fog of War

- [x] **FOG-01**: On each GPS fix, a `RevealDisc(lat, lon, 25 m)` is added to an in-memory disc list (no database) _(Plan 03-01 Wave 0 stub; Plan 03-02 RevealDiscRepository implementation; Plan 03-07 wires MapScreen.\_subscribeToPositions → discRepository.append on every fix with hand-rolled `rvd_<microsSinceEpoch>_<randomU32>_<counter>` ID per RESEARCH §Open Question 4. Verified-by-test: 5 GREEN unit tests pin RevealDiscRepository + distanceMetres surfaces.)_
- [x] **FOG-02**: A 256×256 R-channel midpoint-128 SDF (`ui.Image`) is built from the disc list via `RevealedSdfBuilder.buildFromDiscs`, with distance computed in **metres**, not pixels (so circles stay circular at all latitudes) _(Plan 03-01 Wave 0: distanceMetres stub landed; behaviour ships in Plan 03-02. Verified-by-test: degree-distance regression test asserts `distanceMetres((48.5,2.6), (48.5,3.6)) ≈ 73.7 km` not ~111 km.)_
- [x] **FOG-03**: The SDF is rebuilt when the disc list changes; the rebuild runs on the UI isolate (acceptable for `< 100` discs at `< 16 ms`); a debug log records each rebuild's duration _(Plan 03-01 Wave 0: SdfCache + SdfRebuildLogger stubs landed; behaviour ships in Plan 03-03. Verified-by-test: SdfCache hit/miss + SdfRebuildLogger 1-Hz JSONL rollup + stop()-flush-pending-samples tests all GREEN.)_
- [ ] **FOG-04**: A `FogLayer` widget is registered as a `flutter_map` custom layer that paints into the same Canvas as the tile layer _(Plan 03-01 Wave 0 stub; Plan 03-05 paint behaviour; Plan 03-07 wires FogLayer into MapScreen as a child of FlutterMap between VectorTileLayer and the blue-dot CircleLayer. **Plan 03-08 walk DENIED 2026-05-01** — structural FOG-04 test passes (`find.descendant(of: FogLayer, matching: MobileLayerTransformer)` returns one match), but production walk reveals fog does NOT translate with the map during pan (only rotation propagates). Same-Canvas hypothesis falsified as-implemented; widget-tree containment did not imply Canvas-transform sharing. Phase 3.1 gap-closure required before any port-back to MirkFall. See 03-FALSIFICATION.md.)_
- [ ] **FOG-05**: Inside `FogLayer.paint()`, the 41 float uniforms + 1 sampler of `atmospheric_fog.frag` are populated; identity sdfRect (`0, 0, 1, 1`) is passed because the SDF and the viewport share the same coordinate space _(Plan 03-01 Wave 0: slot-count gate test pinned at 41; population behaviour ships in Plan 03-05. Structural tests pass (FogShaderUniforms.totalFloatSlots == 41 + setAll populates the uniform list); production walk denied 2026-05-01 — the uniforms populate correctly but the painter's Canvas does not consume the tile-layer's translation transform. See 03-FALSIFICATION.md.)_
- [ ] **FOG-06**: The clip path (world rect minus disc circles, in screen coordinates) is computed and applied via `canvas.clipPath`; the shader is then drawn via `canvas.drawRect(viewport, Paint()..shader = fogShader)` _(Plan 03-01 Wave 0: computeFogClipPath stub landed; geometry ships in Plan 03-05. Structural tests pass (computeFogClipPath returns world-rect-minus-disc-circles geometry); production walk denied 2026-05-01 — the clip path is computed in the painter's local Canvas coordinate space which is NOT translated with the camera during pan, producing the static-fog-during-pan failure mode. See 03-FALSIFICATION.md.)_
- [ ] **FOG-07**: All inputs to the per-frame fog draw — SDF rect, clip path, viewport size, shader uniforms — derive from the **same `MapCamera` snapshot**, captured atomically at the start of paint (prevents BUG-014's combined-zoom-pan failure mode from re-emerging in the new pipeline) _(Plan 03-01 Wave 0: keystone test skeleton landed; single-snapshot enforcement ships in Plan 03-05 with KEYSTONE GREEN test asserting readCount==1 initial / +1 per forced rebuild over 3 rebuilds. Structural single-snapshot enforcement passes; **production walk denied 2026-05-01** — the snapshot is taken correctly per paint() invocation, but the painter is plausibly not invoked between pan-driven repaint cycles (Phase 3.1 diagnostic possibility #3) OR the snapshot is consumed in screen-space without applying the camera's translation transform (possibilities #1/#2). See 03-FALSIFICATION.md three diagnostic possibilities.)_
- [x] **FOG-08**: A frame-delta self-debug probe records, per frame: timestamp of the latest map camera update, timestamp of the fog uniform population, the delta between them; rolling median, p95, and max are exposed via the logger and an on-screen overlay _(Plan 03-01 Wave 0 stubs; Plan 03-04 ring buffer + 1-Hz JSONL rollup + dual-clock discipline; Plan 03-06 overlay rendering — 3-line colour-coded HUD subscribed to probe.rollups; Plan 03-07 wires FrameDeltaProbeOverlay into MapScreen Stack at top:104 right:8 + owns probe.start/dispose lifecycle in initState/dispose. Verified-by-test: 7 GREEN probe tests + 5 GREEN overlay/sanity tests + 12 GREEN MapScreen integration tests; quantitative walk evidence not captured per Plan 03-08 walk-aborted-on-visual-grounds (PERF-04 unmeasured) but the probe code itself is software-complete and shipping in the IPA.)_
- [ ] **FOG-09**: A behavioural transform-equality regression test asserts `_FogPainter.paint()` calls `shaderRenderer.render(offset:)` with a different `offset` argument after `MapController.move(...)` than before, within `kPocCanvasTransformEpsilon`; the test is a CI-gating widget test that catches the Plan 03-08 static-fog-during-pan failure mode without a sideload walk. Existing Plan 03-05 FOG-04 structural test is augmented (docstring forward-pointer), not replaced. _(Phase 3.1 — Plan 03.1-02)_
- [ ] **FOG-10**: `FogTransformLogger` is a new sibling to `FrameDeltaProbe` + `SdfRebuildLogger`. Per-paint observation captures `(canvas.getTransform()[12..13], camera.pixelOrigin, camera.center, appliedUOffset)`; emits 1-Hz JSONL rollups via `Logger('infrastructure.mirk.fog_transform')` aligned to wall-clock seconds for grep-correlation; idle-second skip; FIFO drop on overflow at `kPocFogTransformBufferMaxSamples`; synchronous flush on `stop()`. Permanent in production code (debug-level always-on, NOT `--dart-define` gated, per CONTEXT decision). _(Phase 3.1 — Plan 03.1-01)_

### Wisp Particles

- [ ] **WISP-01**: `WispParticleSystem` is ported from MirkFall with particle positions refactored from `Offset` (screen pixels) to `LatLng` (world coordinates); positions are projected to screen at paint time using the same `MapCamera` snapshot as the fog
- [ ] **WISP-02**: Wisps are spawned along disc perimeters as new discs appear; max 200 wisps active simultaneously; 8 m spacing; 2.5 s life; 18 px/s initial speed; birth radius 6 px → death radius 22 px; peak alpha 0.35
- [ ] **WISP-03**: A 5 s warm-up phase suppresses wisp spawning on app open
- [ ] **WISP-04**: Wisps render in the same Canvas as the fog and the tile layer (same paint pass, same `MapCamera` snapshot)

### Logger

- [x] **LOG-01**: A logger configured via the `logging` package writes to `<getApplicationDocumentsDirectory()>/logs/yyyymmdd_hhmmss_logs.txt`, one file per app session
- [x] **LOG-02**: Log level for the POC is `Level.ALL` (verbose); each log line is timestamped to millisecond precision
- [x] **LOG-03**: The logger is initialised before any other module that might log (so initialisation failures are captured)
- [x] **LOG-04**: A button in the app (visible from any screen — likely an app-bar action) opens the system share sheet via `share_plus 12.0.2`, attaching the current session's log file
- [x] **LOG-05**: The share sheet works on a SideStore-sideloaded iOS build with the iOS Mail app as the share target. Phase 1 UAT exit gate: developer sideloads the IPA, taps share-logs, picks Mail, sends to themselves, verifies the email arrives with the gzipped log file as attachment. Verbal "approved" is the gate (no synthetic-log smoke test required per Phase 1 CONTEXT.md decision).

### Performance Instrumentation

- [x] **PERF-01**: An on-screen FPS counter overlay is rendered on the map screen (toggleable via a dev menu or always-on for the POC); shows current FPS rolling-averaged over 1 s
- [x] **PERF-02**: At Phase 2 UAT walk on iPhone 17 Pro: pan-FPS without fog ≥ 40 (gate before Phase 3 fog work begins) _(software-complete + sideload UAT verbal `approved` per Plan 02-06; FPS observed: sustained ~120 fps during pan / pinch / combined gestures at zoom 13–15 — 3× headroom over the gate. Idle-FPS ~4 fps is expected Flutter no-dirty-frames behaviour, not a regression. Evidence: `.planning/phases/02-map-no-fog/02-UAT.md`. Walked 2026-05-01 on iPhone 17 Pro against CI run 25212559648, SHA 46b8fcc.)_
- [ ] **PERF-03**: At Phase 3 UAT walk on iPhone 17 Pro: pan-FPS with fog active ≥ 30; idle-fog-animation FPS ≥ 50 _(Plan 03-08 walk on iPhone 17 Pro 2026-05-01: NOT MEASURED — walk aborted on visual grounds before deliberate FPS observation; PERF-03 is unmeasured-and-moot for this verdict because the failure mode is camera-lock correctness, not throughput. Even sustained 120 fps on a fog that doesn't translate with the camera would fail Criterion B. See `.planning/phases/03-fog-of-war-the-hypothesis/03-UAT.md`.)_
- [ ] **PERF-04**: At Phase 3 UAT walk: frame-delta probe (FOG-08) shows median ≤ 16 ms, p95 ≤ 32 ms, max ≤ 48 ms across ≥ 10 combined gestures _(Plan 03-08 walk on iPhone 17 Pro 2026-05-01: NOT CAPTURED — walk aborted on Criterion B's visual failure before the ≥ 10 combined-gesture seconds of probe rollup evidence could be recorded. Per the falsification clause, Criterion B's failure alone is sufficient for `denied`; Criterion A is unmeasured-and-moot. The probe code itself is software-complete and shipping in the IPA per FOG-08 verified-by-test entry. See `.planning/phases/03-fog-of-war-the-hypothesis/03-UAT.md`.)_
- [x] **PERF-05**: At Phase 3 UAT walk: developer's subjective verdict — no visible fog slip, no white-ellipse artefact during pan/zoom/combined gestures _(Plan 03-08 walk on iPhone 17 Pro 2026-05-01: **MEASURED — VERDICT DENIED.** Developer's verbatim words: *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*. Three of four Criterion B sub-claims fail (slide-then-snap manifested as worse-than-slide-then-snap *static* fog; reveal-hole lag is permanent; inversion is geometrically forced). PERF-05 is checked-as-MEASURED (not as-passed) — the requirement was to capture the developer's subjective verdict, which was captured; the verdict itself is `denied`. See `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` for the full Criterion B sub-claim breakdown and `03-UAT.md` for the walk evidence.)_
- [ ] **PERF-06**: Pixel 4a (Adreno 618) UAT walks at Phase 3 and Phase 5: app launches, fog renders, no crash; informational FPS recorded for cross-platform comparison (no hard pass criterion)
- [ ] **PERF-07**: At Phase 3.1 UAT walk on iPhone 17 Pro: frame-delta probe (FOG-08) shows median ≤ 16 ms, p95 ≤ 32 ms, max ≤ 48 ms across ≥ 10 combined gestures (PERF-04 carry-over: Plan 03-08 walk left this unmeasured-and-moot). _(Phase 3.1 — Plan 03.1-03)_

## v2 Requirements

Deferred to a follow-up if the POC succeeds and ports back to MirkFall, or to a future iteration of the POC if the hypothesis needs more visual fidelity to be conclusive.

### Visual Fidelity

- **STYLE-01**: Custom basemap theme replicating MirkFall's neutral palette (`#f5f1e8` / `#a6c9df` / etc.)
- **STYLE-02**: Multiple mirk styles beyond `atmospheric` (faded, neon, etc.)

### Robustness

- **ROB-01**: SDF rebuild moved to a worker isolate when disc count grows beyond ~100 (POC stays on UI isolate per donor-file's documented `< 16 ms` cost)
- **ROB-02**: PMTiles file integrity check (hash verification) on first-launch copy
- **ROB-03**: Graceful handling of GPS-permission-revoked-mid-session

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Custom basemap styling | Not on the critical path of the same-Canvas hypothesis; default renderer style suffices |
| Multiple mirk styles | Atmospheric only; visual variety is a v2 concern |
| Database (Drift / SQLite) | Discs stored in memory; POC has no persistence requirement |
| Session management | No cross-session state; each launch is fresh |
| Offline compaction, country switching, mirk download infrastructure | Out of POC's hypothesis scope |
| Burger menu, settings screen, live tuner sheet | Convenience UI; defer until migration |
| `MapView` domain abstraction | Talk to `flutter_map` directly; abstraction is a migration concern |
| `MirkInitialRevealFade` | Visual polish; not on the hypothesis path |
| `Permission.locationAlways`, notification permission | Only `locationWhenInUse` needed for the POC |
| Telemetry / analytics / crash reporting | Forbidden by GOSL v1.0 in any case |
| Parent-FPS comparison (criterion C) | Dropped — POC stands on absolute FPS + lock-correctness alone |
| Per-phase Pixel 4a UAT walks | Pixel 4a walked only at Phase 3 (hypothesis test) and Phase 5 (decision); per-phase double-walks are too costly |
| State management framework (Riverpod / Bloc / Provider) | Plain `StatefulWidget` + `setState` + constructor-injected services suffices for a 3-screen POC; ports back to MirkFall's framework on migration |

## Traceability

Filled by the roadmap on 2026-04-30. Five phases:
1. **Foundation** — bootstrap, CI, logger, share, FPS counter, permission gate
2. **Map (no fog)** — PMTiles, gestures, blue dot, recenter; ≥ 40 fps no-fog gate
3. **Fog of War — THE HYPOTHESIS** — fog layer, SDF, frame-delta probe, falsification walk
4. **Wisp Particles** — world-locked wisps, cross-pipeline parity
5. **Decision Gate** — final hardening, Pixel 4a sanity walk, formal POC verdict

| Requirement | Phase | Status |
|-------------|-------|--------|
| BOOT-01 | Phase 1 | Complete |
| BOOT-02 | Phase 1 | Complete |
| BOOT-03 | Phase 1 | Complete |
| BOOT-04 | Phase 1 | Complete |
| BOOT-05 | Phase 1 | Complete |
| BOOT-06 | Phase 1 | Complete |
| BOOT-07 | Phase 1 | Complete |
| BOOT-08 | Phase 1 | Complete |
| AUDIT-01 | Phase 1 | Complete |
| AUDIT-02 | Phase 1 | Complete |
| AUDIT-03 | Phase 1 | Complete |
| CI-01 | Phase 1 | Complete |
| CI-02 | Phase 1 | Complete |
| CI-03 | Phase 1 | Complete |
| CI-04 | Phase 1 | Complete |
| CI-05 | Phase 1 | Complete |
| AUTH-01 | Phase 1 | Complete |
| AUTH-02 | Phase 1 | Complete |
| AUTH-03 | Phase 1 | Complete |
| AUTH-04 | Phase 1 | Complete |
| AUTH-05 | Phase 1 | Complete |
| AUTH-06 | Phase 1 | Complete |
| MAP-01 | Phase 2 | Complete |
| MAP-02 | Phase 2 | Complete |
| MAP-03 | Phase 2 | Complete |
| MAP-04 | Phase 2 | Complete |
| MAP-05 | Phase 2 | Complete |
| MAP-06 | Phase 2 | Complete |
| LOC-01 | Phase 2 | Complete |
| LOC-02 | Phase 2 | Complete |
| LOC-03 | Phase 2 | Complete |
| LOC-04 | Phase 2 | Complete |
| LOC-05 | Phase 2 | Complete |
| FOG-01 | Phase 3 | Complete — Verified-by-test (P03-01 stub; P03-02 RevealDiscRepository; P03-07 MapScreen wiring — append on every fix with hand-rolled rvd_ ID) |
| FOG-02 | Phase 3 | Complete — Verified-by-test (P03-01 stub; P03-02 distanceMetres degree-distance regression test GREEN) |
| FOG-03 | Phase 3 | Complete — Verified-by-test (P03-01 stubs; P03-03 SdfCache + SdfRebuildLogger; 1-Hz JSONL rollup + stop()-flush tests GREEN) |
| FOG-04 | Phase 3 | **Falsified-in-production (P03-08 walk DENIED 2026-05-01)** — structural test passes but production walk reveals fog does NOT translate with camera during pan; widget-tree containment did not imply Canvas-transform sharing. Phase 3.1 gap-closure required. See 03-FALSIFICATION.md. |
| FOG-05 | Phase 3 | **Falsified-in-production (P03-08 walk DENIED 2026-05-01)** — uniforms populate correctly per slot-gate test, but the painter's Canvas does not consume the tile-layer's translation transform. See 03-FALSIFICATION.md. |
| FOG-06 | Phase 3 | **Falsified-in-production (P03-08 walk DENIED 2026-05-01)** — clip path computed correctly per P03-05 tests, but applied in painter-local coordinate space which does not translate with the camera. See 03-FALSIFICATION.md. |
| FOG-07 | Phase 3 | **Falsified-in-production (P03-08 walk DENIED 2026-05-01)** — single-MapCamera-snapshot enforcement passes structurally (P03-05 KEYSTONE GREEN), but the snapshot is plausibly stale during pan-driven repaints OR consumed in screen-space without applying the translation transform (Phase 3.1 diagnostic possibilities #1/#2/#3 in 03-FALSIFICATION.md). |
| FOG-08 | Phase 3 | Complete — Verified-by-test (P03-01 stubs; P03-04 ring buffer + 1-Hz JSONL rollup + dual-clock; P03-06 overlay; P03-07 wires probe.start in initState + overlay at top:104 right:8 in MapScreen Stack). Quantitative walk evidence not captured (P03-08 aborted on visual grounds before probe rollups recorded), but the probe code itself ships in the IPA. |
| FOG-09 | Phase 3.1 | Pending |
| FOG-10 | Phase 3.1 | Pending |
| WISP-01 | Phase 4 | Pending |
| WISP-02 | Phase 4 | Pending |
| WISP-03 | Phase 4 | Pending |
| WISP-04 | Phase 4 | Pending |
| LOG-01 | Phase 1 | Complete |
| LOG-02 | Phase 1 | Complete |
| LOG-03 | Phase 1 | Complete |
| LOG-04 | Phase 1 | Complete |
| LOG-05 | Phase 1 | Complete |
| PERF-01 | Phase 1 | Complete |
| PERF-02 | Phase 2 | Complete |
| PERF-03 | Phase 3 | Not measured (P03-08 walk aborted on visual grounds; PERF-03 is unmeasured-and-moot for the `denied` verdict). |
| PERF-04 | Phase 3 | Not captured (P03-08 walk aborted before ≥ 10 combined-gesture seconds of probe rollups; per falsification clause Criterion B's failure alone delivers `denied`, so Criterion A is unmeasured-and-moot). |
| PERF-05 | Phase 3 | **Measured — VERDICT DENIED (P03-08 2026-05-01)**. Developer's verbatim words: *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*. See 03-FALSIFICATION.md. |
| PERF-06 | Phase 5 | Pending |
| PERF-07 | Phase 3.1 | Pending |

**Coverage:**
- v1 requirements: 59 total
- Mapped to phases: 59
- Unmapped: 0 ✓

**Per-phase counts:**
- Phase 1 (Foundation): 28 requirements (BOOT × 8, AUDIT × 3, CI × 5, AUTH × 6, LOG × 5, PERF-01)
- Phase 2 (Map, no fog): 12 requirements (MAP × 6, LOC × 5, PERF-02)
- Phase 3 (Fog — THE HYPOTHESIS): 11 requirements (FOG × 8, PERF-03/04/05)
- Phase 3.1 (Fix Fog Pan-Translation): 3 requirements (FOG-09, FOG-10, PERF-07)
- Phase 4 (Wisps): 4 requirements (WISP × 4)
- Phase 5 (Decision Gate): 1 requirement (PERF-06)

## Revisions

- **2026-04-30 (Phase 1 planning):** LOG-05 wording softened — dropped the prior 50-megabyte synthetic-logfile smoke-test specification per CONTEXT.md `Phase 1 UAT exit gate` decision. The replacement gate is verbal "approved" after a single sideload + Mail round-trip walk.
- **2026-04-30 (Phase 1 planning, B-1 fix):** BOOT-01 SDK pin updated from `3.41.8` to `3.41.7` for parent code-donor parity per RESEARCH.md Open Question #1. The earlier 3.41.8 wording predated the planner's parent-parity lock; Plan 01 (`flutter create`) and Plan 03 Task 2 (CI workflow `flutter-version: '3.41.7'`) both reference 3.41.7. This wording change brings REQUIREMENTS.md into lockstep with both plans.
- **2026-05-01 (Phase 1 closure, Plan 01-07 SUMMARY):** LOG-03 marked Complete after source review of `lib/main.dart` confirmed `await FileLogger.bootstrap()` runs BEFORE `WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver())` and BEFORE `runApp(MirkPocApp)`. AUTH-04 carries a deferred-bug note (cross-restart auto-resume routing bug; software-complete per Plan 01-06, sideload UAT confirms manual deny + Open Settings flow works; cross-restart auto-nav from /denied to /map after iOS Settings toggle does not fire — deferred per user's POC-scope call). Phase 1 closes with all 28 requirement IDs addressed; AUTH-04 alone carries the documented limitation.
- **2026-05-01 (Phase 2 closure, Plan 02-06 SUMMARY):** PERF-02 marked Complete after sideload UAT walk on iPhone 17 Pro against CI run `25212559648` (SHA `46b8fcc`). Developer's verbatim verdict: *"everything works well, 120 fps when doing stuff, revert to 4 when not doing anything"*. Sustained ~120 fps observed during pan / pinch / combined gestures at zoom 13–15 — 3× headroom over the ≥ 40 fps gate. Idle-FPS ~4 fps documented as expected Flutter no-dirty-frames behaviour (same pattern observed in Phase 1 sideload UAT). Evidence: `.planning/phases/02-map-no-fog/02-UAT.md`. Phase 2 closes with all 12 requirement IDs Complete; Phase 3 (fog hypothesis) unblocked with massive frame-budget headroom for the fog shader.
- **2026-05-01 (Phase 3 closure, Plan 03-08 SUMMARY — HYPOTHESIS DENIED):** Plan 03-08 sideload UAT walk on iPhone 17 Pro against CI run `25224334312` (SHA `280dd04`) over central Melun delivered a **DENIED** verdict on the same-Canvas fog hypothesis. Developer's verbatim words: *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*. Fog renders correctly on screen (the pre-walk `/sanity` shader-compile gate held — the developer saw "mirk" during the walk), and rotation gestures DO transform the fog surface, but **translation/pan does not**: the fog stays static relative to the screen while the underlying tile layer translates beneath it. The structural FOG-04 test (`find.descendant(of: FogLayer, matching: MobileLayerTransformer)`) passed but the behavioural consequence (Canvas-transform sharing) does not follow. **FOG-04..07 flipped to Falsified-in-production**; FOG-01..03 + FOG-08 retain Complete (verified-by-test: probe code, repository, distance helper, SDF cache + logger all software-functional). **PERF-05 marked Measured-with-DENIED-verdict**; PERF-03/04 marked Not-measured (walk aborted on visual grounds before quantitative evidence was collected — moot per falsification clause: Criterion B's failure alone delivers `denied`). MirkFall migration recommendation: **DO NOT PORT BACK as-implemented**. Three diagnostic possibilities documented in 03-FALSIFICATION.md (camera-staleness during pan-driven repaints; transform-bypass at painter Canvas; widget-tree-vs-Canvas-matrix transform application by `MobileLayerTransformer`). Phase 3.1 gap-closure investigation phase is the recommended next step to diagnose the camera-translation propagation path before any port-back attempt; Phase 4 (wisp particles) does NOT unblock until Phase 3.1 produces a fix or formally confirms the failure is unfixable. Evidence: `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` + `03-UAT.md`.
- **2026-05-02 (Phase 3.1 planning, Plan 03.1-01):** Three new v1 requirement IDs added — FOG-09 (behavioural transform-equality regression test), FOG-10 (`FogTransformLogger` per-paint diagnostic instrumentation), PERF-07 (post-fix Criterion A measurement re-running PERF-04 methodology that Plan 03-08 left unmeasured-and-moot). Total v1 requirements grow from 56 to 59. Phase 3.1 is the gap-closure phase that either reverses the Plan 03-08 `DENIED` verdict to `CONFIRMED-AFTER-FIX` or strengthens it to `DENIED-FINAL`. The structural FOG-04 test is augmented (forward-pointer docstring) but not replaced; the new FOG-09 test catches the Plan 03-08 static-fog failure mode mechanically without a sideload walk.

---
*Requirements defined: 2026-04-30*
*Last updated: 2026-04-30 — traceability filled by roadmapper (5 phases, 56/56 mapped)*
