# MirkFall Same-Canvas POC

## What This Is

A standalone Flutter proof-of-concept that tests whether rendering the MirkFall
map, fog-of-war shader, and wisp particles in a single unified Flutter rendering
pipeline eliminates the camera-tracking lag identified by BUG-014 in the parent
project. If the POC succeeds on iOS, the validated code is ported back into
MirkFall as a `maplibre_gl` replacement.

## Core Value

The fog-of-war stays perfectly locked to the map during pan, zoom, and combined
gestures on a sideloaded iOS build. Everything else exists only to make that
question answerable.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Permission gate that requests `locationWhenInUse` and routes to the map
      screen on grant, or to a denied screen with a system-settings link on deny
- [ ] Single map screen displaying the bundled `Fra_Melun.pmtile` centred on
      Melun (~lat 48.5397, lon 2.6553, zoom 13)
- [ ] Pan, zoom, and combined pan+zoom gestures work on the map
- [ ] Blue dot showing the user's GPS position, updated on each fix
- [ ] Recenter floating action button that animates the camera to the user's
      last known position at zoom 15
- [ ] Atmospheric fog-of-war shader rendered in the **same rendering pipeline**
      as the map tiles (the architectural hypothesis under test)
- [ ] Reveal discs (25 m radius) created on each GPS fix; SDF rebuilt when the
      disc list changes; SDF drives the fog shader
- [ ] Wisp particles rendered along disc perimeters in the same pipeline as the
      fog
- [ ] Logger writing verbose logs to
      `<app_documents_dir>/logs/yyyymmdd_hhmmss_logs.txt`
- [ ] Email-share button to share the current log file via `share_plus` (the
      only realistic iOS-walk debugging channel for a developer on Windows)
- [ ] CI builds an unsigned IPA (sideloadable via SideStore) on `macos-latest`
      and a debug APK on `ubuntu-latest`; both artifacts downloadable from the
      run page on every push
- [ ] All `.dart` files carry the GOSL v1.0 copyright header
- [ ] Every dependency audited and documented in `DEPENDENCIES.md`

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Custom MirkFall basemap styling (replicating `#f5f1e8` / `#a6c9df` / etc. via
  a Theme object) — default renderer style is sufficient to test fog tracking
- Multiple mirk styles — atmospheric only
- Database / Drift / migrations — POC stores discs in memory
- Session management, offline compaction, country switching, mirk download
  infrastructure — out of scope of the hypothesis
- Burger menu, settings screen, live tuner sheet — convenience UI; defer
- `MapView` domain abstraction — talk to the chosen renderer directly; the
  abstraction layer is a migration concern, not a POC concern
- `MirkInitialRevealFade` — visual polish; not on the hypothesis path
- `Permission.locationAlways` and notification permissions — POC only needs
  `locationWhenInUse`
- Telemetry, analytics, crash reporting — forbidden by GOSL v1.0 in any case
- Anything that doesn't either (a) prove the same-Canvas hypothesis or
  (b) make iOS-walk bugs investigable from Windows

## Context

- **Parent project**: `C:\claude_checkouts\GOSL-MirkFall` — Flutter app
  currently using `maplibre_gl` for the map and a Flutter `CustomPainter`
  overlay for the fog. The overlay lives in screen space, not map space.
- **BUG-014** (`docs/phase09-bug-tracking/BUG-014-sdf-rect-offset-axes.md` in
  the parent project): six iterations failed or were reverted (shader slot
  reorder, vec4 → scalar uniforms, identity sdfRect, disc-bbox SDF, MapLibre
  image source, Canvas affine transform). The architectural conclusion: a
  Flutter overlay over a native platform-view map renderer cannot track
  gestures in sync, because the two pipelines are physically decoupled
  (1–3 frame lag on viewport bbox queries, amplified by combined zoom+pan).
- **Hypothesis under test (architectural)**: rendering map tiles, fog, and
  wisps in a single unified pipeline eliminates the lag, because every paint
  happens in the same frame.
- **Leading candidate stack** (open — to be confirmed by research):
  `flutter_map` (BSD-3) + `vector_map_tiles` (Apache-2.0) +
  `vector_map_tiles_pmtiles` (MIT) + Flutter `FragmentProgram` running the
  existing `atmospheric_fog.frag`. Vector tile perf has been validated
  previously on the parent app.
- **Open research questions**:
  1. Renderer choice — `flutter_map` vs. `mapsforge_flutter` vs. custom
     MVT-on-Canvas vs. `flutter_gpu` (when stable) vs. anything else
     compatible with the same-Canvas hypothesis
  2. Fog draw method — Flutter `FragmentProgram` is the leading approach
     (already proven on Impeller in MirkFall); re-evaluate if the chosen
     renderer changes the constraints
  3. Wisp integration — how the existing `WispParticleSystem` composites in
     the chosen renderer's paint phase
- **Battle-tested code to port from MirkFall** (verbatim where renderer-
  agnostic, adapted otherwise):
  - `assets/shaders/atmospheric_fog.frag`
  - `lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart`
  - `lib/domain/revealed/reveal_disc.dart`
  - `lib/domain/mirk/mirk_viewport_bbox.dart`
  - `lib/infrastructure/mirk/tile_cell_iteration.dart`
  - `lib/infrastructure/mirk/mirk_projection.dart`
  - `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart`
  - `lib/infrastructure/mirk/animation_helpers.dart`
  - `lib/infrastructure/mirk/wisp/wisp_particle_system.dart`
  - Relevant `kMirkFog*`, `kMetersPerDegreeLat`, `kEarthRadiusMeters`
    constants from `lib/config/constants.dart`
- **Bundled data**: `C:\claude_checkouts\countries-pmtiles\Fra_Melun.pmtile` —
  4 MB MVT vector PMTiles, zoom 0–15, bbox lon `[2.60, 2.72]`,
  lat `[48.50, 48.57]`, centre Melun. Bundled as a Flutter asset.
- **Code-donor mandate**: every component here is expected to port back into
  MirkFall if the POC succeeds. Match MirkFall's structure and naming where
  practical.
- **Dev environment**: developer on Windows 10. Iterates on Android (Pixel 4a)
  and Windows desktop. iOS bugs investigated by sideloading the latest CI IPA
  via SideStore, walking, and reading the shared log file. No Mac available.

## Constraints

- **License**: GOSL v1.0 — no GPL / LGPL / AGPL dependencies; no telemetry; no
  analytics SDKs. Acceptable: MIT, BSD (2/3-clause), Apache 2.0, Unlicense,
  CC0, ISC, zlib. Audit every dependency in `DEPENDENCIES.md` (license,
  telemetry inspection, transitive deps, maintenance, platform compatibility).
- **Telemetry**: zero automatic network egress from any dependency. Logs are
  local-only; sharing is user-initiated via `share_plus`.
- **Code style**: strict Dart analysis (`strict-casts`, `strict-inference`,
  `strict-raw-types`); `dart format --line-length 160`; type hints everywhere;
  strict null safety (no `!` without a prior null check).
- **File header**: every `.dart` file starts with:
  ```
  // Copyright (c) 2026 THONGVAN Alexis
  // Licensed under the Good Old Software License v1.0
  // See LICENSE file for details
  ```
- **Pinned versions**: every dependency in `pubspec.yaml` strictly pinned
  (e.g. `http: 1.2.0`, never `^1.2.0`). `pubspec.lock` committed.
- **Target platforms**:
  - **iOS (primary)**: sideloaded via SideStore. All UAT walks happen on
    iPhone. No Apple Developer account, no TestFlight, no Mac.
  - **Android (secondary)**: debug APK on Pixel 4a for fast iteration and
    cross-platform sanity check.
- **CI required**: every push builds an unsigned IPA on `macos-latest` and a
  debug APK on `ubuntu-latest`; both artifacts must be downloadable from the
  GitHub Actions run page.
- **Performance target**: 30+ fps on iOS during pan/zoom gestures with fog
  active; 50+ fps when the map is idle and only the fog animates. Soft target
  on Pixel 4a as well.
- **UAT gate**: subjective iOS walk + the developer's verbal "approved" after
  each phase before moving on.

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Build a separate POC repo instead of branching MirkFall | Green-field lets us discard the wrong renderer cleanly without churning MirkFall's 1045 tests; outcome flows back as a port if the hypothesis holds | — Pending |
| Bundle `Fra_Melun.pmtile` (4 MB MVT vector) as the only basemap | Developer is in Melun; one small bundled file removes network/distribution complexity; vector format preserves the production restyling capability the migration must not lose | — Pending |
| Skip MirkFall's custom basemap styling for the POC | Re-creating the `Theme` object isn't on the critical path of the same-Canvas hypothesis; default renderer style is sufficient to test fog tracking | — Pending |
| iOS-primary, Windows dev, no Mac | Mirrors MirkFall's sideload-via-SideStore loop; CI builds the unsigned IPA so the developer never needs a Mac | — Pending |
| UAT gate after every phase | iOS walks are the only honest signal for fog tracking; subjective walk + verbal approval beats per-phase FPS instrumentation overhead | — Pending |
| In-app logger + email-share button | The developer can't attach Xcode to the device from Windows; sharing the log file is the only realistic feedback channel during iOS UAT | — Pending |
| Renderer choice deferred to research | The architectural hypothesis (same-Canvas pipeline) is renderer-independent; the research phase compares `flutter_map`, `mapsforge_flutter`, custom MVT-on-Canvas, `flutter_gpu`, and other candidates before locking | — Pending |
| Fog draw method deferred to research | Flutter `FragmentProgram` running the existing 436-line shader is the leading approach (already proven on Impeller); research re-evaluates if the chosen renderer changes the constraints | — Pending |

---
*Last updated: 2026-04-30 after initialization*
