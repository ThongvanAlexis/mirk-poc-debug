# Requirements: MirkFall Same-Canvas POC

**Defined:** 2026-04-30
**Core Value:** The fog-of-war stays perfectly locked to the map during pan, zoom, and combined gestures on a sideloaded iOS build.

Requirements are user-centric, testable, atomic. The POC's only question is the architectural hypothesis (single Canvas → no fog/map lag) — every requirement either proves that hypothesis or makes the iOS UAT walks investigable from a Windows dev box.

## v1 Requirements

### Bootstrap

- [ ] **BOOT-01**: Flutter project initialised with SDK pin `3.41.8` and Dart `3.11.x`; `pubspec.yaml` strictly version-pinned (no `^`); `pubspec.lock` committed
- [ ] **BOOT-02**: Every `.dart` file in `lib/` and `test/` starts with the GOSL v1.0 copyright header (`// Copyright (c) 2026 THONGVAN Alexis` / `// Licensed under the Good Old Software License v1.0` / `// See LICENSE file for details`)
- [ ] **BOOT-03**: `LICENSE` file at repo root contains the GOSL v1.0 text
- [ ] **BOOT-04**: `analysis_options.yaml` enforces `strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`; uses `flutter_lints 6.0.0`
- [ ] **BOOT-05**: `dart format --line-length 160 --set-exit-if-changed .` passes
- [ ] **BOOT-06**: `flutter analyze` passes with no warnings
- [ ] **BOOT-07**: `Fra_Melun.pmtile` (4 MB MVT vector) bundled as a Flutter asset under `assets/maps/`
- [ ] **BOOT-08**: Battle-tested files ported verbatim from MirkFall: `atmospheric_fog.frag`, `revealed_sdf_builder.dart`, `reveal_disc.dart`, `mirk_viewport_bbox.dart`, `tile_cell_iteration.dart`, `mirk_projection.dart`, `fog_shader_uniforms.dart`, `animation_helpers.dart`, plus relevant `kMirkFog*` / `kMetersPerDegreeLat` / `kEarthRadiusMeters` constants

### Dependency Audit

- [ ] **AUDIT-01**: `DEPENDENCIES.md` at repo root lists every direct dependency with: name, pinned version, license, telemetry audit (auto network egress: yes/no, what it does), transitive license summary, maintenance signal (last release, contributors), platform compatibility (iOS + Android), audit date
- [ ] **AUDIT-02**: CI fails the build if any direct or transitive dependency carries a non-acceptable license (allow-list: MIT, BSD-2/3, Apache 2.0, ISC, zlib, CC0, Unlicense)
- [ ] **AUDIT-03**: Zero packages perform automatic network egress on app launch (no analytics, no crash reporting, no attribution SDKs, no remote config, no update checks)

### CI

- [ ] **CI-01**: GitHub Actions workflow on every push to `main` runs three jobs: lint (ubuntu-latest), build-android (ubuntu-latest), build-ios (macos-latest)
- [ ] **CI-02**: Lint job runs `flutter analyze`, `dart format --line-length 160 --set-exit-if-changed`, `flutter test`
- [ ] **CI-03**: Build-android job produces a debug APK downloadable as a workflow artifact
- [ ] **CI-04**: Build-ios job produces an unsigned IPA (sideloadable via SideStore) downloadable as a workflow artifact
- [ ] **CI-05**: Both APK and IPA artifacts are visible from the GitHub Actions run page on every push

### Permissions

- [ ] **AUTH-01**: On launch, the app shows a permission rationale screen explaining why `locationWhenInUse` is required for the fog-of-war
- [ ] **AUTH-02**: When the user accepts the rationale, the app requests `Permission.locationWhenInUse` via `permission_handler`
- [ ] **AUTH-03**: On grant, the app navigates to the map screen via `context.go('/map')` (full pile reset — there's nowhere to go back to)
- [ ] **AUTH-04**: On deny, the app shows a denied screen with a button that opens system settings via `permission_handler.openAppSettings()`
- [ ] **AUTH-05**: `ios/Runner/Info.plist` contains `NSLocationWhenInUseUsageDescription` with a non-empty rationale string; no `NSLocationAlwaysAndWhenInUseUsageDescription` (out of scope)
- [ ] **AUTH-06**: `ios/Runner/Info.plist` contains `ITSAppUsesNonExemptEncryption=false`

### Map

- [ ] **MAP-01**: On first launch (after permission grant), `Fra_Melun.pmtile` is copied from `rootBundle` to `<getApplicationSupportDirectory()>/maps/Fra_Melun.pmtile` exactly once; subsequent launches detect the existing file and skip the copy
- [ ] **MAP-02**: The map screen renders the bundled PMTiles via `flutter_map 7.0.2` + `vector_map_tiles 8.0.0` + `vector_map_tiles_pmtiles 1.5.0`, with the renderer's default style
- [ ] **MAP-03**: Initial camera centred on Melun (lat `48.5397`, lon `2.6553`, zoom `13`)
- [ ] **MAP-04**: User can pan the map with one-finger drag
- [ ] **MAP-05**: User can zoom the map with pinch gesture
- [ ] **MAP-06**: User can perform combined pan+zoom (pinch + drag simultaneously) and the map responds smoothly

### Location & Recenter

- [ ] **LOC-01**: After permission grant, the app subscribes to `Geolocator.getPositionStream` with a sensible accuracy/distance filter
- [ ] **LOC-02**: A blue dot (radius 7 px, fill `#2b7cd6`, white stroke 2 px) is rendered at the user's current position on the map and updates on each GPS fix
- [ ] **LOC-03**: The most-recent GPS fix is cached in memory as `_lastFix`; the app does NOT call `Geolocator.getLastKnownPosition()` (unreliable on iOS — known plugin issue)
- [ ] **LOC-04**: A floating action button on the map screen animates the camera to `_lastFix` at zoom 15
- [ ] **LOC-05**: When `_lastFix` is null (no fix yet received), the recenter button is disabled (or shows a spinner)

### Fog of War

- [ ] **FOG-01**: On each GPS fix, a `RevealDisc(lat, lon, 25 m)` is added to an in-memory disc list (no database)
- [ ] **FOG-02**: A 256×256 R-channel midpoint-128 SDF (`ui.Image`) is built from the disc list via `RevealedSdfBuilder.buildFromDiscs`, with distance computed in **metres**, not pixels (so circles stay circular at all latitudes)
- [ ] **FOG-03**: The SDF is rebuilt when the disc list changes; the rebuild runs on the UI isolate (acceptable for `< 100` discs at `< 16 ms`); a debug log records each rebuild's duration
- [ ] **FOG-04**: A `FogLayer` widget is registered as a `flutter_map` custom layer that paints into the same Canvas as the tile layer
- [ ] **FOG-05**: Inside `FogLayer.paint()`, the 41 float uniforms + 1 sampler of `atmospheric_fog.frag` are populated; identity sdfRect (`0, 0, 1, 1`) is passed because the SDF and the viewport share the same coordinate space
- [ ] **FOG-06**: The clip path (world rect minus disc circles, in screen coordinates) is computed and applied via `canvas.clipPath`; the shader is then drawn via `canvas.drawRect(viewport, Paint()..shader = fogShader)`
- [ ] **FOG-07**: All inputs to the per-frame fog draw — SDF rect, clip path, viewport size, shader uniforms — derive from the **same `MapCamera` snapshot**, captured atomically at the start of paint (prevents BUG-014's combined-zoom-pan failure mode from re-emerging in the new pipeline)
- [ ] **FOG-08**: A frame-delta self-debug probe records, per frame: timestamp of the latest map camera update, timestamp of the fog uniform population, the delta between them; rolling median, p95, and max are exposed via the logger and an on-screen overlay

### Wisp Particles

- [ ] **WISP-01**: `WispParticleSystem` is ported from MirkFall with particle positions refactored from `Offset` (screen pixels) to `LatLng` (world coordinates); positions are projected to screen at paint time using the same `MapCamera` snapshot as the fog
- [ ] **WISP-02**: Wisps are spawned along disc perimeters as new discs appear; max 200 wisps active simultaneously; 8 m spacing; 2.5 s life; 18 px/s initial speed; birth radius 6 px → death radius 22 px; peak alpha 0.35
- [ ] **WISP-03**: A 5 s warm-up phase suppresses wisp spawning on app open
- [ ] **WISP-04**: Wisps render in the same Canvas as the fog and the tile layer (same paint pass, same `MapCamera` snapshot)

### Logger

- [ ] **LOG-01**: A logger configured via the `logging` package writes to `<getApplicationDocumentsDirectory()>/logs/yyyymmdd_hhmmss_logs.txt`, one file per app session
- [ ] **LOG-02**: Log level for the POC is `Level.ALL` (verbose); each log line is timestamped to millisecond precision
- [ ] **LOG-03**: The logger is initialised before any other module that might log (so initialisation failures are captured)
- [ ] **LOG-04**: A button in the app (visible from any screen — likely an app-bar action) opens the system share sheet via `share_plus 12.0.2`, attaching the current session's log file
- [ ] **LOG-05**: The share sheet works on a SideStore-sideloaded iOS build with the iOS Mail app as the share target (Phase 1 smoke test confirms this)

### Performance Instrumentation

- [ ] **PERF-01**: An on-screen FPS counter overlay is rendered on the map screen (toggleable via a dev menu or always-on for the POC); shows current FPS rolling-averaged over 1 s
- [ ] **PERF-02**: At Phase 2 UAT walk on iPhone 17 Pro: pan-FPS without fog ≥ 40 (gate before Phase 3 fog work begins)
- [ ] **PERF-03**: At Phase 3 UAT walk on iPhone 17 Pro: pan-FPS with fog active ≥ 30; idle-fog-animation FPS ≥ 50
- [ ] **PERF-04**: At Phase 3 UAT walk: frame-delta probe (FOG-08) shows median ≤ 16 ms, p95 ≤ 32 ms, max ≤ 48 ms across ≥ 10 combined gestures
- [ ] **PERF-05**: At Phase 3 UAT walk: developer's subjective verdict — no visible fog slip, no white-ellipse artefact during pan/zoom/combined gestures
- [ ] **PERF-06**: Pixel 4a (Adreno 618) UAT walks at Phase 3 and Phase 5: app launches, fog renders, no crash; informational FPS recorded for cross-platform comparison (no hard pass criterion)

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

Empty initially. Filled by the roadmap when phases are derived.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BOOT-01 | TBD | Pending |
| BOOT-02 | TBD | Pending |
| BOOT-03 | TBD | Pending |
| BOOT-04 | TBD | Pending |
| BOOT-05 | TBD | Pending |
| BOOT-06 | TBD | Pending |
| BOOT-07 | TBD | Pending |
| BOOT-08 | TBD | Pending |
| AUDIT-01 | TBD | Pending |
| AUDIT-02 | TBD | Pending |
| AUDIT-03 | TBD | Pending |
| CI-01 | TBD | Pending |
| CI-02 | TBD | Pending |
| CI-03 | TBD | Pending |
| CI-04 | TBD | Pending |
| CI-05 | TBD | Pending |
| AUTH-01 | TBD | Pending |
| AUTH-02 | TBD | Pending |
| AUTH-03 | TBD | Pending |
| AUTH-04 | TBD | Pending |
| AUTH-05 | TBD | Pending |
| AUTH-06 | TBD | Pending |
| MAP-01 | TBD | Pending |
| MAP-02 | TBD | Pending |
| MAP-03 | TBD | Pending |
| MAP-04 | TBD | Pending |
| MAP-05 | TBD | Pending |
| MAP-06 | TBD | Pending |
| LOC-01 | TBD | Pending |
| LOC-02 | TBD | Pending |
| LOC-03 | TBD | Pending |
| LOC-04 | TBD | Pending |
| LOC-05 | TBD | Pending |
| FOG-01 | TBD | Pending |
| FOG-02 | TBD | Pending |
| FOG-03 | TBD | Pending |
| FOG-04 | TBD | Pending |
| FOG-05 | TBD | Pending |
| FOG-06 | TBD | Pending |
| FOG-07 | TBD | Pending |
| FOG-08 | TBD | Pending |
| WISP-01 | TBD | Pending |
| WISP-02 | TBD | Pending |
| WISP-03 | TBD | Pending |
| WISP-04 | TBD | Pending |
| LOG-01 | TBD | Pending |
| LOG-02 | TBD | Pending |
| LOG-03 | TBD | Pending |
| LOG-04 | TBD | Pending |
| LOG-05 | TBD | Pending |
| PERF-01 | TBD | Pending |
| PERF-02 | TBD | Pending |
| PERF-03 | TBD | Pending |
| PERF-04 | TBD | Pending |
| PERF-05 | TBD | Pending |
| PERF-06 | TBD | Pending |

**Coverage:**
- v1 requirements: 56 total
- Mapped to phases: 0 (filled by roadmap)
- Unmapped: 56 ⚠️

---
*Requirements defined: 2026-04-30*
*Last updated: 2026-04-30 after initial definition*
