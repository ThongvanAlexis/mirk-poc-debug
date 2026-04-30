# Project Research Summary

**Project:** MirkFall Same-Canvas POC
**Domain:** Pure-Flutter fog-of-war map POC -- architectural hypothesis validation + code donor for MirkFall
**Researched:** 2026-04-30
**Confidence:** HIGH for stack and architecture decisions; MEDIUM for vector tile render performance at scale (no device data yet); LOW for share_plus Mail attachment on free-Apple-ID sideloaded build (flagged for Phase 0 smoke test)

---

## Executive Summary

This project is an architectural proof-of-concept, not a product. Its single question: can rendering the MirkFall map, fog-of-war shader, and wisp particles in one unified Flutter Canvas pipeline eliminate the 1-3 frame camera-tracking lag (BUG-014) that six iterations of compensation failed to fix inside the `maplibre_gl` native platform-view architecture? All research converges on the same answer: yes, structurally, and the tooling to test it exists today on stable Flutter. The recommended renderer is `flutter_map` 7.0.2 (stable chain with `vector_map_tiles` 8.0.0 and `vector_map_tiles_pmtiles` 1.5.0), because every layer in a `FlutterMap` widget reads `MapCamera.of(context)` from the same `MapInheritedModel` in the same build pass -- there is no platform channel, no separate native render thread, no 20 Hz bbox query. The fog shader (`atmospheric_fog.frag`) ports verbatim; the integration shim (`FogLayer`) is fewer than 150 lines of new code.

The critical constraint established by STACK research: ARCHITECTURE research cited `flutter_map` 8.3.0, but the only pub-resolvable chain is `flutter_map` 7.0.2 + `vector_map_tiles` 8.0.0 + `vector_map_tiles_pmtiles` 1.5.0. `vector_map_tiles 8.0.0` hard-pins `flutter_map ^7.0.2`; the flutter_map 8.x + vector_map_tiles 8.0 combination cannot `pub get`. All architectural reasoning from ARCHITECTURE.md (single Canvas, single paint pass, `RepaintBoundary` discipline, `MapCamera.of(context)` anchor) holds fully at flutter_map 7.0.2 -- none of it depends on a specific 7.x vs 8.x release. The stable chain removes a potential confound: if performance is poor, the cause is the renderer category, not a beta regression. State management is plain `StatefulWidget` + `setState` (no Riverpod); the POC has three screens with non-trivial state only in `MapScreen`, and adding Riverpod codegen overhead to a 3-screen POC is not justified. On port-back to MirkFall, the StatefulWidget becomes a Riverpod Notifier -- a small mechanical refactor.

The primary risks are: (1) `vector_map_tiles` label-collision computation on the UI isolate may push pan FPS below 30 fps before fog is even added -- this must be baselined in Phase 2 and is a project-kill criterion if unresolvable; (2) the fog may track the map in isolation but re-introduce BUG-014 symptoms if `MapCamera` is sampled at more than one point per frame; (3) wisp particle positions must be converted from screen pixels to `LatLng` (world space) before porting -- verbatim port of `WispParticleSystem` carries the pixel-space bug. The single most important mitigation is to wire the frame-delta probe (Feature K) before the hypothesis-test walk, and to write the falsification criteria down before Phase 3 begins.

---

## Key Findings

### Recommended Stack

The resolved dependency chain is: Flutter 3.41.8 stable / Dart 3.11.x, `flutter_map` 7.0.2, `vector_map_tiles` 8.0.0, `vector_map_tiles_pmtiles` 1.5.0, plus `vector_tile_renderer` 5.2.0, `pmtiles` 1.2.0, and `latlong2` 0.9.1 as explicit transitive pins. All other packages (`permission_handler` 12.0.1, `geolocator` 14.0.2, `go_router` 16.0.0, `logging` 1.3.0, `path_provider` 2.1.5, `path` 1.9.1, `share_plus` 12.0.2, `flutter_lints` 6.0.0) match the parent MirkFall project exactly, enabling clean code-donor port-back. `share_plus` is pinned at 12.0.2 (not 13.x) to reuse the parent audit row and avoid win32 transitive churn. Every package is MIT / BSD-2 / BSD-3 -- GOSL-clean with zero telemetry. `mapsforge_flutter` is LGPL-blocked; `flutter_gpu` / vector_map_tiles 10-beta requires the Flutter master channel; custom MVT-on-Canvas is 4-8 weeks of reinvention; MapLibre native custom layer requires a Mac and a three-platform shader port. `flutter_map` is the only viable path.

**Version conflict resolved:** ARCHITECTURE.md cited flutter_map 8.3.0. STACK.md verified via the constraint solver that this combination cannot resolve with vector_map_tiles 8.0.0. Trust STACK. All architectural claims in ARCHITECTURE.md hold verbatim at 7.0.2.

**Core technologies:**

| Slot | Package | Pinned version | Why |
|------|---------|----------------|-----|
| Flutter SDK | flutter stable | 3.41.8 | Matches parent; Impeller default on iOS; FragmentProgram fully supported |
| Map renderer | flutter_map | 7.0.2 | Pure-Flutter Canvas; only stable-chain resolver; same paint pass as fog |
| Vector tiles | vector_map_tiles | 8.0.0 | Only maintained pure-Flutter MVT renderer; hard-pins flutter_map 7.x |
| PMTiles loader | vector_map_tiles_pmtiles | 1.5.0 | MIT; resolves to vector_map_tiles ^8.0.0 |
| Location | geolocator | 14.0.2 | Parent-validated; MIT; no telemetry |
| Permissions | permission_handler | 12.0.1 | Parent-validated; MIT; iOS 12+ |
| Logging | logging | 1.3.0 | BSD-3; hierarchical loggers; parent-validated |
| Share | share_plus | 12.0.2 | BSD-3; UIActivityViewController; reuses parent audit |
| Routing | go_router | 16.0.0 | BSD-3; parent-mandated; 3-route graph |
| State | StatefulWidget + setState | (SDK) | No framework; 3-screen POC does not justify Riverpod overhead |

### Expected Features

All in-scope features from PROJECT.md are P1 or P2. The scope is already pre-cut.

**Must have (table stakes -- hypothesis unanswerable without these):**

- Permission gate (`locationWhenInUse` only) -- no location, no discs, no fog signal
- Map rendering with bundled PMTiles (`Fra_Melun.pmtile` copied to `getApplicationSupportDirectory()` on first launch; `asset:///` URI is not supported by vector_map_tiles_pmtiles, per issue #44 closed "not planned")
- Pan / zoom / combined-gesture handling -- the combined gesture is the BUG-014 reproducer
- Blue dot (GPS marker) -- visual anchor for fog-vs-map sync evaluation; must be in the same Canvas as the fog, not a Stack overlay
- Fog rendering in the same Canvas as the map -- the hypothesis itself
- Reveal discs + SDF rebuild (debounced 100-200 ms; UI isolate OK at <100 discs; instrument rebuild time)
- File logger (one file per session) -- only feedback channel from iOS sideload to Windows dev
- Email-share for log file via share_plus -- closes the feedback loop
- Recenter FAB with in-memory `_lastFix` cache (do NOT use `Geolocator.getLastKnownPosition()` -- returns null or `[0.0, 10.69]` on iOS unreliably)
- Frame-delta probe (Feature K, ~50 LOC) -- falsifier; must be wired before the Phase 3 hypothesis walk
- CI: unsigned IPA on macos-latest + debug APK on ubuntu-latest on every push

**Should have (strengthens signal quality and code-donor completeness):**

- Wisp particles (`WispParticleSystem` adapted port) -- cross-pipeline parity check; code-donor completeness. WARNING: positions must be converted to `LatLng` world-space before porting (see Critical Pitfalls).
- FPS counter visible during iOS walk (built in Phase 0, not Phase 3)

**Defer (migration phase, not POC):**

- MirkFall basemap theme (`#f5f1e8` / `#a6c9df` etc.) -- orthogonal to the hypothesis
- Worker-isolate SDF rebuild -- profiling data from the POC informs the migration
- MapView domain abstraction -- migration concern, not POC concern
- DB-backed disc persistence (Drift) -- in-memory list is explicit POC scope
- Multiple mirk styles, country switching, session management, notifications

**Anti-features (categorically excluded):**

- Any telemetry, analytics, crash reporting -- forbidden by GOSL v1.0; no exceptions
- `maplibre_gl` -- re-imports the platform-view problem the POC is escaping
- `mapsforge_flutter` -- LGPL-3.0, GOSL-blocked
- `flutter_gpu` / vector_map_tiles 10-beta -- requires Flutter master channel

### Architecture Approach

The recommended architecture places `FogLayer` and `WispLayer` as direct children of `FlutterMap`'s `children` list, alongside `VectorTileLayer` and `MarkerLayer`. All children share one `MapInheritedModel` instance -- the same camera object, the same frame, the same `RepaintBoundary`. `FogLayer.build()` calls `MapCamera.of(context)` exactly once at the top of `build()` and passes the captured camera to `_FogPainter.paint()`, which uses it to compute the clip path, shader uniforms, and SDF rect. The outer `RepaintBoundary` that `FlutterMap` already provides is the only one -- adding a second `RepaintBoundary` around `FogLayer` would re-create the BUG-014 pipeline split in miniature. The `uSdfRect` uniforms are always identity (0, 0, 1, 1) -- the disc-bbox SDF optimisation from BUG-014 Iteration 4 must NOT be reproduced here; it compensated for platform-view lag that no longer exists.

Twelve donor files port verbatim from MirkFall (shader, SDF builder, projection helpers, wisp system, constants -- all renderer-agnostic Dart). The only new code is `FogLayer` (~100-150 LOC), `WispLayer` (~50 LOC), and `PMTilesAssetUnpacker`. The file structure mirrors MirkFall's `domain/` / `application/` / `infrastructure/` / `presentation/` split for clean port-back.

**Major components:**

| Component | Type | Responsibility |
|-----------|------|----------------|
| `FogLayer` | New -- only renderer-specific shim | Reads `MapCamera.of(context)` once; paints shader + clip path |
| `WispLayer` | New -- same pattern as FogLayer | Reads `MapCamera.of(context)` once; composites after fog |
| `atmospheric_fog.frag` | Verbatim port | 41 float uniforms + 1 sampler; slot order from BUG-014 Iteration 2 fix preserved |
| `RevealedSdfBuilder` | Verbatim port | 256x256 `ui.Image` R-channel SDF; <16 ms for <100 discs |
| `MirkProjection` | Verbatim port | lat/lon to screen Offset; used by FogLayer and WispLayer |
| `WispParticleSystem` | Port with required adaptation | Positions converted from `Offset` (pixels) to `LatLng` (world space) |
| `PMTilesAssetUnpacker` | New | Copies 4 MB asset to `getApplicationSupportDirectory()` once; idempotent |
| `MapScreen` (StatefulWidget) | New | Hosts FlutterMap; owns MapController; fans out position stream |

### Critical Pitfalls

The five most actionable pitfalls -- ones that can produce a wrong POC answer or a multi-day stuck state:

1. **Wisp positions stored in screen pixels in the donor file** -- `WispParticleSystem` stores each particle as an `Offset` in screen pixels. Verbatim port = every camera pan desyncs wisps from disc perimeters (BUG-014 applied to particles). Fix before first wisp paint: redefine `WispParticle.position` as `LatLng`; integrate velocity in metres/sec (not px/sec); render via `MapCamera.latLngToScreenPoint`. Add a unit test: simulate 100 m camera pan; assert wisp logical position is unchanged.

2. **`vector_map_tiles` label-collision computation on the UI isolate** -- In dense urban Melun at zoom 13-15, label collision is the main pan-time cost. If FPS is below ~40 during a no-fog pan baseline (Phase 2), fog cannot hit 30 fps on top. Measure as Phase 2 exit gate. If <40 fps: thin label density. If still <30 fps: renderer evaluation is the project-kill branch.

3. **Combined-zoom+pan displacement trap** -- Even with same-Canvas architecture, reading `MapCamera` at more than one point per frame re-introduces BUG-014 white-ellipse symptom (different cause, identical symptom). Enforce: all three paint-time consumers (SDF rect, clip path, shader uniforms) receive the same `MapCamera` instance captured once at the top of `FogLayer.build()`. Write this as a unit test before the Phase 3 walk.

4. **PMTiles asset copy at the wrong point in the lifecycle** -- The copy must happen during the permission-grant flow, not inside `MapScreen.build()`. Use `getApplicationSupportDirectory()` (not Documents -- iCloud-backed). Log copy duration at INFO. If copy races with first map paint: blank map with variable duration and no logged error -- a confound that wastes an iOS walk.

5. **No baseline FPS against the parent project** -- The POC go/no-go is "same-Canvas locks correctly AND pan-FPS is at least 0.7x the parent pan-FPS." Without measuring the parent, a 32 fps POC on a 55 fps parent is a net 42% regression -- the hypothesis holds but the trade-off is unclear. Port the FPS counter to MirkFall for one walk before declaring POC success.

---

## Falsification Criteria for the Hypothesis

The hypothesis ("same-Canvas eliminates the lag") is confirmed only when all three of the following are true:

**Criterion A -- Frame-delta (quantitative, from Feature K):**
Over a 5-minute Melun walk with at least 10 deliberate combined pinch-zoom+pan gestures: median camera-to-fog-paint delta <= 16 ms, p95 <= 32 ms, max <= 48 ms. If max exceeds 48 ms during combined gestures, the same-Canvas claim requires investigation (camera-snapshot discipline broken at the `flutter_map` layer).

**Criterion B -- Visual lock (subjective, from iOS walk):**
No visible fog slide-then-snap, no white-ellipse artefact on fast zoom, no reveal hole that lags behind the blue dot by a perceptible amount. At least 10 combined pinch-zoom+pan gestures and 3 recenter-button taps during the walk.

**Criterion C -- FPS parity (comparative):**
POC pan-FPS >= 0.7x parent MirkFall pan-FPS on the same iPhone, same ~5-minute route, measured by an in-app FPS counter. Below this threshold: the architecture is correct in principle but the renderer has an unacceptable performance trade-off relative to maplibre_gl, warranting deeper renderer evaluation before migration.

**Walk-replay falsification tool:**
Record GPS fixes as `(timestamp, lat, lon, accuracy)` during a real walk. Replay on Pixel 4a at 1x and 5x speed without re-walking. Used to reproduce borderline results across iterations.

**Hypothesis denied early (valid outcome):**
If Criterion A shows consistent >48 ms deltas despite single-camera-snapshot discipline, the same-Canvas hypothesis is partially false at the `flutter_map` layer. Document and investigate whether rendering fog inside `vector_map_tiles` theme system resolves it before concluding the hypothesis is wrong. A denied hypothesis is a valid and scientifically useful POC outcome.

---

## Implications for Roadmap

All four researchers independently suggested the same six-phase decomposition. The synthesis below resolves minor numbering differences and adds the falsification gate explicitly.

### Phase 0: Bootstrap, CI, and Test Infrastructure

**Rationale:** The iOS sideload loop is the only valid test vehicle. Without CI producing an unsigned IPA on every push, no other phase can be walked on iOS. Without the file logger and share button, iOS bugs are invisible from Windows. These are load-bearing infrastructure, not setup chores.

**Delivers:** Empty Flutter app; all deps strictly pinned in `pubspec.yaml`; `DEPENDENCIES.md` first-pass audit; CI with three jobs (lint + build-android + build-ios); unsigned IPA downloadable from GitHub Actions on every push; file logger writing to `<app_documents_dir>/logs/yyyymmdd_hhmmss_logs.txt`; share-logs button; `tool/check_licenses.dart` ported from parent; `analysis_options.yaml` strict mode with `use_build_context_synchronously`; FPS counter widget; shader sanity screen stub; SideStore bundle ID `com.thongvan.mirkpoc`; GOSL copyright header on all `.dart` files.

**Addresses:** Logger (H), Email-share (I) from FEATURES.md

**Avoids:** Pitfall 6 (no iOS walk without CI IPA), Pitfall 8 (telemetry creep without CI license gate), Pitfall 9 (SideStore caps), Pitfall 14 (FPS counter refresh-rate awareness), Pitfall 20 (Flutter version pinned)

**iOS UAT gate:** Sideload empty IPA. Tap share button. Verify log file arrives in Mail with correct content and byte count. Confirm FPS counter visible. This must pass before Phase 1 begins -- it proves the round-trip works.

**Research flag:** STANDARD PATTERNS. Mirror parent CI exactly.

---

### Phase 1: Permission Gate

**Rationale:** Permission is the topological root of the entire feature graph. It is also the cheapest phase and establishes the GoRouter routing graph. The map screen must not instantiate until `PermissionStatus.granted`.

**Delivers:** `PermissionGateScreen`; `PermissionDeniedScreen` with `openAppSettings()` link; `AppLifecycleState.resumed` re-check (iOS does not auto-callback after settings round-trip); GoRouter graph (`/` to `/map` via `context.go`, `/` to `/denied` via `context.go`); `Info.plist` with `NSLocationWhenInUseUsageDescription` (French string); `ITSAppUsesNonExemptEncryption = false`; `PrivacyInfo.xcprivacy` copied from parent.

**Addresses:** Permission gate (A)

**Avoids:** Pitfall 15 (BuildContext-after-await violations), Pitfall 16 (geolocator lifecycle observer scaffold)

**iOS UAT gate:** Grant permission -> map placeholder appears. Deny -> denied screen. Tap "Open Settings" -> return -> re-check fires.

**Research flag:** STANDARD PATTERNS.

---

### Phase 2: Map + PMTiles + Gestures + Blue Dot + Recenter

**Rationale:** The second-biggest risk is vector tile render FPS on iOS. If `vector_map_tiles` cannot sustain 40+ fps on a no-fog pan through central Melun at zoom 13-15, Phase 3 is compromised before fog is added. Cheaper to discover here. The PMTiles asset copy belongs here as a blocking precondition before `MapScreen` mounts. The blue dot and recenter FAB are cheap and make Phase 3 usable.

**Delivers:** `PMTilesAssetUnpacker` (copies `Fra_Melun.pmtile` to `getApplicationSupportDirectory()`; idempotent; logs copy duration at INFO); `MapScreen` with `FlutterMap` + `VectorTileLayer`; pan/zoom/combined-gesture handling; `BlueDotMarkerLayer` (same-Canvas, not Stack overlay); recenter FAB with in-memory `_lastFix` cache; no-fog FPS baseline measurement documented.

**Addresses:** Map + PMTiles (B), Blue dot (D), Recenter button, Pan/zoom/gestures (C)

**Avoids:** Pitfall 4 (PMTiles I/O before map mounts), Pitfall 5 (vector tile FPS baselined here as exit gate), Pitfall 18 (tile cache eviction on fast zoom)

**iOS UAT gate:** Walk 200 m in Melun. Pan, zoom, combined pinch-zoom+pan. FPS counter must show >= 40 fps sustained. Blue dot follows. Recenter works. Tiles do not blank on rapid zoom-out. If FPS < 40 without fog: STOP and evaluate label-thinning mitigation before Phase 3.

**Research flag:** MEDIUM. Performance of `vector_map_tiles` 8.0.0 on this specific PMTiles at zoom 13-15 has no published numbers. The Phase 2 walk IS the research. This is the highest-probability project-blocking risk.

---

### Phase 3: THE HYPOTHESIS -- Fog Layer + SDF + Frame-Delta Probe

**Rationale:** This is the architectural test. All prior phases exist to make this phase testable. If fog drifts despite same-Canvas architecture, the POC conclusion is "wrong renderer" and the project terminates with documented findings. Wisps are excluded to give the cleanest fog-vs-map signal. The frame-delta probe must be wired here, not in Phase 4.

**Delivers:** Port of `RevealedSdfBuilder`, `MirkProjection`, `tile_cell_iteration`, `FogShaderUniforms`, `animation_helpers`, `atmospheric_fog.frag` (verbatim, including BUG-014 Iteration 2 slot-reorder fix), `kMirkFog*` constants; `FogLayer` widget (~100-150 LOC; `MapCamera.of(context)` read exactly once per build); in-memory `RevealDiscRepository` (one 25 m disc per GPS fix); identity `uSdfRect` (0, 0, 1, 1 -- never dynamic); frame-delta probe (Feature K, ~50 LOC); falsification criteria written down before the walk.

**Addresses:** Fog rendering in same Canvas (E), Reveal discs + SDF (F), Frame-delta probe (K)

**Avoids:** Pitfall 2 (degree-distance in SDF -- unit test before walk), Pitfall 3 (Impeller transpiler -- shader sanity screen on device first), Pitfall 10 (combined-zoom+pan displacement -- single MapCamera snapshot, unit tested before walk), Anti-Pattern 1 (dynamic uSdfRect), Anti-Pattern 2 (RepaintBoundary around FogLayer), Anti-Pattern 3 (MapCamera from setState callback)

**Pre-walk gates (must pass before the iOS walk):**
- Unit test: `distanceMetres(LatLng(48.5, 2.6), LatLng(48.5, 3.6))` returns ~73.7 km (not ~111 km)
- Unit test: SDF rect, clip path, and shader uniforms all derive from the same `MapCamera` instance
- Shader sanity screen passes on iOS device (fog renders with hardcoded uniforms)
- Falsification criteria written down in advance

**iOS UAT gate:** 5-minute walk, >= 10 combined pinch-zoom+pan gestures, >= 3 recenter taps. Criteria A, B, and C must all pass. A "hypothesis denied" result terminates the project before Phase 4 with documented findings -- that is a valid and valuable outcome.

**Research flag:** HIGH. Most failure modes. Shader sanity screen and unit tests are mandatory before the walk.

---

### Phase 4: Wisp Particles

**Rationale:** Wisps are categorised Differentiator rather than Table Stakes because Phase 3 already answers the hypothesis. Phase 4 adds cross-pipeline parity value and completes the code-donor package. If Phase 3 revealed an issue requiring remediation, Phase 4 can be deferred without invalidating the scientific result.

**Delivers:** Adapted `WispParticleSystem` (positions converted from `Offset` to `LatLng`; velocity integrated in metres/sec; curl-scale re-tuned for metre input; render projects via `MapCamera.latLngToScreenPoint`); `WispLayer` (~50 LOC; composited after `FogLayer`); 5 s warm-up gated on first GPS fix; BUG-015 fix preserved; 200-particle cap enforced.

**Addresses:** Wisp particles (G)

**Avoids:** Pitfall 1 (wisps in pixel space -- the primary adaptation), Pitfall 13 (wisp pre-fix warm-up glitch)

**iOS UAT gate:** Same route as Phase 3. Wisps appear after 5 s from first fix. No burst on app open. Wisps remain anchored to disc perimeters during pan/zoom. FPS still >= 30. Cross-parity: same lat/lon produces visually equivalent wisp positions in POC vs. parent MirkFall build.

**Research flag:** STANDARD PATTERNS for the port. Pixel-to-LatLng adaptation is the only novel work.

---

### Phase 5: Polish, Hardening, and Decision Gate

**Rationale:** After the visual product is correct, lock everything down for port-back. Also: measure the parent project pan-FPS for the go/no-go comparative criterion (Criterion C). This phase produces the formal POC verdict.

**Delivers:** Full `DEPENDENCIES.md` (license, telemetry, transitive chain audited for every package in `pubspec.lock`); GOSL copyright header audit; zero analyzer warnings, zero format violations; `check_licenses.dart` + `check_dependencies_md.dart` CI tools ported from parent; parent project pan-FPS measurement (one walk on same route with FPS counter added to MirkFall); formal POC verdict document; Pixel 4a Android-OpenGLES Y-flip sanity check.

**Avoids:** Pitfall 7 (no baseline FPS without parent measurement), Pitfall 17 (shader Y-flip on Android OpenGLES)

**iOS UAT gate:** Final sideload walk. Same Phase 3 criteria. Plus: share log, verify byte count. Plus: all CI jobs green. Plus: parent FPS comparison documented.

**Research flag:** STANDARD PATTERNS.

---

### Phase Ordering Rationale

- **Phase 0 before everything:** The iOS feedback loop must be proven end-to-end before any map code is written. No CI = no iOS walks = no validation.
- **Phase 1 before Phase 2:** Permission is the topological root; `MapScreen` must not instantiate before permission is granted.
- **Phase 2 before Phase 3:** Vector tile FPS is the second-biggest unknown. Phase 3 fog cannot hit 30 fps if the renderer is already below 40 fps without fog. Phase 2 is a gatekeeping phase.
- **PMTiles copy in Phase 2:** Completing it here means Phase 3 starts with a confirmed working map.
- **Frame-delta probe in Phase 3, not Phase 4:** It is the falsifier; it must be present when the hypothesis is tested.
- **Wisps after fog (Phase 4 after Phase 3):** Wisps add visual noise that can mask fog-tracking errors; testing fog in isolation gives the cleanest signal.
- **FPS counter in Phase 0, not Phase 3:** Needed for the Phase 2 baseline walk. Building it at Phase 0 costs nothing and removes urgency during Phase 3.

### Research Flags

**Needs deeper investigation during the phase itself:**
- **Phase 2:** `vector_map_tiles` 8.0.0 pan-FPS on iOS with `Fra_Melun.pmtile` at zoom 13-15 -- no published numbers. The Phase 2 walk IS the research. If result is below 40 fps without fog: evaluate label density thinning, then renderer replacement. Highest-probability project-blocking risk.
- **Phase 3:** Shader transpilation on iOS Impeller-Metal -- validate with shader sanity screen on device before the fog walk. The 41-uniform shader is beyond the well-tested range in the Flutter issue tracker.

**Standard patterns (no additional research needed):**
- **Phase 0:** CI mirrors parent MirkFall; logger pattern mirrors parent.
- **Phase 1:** Permission gate is well-documented; parent project has a superset.
- **Phase 4:** Wisp port is straightforward once the LatLng conversion is designed.
- **Phase 5:** Dependency audit, GOSL header check, CI tooling are established patterns from the parent.

---

## Open Questions for Requirements / Roadmap Phase to Resolve

**1. iPhone model (affects frame pacing and Criterion C FPS comparison)**
PROJECT.md does not name the iPhone model. If it is a ProMotion device (13 Pro+, 14 Pro+, 15 Pro+), the 30 fps criterion must be ">=50% of device refresh rate" not ">=30 fps absolute." The requirements phase must record the iPhone model and the FPS counter must report device refresh rate alongside fps (Pitfall 14).

**2. Pixel 4a OpenGL ES fallback exposure**
The Pixel 4a (Adreno 618) uses Vulkan on Android 11+. Flutter issue #179268 documents gradient rendering bugs on the Impeller-OpenGL ES fallback path. The requirements phase must document whether OpenGL ES compatibility is in scope for the POC or only for the MirkFall migration -- this determines whether a second Android device is needed for Phase 5.

**3. share_plus + Mail smoke test result (Phase 0 UAT gate)**
Confidence on share_plus behaviour on a free-Apple-ID SideStore-signed build is LOW. The roadmap must explicitly list "share a 50 MB synthetic log via Mail and verify byte count on the receiving side" as Phase 0 UAT gate, and the result must be documented before Phase 1 begins.

---

## Decisions Already Locked vs. Deferred

### Locked (do not re-open without strong new evidence)

| Decision | Evidence | Rationale |
|----------|----------|-----------|
| flutter_map 7.0.2 (not 8.x) | STACK constraint solver | vector_map_tiles 8.0.0 hard-pins flutter_map ^7.0.2; no other stable chain exists |
| No Riverpod / no state management framework | STACK + ARCHITECTURE conflict resolved | 3-screen POC; overhead unjustified; StatefulWidget + setState is the right scope |
| vector_map_tiles_pmtiles asset-copy workaround | FEATURES + flutter_map_plugins issue #44 | asset:/// URI not supported; filesystem path required |
| Identity uSdfRect (0, 0, 1, 1) -- never dynamic | ARCHITECTURE anti-patterns | Dynamic uSdfRect re-introduces BUG-014 root cause |
| No RepaintBoundary around FogLayer | ARCHITECTURE anti-patterns | Would re-create BUG-014 pipeline split inside Flutter |
| MapCamera.of(context) read exactly once per FogLayer build | ARCHITECTURE Pattern 3 + Pitfall 10 | Multiple reads = frame-stale inconsistency = white-ellipse symptom |
| WispParticle positions must be LatLng, not Offset | Pitfall 1 | Verbatim port carries the pixel-space bug |
| Frame-delta probe wired in Phase 3 | Feature K + Pitfall 6 | Falsifier must be present during the hypothesis test |
| FPS counter built in Phase 0 | Pitfall 6 | Needed for Phase 2 baseline before fog exists |
| mapsforge_flutter: REJECTED | ARCHITECTURE + STACK | LGPL-3.0; GOSL-blocked |
| flutter_gpu / vector_map_tiles 10.x: REJECTED for POC | ARCHITECTURE + STACK | Requires Flutter master channel |

### Deferred (to roadmap/phase research or later)

| Decision | Deferred To | Why |
|----------|-------------|-----|
| flutter_map Path B (8.3.0 + v_m_t 9-beta) | Post-POC if Path A FPS inadequate | Re-evaluate only if Phase 2 walk shows <40 fps and label-thinning does not help |
| Worker-isolate SDF rebuild | MirkFall migration | UI isolate sufficient for POC at <100 discs; POC instruments timing for migration |
| MapView domain abstraction | MirkFall migration | Abstraction is a migration concern |
| MirkFall basemap theme port | MirkFall migration | Orthogonal to the hypothesis |
| iOS OpenGL ES fallback compatibility | Phase 5 or migration | Requires second device or explicit test build; requirements phase to flag |
| Comparative FPS vs. parent project | Phase 5 explicit task | One walk with FPS counter added to MirkFall; required before POC verdict |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Every package verified via pub.dev and source repos. Version conflict fully resolved by constraint solver. All licenses GOSL-clean. All telemetry absent confirmed. |
| Features | HIGH | Categorisation grounded in PROJECT.md and parent codebase. Asset-loading mechanics confirmed via upstream issue #44. Geolocator getLastKnownPosition flakiness confirmed via issue tracker. |
| Architecture | HIGH | Same-Canvas guarantee proven from flutter_map source code (MapInteractiveViewer + MapInheritedModel). Anti-patterns are specific to BUG-014 failure modes. FogLayer sketch is structurally sound. |
| Pitfalls | HIGH for shader/sideload/iOS-specific (direct parent-project evidence); MEDIUM for vector_map_tiles perf (qualitative issue tracker, no measured numbers); LOW for share_plus Mail on sideloaded build |

**Overall confidence: HIGH for "the architecture is sound and buildable." MEDIUM for "it will pass the FPS gate" -- that is literally the hypothesis under test.**

### Gaps to Address

- **Vector tile FPS on iOS at zoom 13-15:** No published numbers. Phase 2 walk is the measurement. If FPS < 40 no-fog: block Phase 3 and evaluate mitigations.
- **share_plus + Mail byte-integrity on sideloaded build:** Phase 0 smoke test (50 MB synthetic log, verify receipt byte count). Must pass before Phase 1.
- **iPhone model (ProMotion vs. non-ProMotion):** Must be recorded in PROJECT.md. Affects FPS criterion interpretation.
- **SideStore "Disable App Limit" toggle and pairing-file status on the developer iPhone:** Must be confirmed before Phase 0 UAT. Document in README.

---

## Sources

### Primary (HIGH confidence)

- `C:\claude_checkouts\mirk-poc-debug\.planning\PROJECT.md` -- project context, scope, constraints
- `C:\claude_checkouts\GOSL-MirkFall\assets\shaders\atmospheric_fog.frag` -- 41-uniform + 1-sampler shader; BUG-014 slot-reorder fix; OpenGLES Y-flip guard
- `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\mirk\wisp\wisp_particle_system.dart` -- pixel-space positions confirmed (Pitfall 1 source)
- `C:\claude_checkouts\GOSL-MirkFall\docs\phase09-bug-tracking\BUG-014-sdf-rect-offset-axes.md` -- six failed iterations; platform-view lag root cause
- `github.com/fleaflet/flutter_map` (MapInteractiveViewer, MapInheritedModel, MobileLayerTransformer) -- same-Canvas guarantee proof from source
- `github.com/josxha/flutter_map_plugins/issues/44` -- asset:/// URI not supported by vector_map_tiles_pmtiles ("not planned")
- `github.com/flutter/flutter/blob/stable/CHANGELOG.md` -- Flutter 3.41.8 confirmed as latest stable
- geolocator issues #962, #1037 -- `getLastKnownPosition` unreliability on iOS confirmed
- All pub.dev package pages -- licenses, publishers, versions, telemetry inspection

### Secondary (MEDIUM confidence)

- `greensopinion/flutter-vector-map-tiles issues #10, #120` -- label-collision UI-isolate perf reports
- `github.com/flutter/flutter/issues/179268` -- Vulkan to OpenGLES gradient bug on Android
- `github.com/flutter/flutter/issues/155805, #115044, #151355` -- Impeller transpiler edge cases

### Tertiary (LOW confidence -- flagged for Phase 0 validation)

- share_plus on free-Apple-ID sideloaded build -- no documented behaviour for Mail attachment byte-integrity
- SideStore "Disable App Limit" toggle (single-source community doc; verify before relying on it)

---

*Research completed: 2026-04-30*
*Ready for roadmap: yes*
