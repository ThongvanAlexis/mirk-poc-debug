# Architecture Research

**Domain:** Pure-Flutter same-Canvas fog-of-war map POC (iOS-primary, side-loaded)
**Researched:** 2026-04-30
**Confidence:** HIGH for renderer choice (flutter_map), MEDIUM for some downstream details (wisp integration cost on iOS-Metal under sustained gestures, exact Pixel 4a OpenGL ES fallback FPS)

---

## TL;DR — Recommendation

**Use `flutter_map` 8.x + `vector_map_tiles` 8.x + `vector_map_tiles_pmtiles` 1.5 + Flutter `FragmentProgram` running the existing `atmospheric_fog.frag` unchanged. Confidence: HIGH.**

This is the only candidate that:

1. **Structurally** prevents BUG-014's six failure modes (one Flutter widget tree, one builder pass per frame, one Canvas, one paint phase — proven by the `flutter_map` source code below).
2. **Runs the 436-line `atmospheric_fog.frag` unchanged** — same `FragmentProgram` API, same Impeller SPIR-V→MSL/SPIR-V transpiler path, same `IMPELLER_TARGET_OPENGLES` Y-flip guard already in the shader, same scalar-uniform layout that survived BUG-014 iteration 2.
3. **Loads `Fra_Melun.pmtile`** through a published, MIT-licensed adapter (`vector_map_tiles_pmtiles`) the user has already validated in another codebase.
4. **Is GOSL v1.0 compatible** — every dependency in the chain is BSD-3 / Apache-2.0 / MIT / BSD-2.
5. **Has zero telemetry** — pure rendering libraries, no analytics SDKs in any transitive dep.
6. **Is buildable from Windows** through the existing `macos-latest` GitHub Actions IPA path (no native Swift/Kotlin work required).

What would change my mind: see the **Counterfactuals** section.

---

## The same-pipeline guarantee — proof from source

Direct evidence from `lib/src/map/widget.dart` on `master`
([fleaflet/flutter_map](https://github.com/fleaflet/flutter_map/blob/master/lib/src/map/widget.dart)):

```dart
@override
Widget build(BuildContext context) {
  super.build(context);
  final widgets = ClipRect(
    child: Stack(
      children: <Widget>[
        Positioned.fill(child: ColoredBox(color: widget.options.backgroundColor)),
        ...widget.children,        // ← TileLayer + custom fog layer + markers all here
      ],
    ),
  );
  return RepaintBoundary(
    child: LayoutBuilder(
      builder: (context, constraints) {
        return MapInteractiveViewer(
          controller: _mapController,
          builder: (context, options, camera) {     // ← rebuilds on each gesture frame
            return MapInheritedModel(
              camera: camera, ...
              child: widgets,                       // ← all layers see THIS camera
            );
          },
        );
      },
    ),
  );
}
```

And from `lib/src/layer/shared/mobile_layer_transformer.dart`:

```dart
@override
Widget build(BuildContext context) {
  final camera = MapCamera.of(context);            // ← reads same camera object
  return OverflowBox(
    minWidth: camera.size.width, ...
    child: Transform.rotate(angle: camera.rotationRad, child: child),
  );
}
```

What this means concretely:

- `FlutterMap` is a `StatefulWidget`. `MapInteractiveViewer` calls a builder
  with the **current camera** in a single build pass. The builder constructs
  `MapInheritedModel` containing the camera, wrapping the entire `Stack` of
  layer children.
- All layers — `TileLayer` (vector tiles via `vector_map_tiles`), our custom
  `FogLayer`, our `BlueDotLayer` — read `MapCamera.of(context)` from the
  **same `InheritedModel`**, in the **same widget tree build**, in the **same
  frame**.
- They are then painted into the **same parent `RepaintBoundary`**'s Canvas
  via the standard widget RenderObject pipeline.
- There is no platform view, no native UIView/SurfaceView intermediate, no
  separate render thread, no platform-channel viewport bbox query.

Compare this to `maplibre_gl`'s architecture (BUG-014):

| Aspect | maplibre_gl (current MirkFall) | flutter_map (proposed POC) |
|--------|--------------------------------|----------------------------|
| Map renderer | Native `UIView` / `SurfaceView` (Metal/OpenGL) | Flutter `RenderObject` (Canvas) |
| Fog renderer | Flutter `CustomPaint` overlay | Flutter `CustomPaint` layer |
| Camera transport | Platform channel @ ~20 Hz | `MapInheritedModel` per build |
| Frame coupling | **Decoupled** — overlay always 1–3 frames behind | **Coupled** — same `build()` call |
| BUG-014 cause | Two physical pipelines | N/A — one pipeline |

Sources:
- [`fleaflet/flutter_map`/lib/src/map/widget.dart](https://github.com/fleaflet/flutter_map/blob/master/lib/src/map/widget.dart)
- [`fleaflet/flutter_map`/lib/src/map/inherited_model.dart](https://github.com/fleaflet/flutter_map/blob/master/lib/src/map/inherited_model.dart)
- [`fleaflet/flutter_map`/lib/src/layer/shared/mobile_layer_transformer.dart](https://github.com/fleaflet/flutter_map/blob/master/lib/src/layer/shared/mobile_layer_transformer.dart)

Confidence: **HIGH** — first-party source code, current `master`.

---

## Candidate evaluation

For each candidate, the question is the same:

> Does this architecture *structurally* prevent the screen-space-overlay vs
> native-renderer mismatch that caused BUG-014 — without sacrificing the
> 436-line atmospheric shader?

### Candidate 1 — `flutter_map` + `vector_map_tiles` + `vector_map_tiles_pmtiles` + `FragmentProgram` (RECOMMENDED)

| Dimension | Verdict |
|---|---|
| **Same-pipeline guarantee** | YES — structurally. All layers in one `Stack`, one `MapInheritedModel.builder`, one Canvas, one frame. Proof above. |
| **Visual fidelity (run `atmospheric_fog.frag` unchanged)** | YES — `FragmentProgram` is the standard Flutter shader API; the existing shader was authored against this API and is known to work on Impeller-Metal in MirkFall. The `IMPELLER_TARGET_OPENGLES` guard is already inside the .frag. |
| **PMTiles support for `Fra_Melun.pmtile`** | YES — `vector_map_tiles_pmtiles` 1.5 (MIT) wraps the BSD-2 `pmtiles` 2.0 package. User has independently validated `vector_map_tiles + Fra_Melun.pmtile` perf. |
| **iOS Impeller compatibility** | HIGH — `FragmentProgram` is production-ready on Impeller as of Flutter 3.27 (early 2025). Existing shader's scalar-uniform layout (post BUG-014 iteration 2) is the documented best practice. |
| **Android Impeller / Pixel 4a (Adreno 618)** | MEDIUM-HIGH — Pixel 4a falls back to OpenGL ES backend; the shader's `#ifdef IMPELLER_TARGET_OPENGLES` Y-flip guard already accommodates this. Flutter [issue #179268](https://github.com/flutter/flutter/issues/179268) shows occasional gradient bugs on the OpenGL ES fallback path; verify in Phase 1 walk. |
| **Performance (vector tiles)** | KNOWN-GOOD per user validation. Public reports of `vector_map_tiles` jank on low-end devices exist ([greensopinion/flutter-vector-map-tiles#10](https://github.com/greensopinion/flutter-vector-map-tiles/issues/10)) but bundled offline tiles + small Melun bbox + zoom 0–15 cap is the favourable case. |
| **License (GOSL-compatible?)** | YES — `flutter_map` BSD-3, `vector_map_tiles` Apache-2.0, `vector_map_tiles_pmtiles` MIT, `pmtiles` BSD-2, `vector_tile_renderer` Apache-2.0. None copyleft. |
| **Telemetry** | None — these are pure rendering libraries with no analytics SDK transitives. Verify via `flutter pub deps` audit in Phase 0. |
| **Maintenance pulse** | `flutter_map` 8.3.0 published ~16 days ago (high activity). `vector_map_tiles` 8.0.0 stable, 20 months old (mature, not abandoned — same author shipping 10.0.0-beta on flutter_gpu now). `vector_map_tiles_pmtiles` 1.5.0 ~18 months old. |
| **Code-donor reusability for MirkFall** | HIGH — every donor file (shader, SDF builder, mirk_projection, wisp system, constants) is renderer-agnostic dart code. The integration glue (FogLayer widget) is the only renderer-specific shim and is small. Migration replaces `MapLibreMap` widget with `FlutterMap` widget. |
| **Effort to first iOS walk** | ~3–5 days. Most of the donor code is verbatim port; the new code is the `FogLayer` widget glue. |
| **Most likely failure mode** | Vector tile FPS on iOS during sustained pinch-zoom dropping below 30. Mitigation: aggressive tile pre-warming on app open, and the user's prior validation makes this unlikely. |

**Verdict: SELECT.**

### Candidate 2 — `mapsforge_flutter`

| Dimension | Verdict |
|---|---|
| **License** | **LGPL-3.0** — BLOCKED by GOSL v1.0. Project's `CLAUDE.md` forbids LGPL with linking implications; LGPL-3.0 obligates source disclosure for the entire combined work in the typical mobile-app static-link context. |

**Verdict: REJECTED on license alone.** Even setting the license aside: it's a `.map` (mapsforge) format renderer, not PMTiles. Conversion would be invasive and re-introduce the donor-mismatch problem. No further analysis needed.

Sources: [pub.dev/packages/mapsforge_flutter](https://pub.dev/packages/mapsforge_flutter).

### Candidate 3 — Custom MVT-on-Canvas (roll our own)

| Dimension | Verdict |
|---|---|
| **Same-pipeline guarantee** | YES (we control the paint phase). |
| **Visual fidelity** | YES (FragmentProgram works in any CustomPainter). |
| **PMTiles support** | We'd use `pmtiles` package directly + write our own MVT decoder→Canvas glue. |
| **Effort** | ~4–8 weeks. MVT spec is non-trivial: protobuf parsing, layer ordering, line/polygon/point primitive translation, label collision, level-of-detail, tile request scheduling, caching, theme/style application. `vector_tile_renderer` (Apache-2.0) already exists for exactly this purpose and is what `vector_map_tiles` uses internally — re-implementing it from scratch is reinventing a wheel that's already free. |
| **Maintenance burden post-POC** | HIGH — every Mapbox style spec update, every PMTiles v3.x revision, every label-rendering edge case becomes our problem. |
| **Code-donor value to MirkFall** | LOW for the renderer (would carry the whole maintenance burden into MirkFall too); HIGH for donor files (same as Candidate 1). |

**Verdict: REJECTED.** The dependency cost of `vector_map_tiles` is well within GOSL bounds and the user has already validated its performance. Custom MVT renderer is gratuitous when a tested Apache-2.0 implementation exists. Could be revisited *after* the POC succeeds, only if `vector_map_tiles` becomes a future maintenance concern — but that's a migration, not a POC consideration.

### Candidate 4 — `flutter_gpu`

| Dimension | Verdict |
|---|---|
| **Same-pipeline guarantee** | YES (Flutter-internal). |
| **Visual fidelity** | YES, but the existing shader is a `FragmentProgram` and would need to be re-authored against the `flutter_gpu` API. The shader is 436 lines of carefully tuned visual product — re-authoring is non-zero risk and re-introduces hand-tuned float-uniform layout questions BUG-014 already resolved. |
| **API stability (2026-04)** | **PREVIEW / NOT PRODUCTION-READY.** Per Flutter docs and engine repo: requires master channel, prefixed symbols `InternalFlutterGpu` are unstable, `does not guarantee API stability`. Documented this way as recently as the [Flutter engine `Flutter-GPU.md`](https://github.com/flutter/engine/blob/main/docs/impeller/Flutter-GPU.md) on `main`. |
| **Cross-platform** | Yes (built on Impeller's Metal/Vulkan/GLES backends), but each backend's stability for unusual code paths is preview-quality. |
| **Compatibility with sideload-via-SideStore + macos-latest CI** | Works in principle; risk is the master channel breaking the build between commits. |

**Verdict: REJECTED for the POC.** Building the architectural hypothesis test on a preview API is the wrong leverage. The hypothesis ("same Canvas eliminates lag") is renderer-internal, not API-internal — `FragmentProgram` already proves the hypothesis on stable Flutter. `flutter_gpu` is a future migration option once it stabilises (already being pursued by `vector_map_tiles` 10.0.0-beta on its own track). Re-evaluate when `flutter_gpu` reaches stable channel, **not** before.

### Candidate 5 — MapLibre native + custom GL/Metal layer (BUG-014 Option C)

| Dimension | Verdict |
|---|---|
| **Same-pipeline guarantee** | YES (the shader runs in MapLibre's own GL/Metal context, native to the map). |
| **Visual fidelity** | The shader would need to be **manually ported** to: MSL (Metal/iOS), GLSL ES (Android OpenGL fallback), Vulkan-GLSL (Android modern), and tested on each. Maintaining three ports of a 436-line ALU-budgeted shader is a long-term liability. |
| **`flutter-maplibre-gl` plugin support** | Per [maplibre/flutter-maplibre-gl README](https://github.com/maplibre/flutter-maplibre-gl): "only a subset of the native SDK APIs are currently exposed". `addCustomLayer` is not exposed via Dart. We would have to fork the plugin and write platform-channel glue + native Swift/Objective-C + Kotlin/Java code. |
| **MapLibre Native cross-platform custom drawable layer** | Per [MapLibre September 2025 newsletter](https://maplibre.org/news/2025-10-04-maplibre-newsletter-september-2025/): "currently working on extending Custom Drawable Layer support" — actively in development, not shipped, not exposed via Flutter plugin. |
| **Buildability from Windows** | NO — without a Mac to write/debug the iOS Metal native shim, this requires either (a) acquiring a Mac, or (b) blind-flying changes through `macos-latest` CI with each iOS UAT walk costing a full CI cycle. Punishingly slow. |
| **Effort to first iOS walk** | 2–4 weeks minimum. Custom-layer Flutter plugin work + 3-platform shader port + sideload validation on each. |
| **Code-donor value to MirkFall** | The most direct port back, BUT only if MirkFall is willing to inherit the same maintenance burden, AND only if that burden is preferable to migrating MirkFall to `flutter_map`. The migration to `flutter_map` is structurally simpler. |

**Verdict: REJECTED for the POC.** This is the route that *might* work but maximises native-shim risk for a developer on Windows with no Mac. The whole POC's reason to exist is that BUG-014 proved a Flutter-side compensation can't fix the platform-view pipeline split — Option C accepts the platform view and bolts the fog inside it. That's coherent, but the iteration loop (Windows → CI → IPA → SideStore → walk → log read → Windows) makes any platform-channel work prohibitively slow.

### Candidate 6 — MapLibre raster image source (BUG-014 Iteration 5)

Already failed; documented for completeness. Three structural problems shipped:

1. **Pixelated boundary** — 512×512 raster covering 3× viewport ⇒ ~170 effective px per screen dim ⇒ blocky watercolour boundary.
2. **Zoom stretching** — geo-pinned image stretches/compresses the noise pattern unnaturally on zoom.
3. **Re-pin snap** — when camera drifts past 50 % padding, image re-pins to new coords ⇒ visible jump.

**Verdict: REJECTED — already proven non-viable.** The fog needs to be rendered per-pixel at screen resolution every frame; raster image sources cannot satisfy that.

### Candidate 7 — Hybrid: flutter_map with a non-Flutter raster source

Hypothetical: e.g., `flutter_map` with raster tiles from a native bitmap source. Would the bitmap source re-introduce the pipeline split?

**No, in principle** — any tile provider that delivers `ui.Image` objects to `flutter_map`'s `TileLayer` is consumed by the *Flutter Canvas* path; the network/native fetch happens off-frame and the result is composited via Flutter widgets. `vector_map_tiles_pmtiles` is exactly this: pmtiles parsing in Dart isolate, `ui.Image` produced, Flutter composites.

**Verdict: This is what Candidate 1 already does.** No separate hybrid worth highlighting beyond what Candidate 1 covers.

---

## Cross-candidate comparison matrix

| | C1 flutter_map + FP | C2 mapsforge_flutter | C3 Custom MVT | C4 flutter_gpu | C5 MapLibre custom layer | C6 MapLibre raster src |
|---|---|---|---|---|---|---|
| Same-pipeline structurally | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ (raster lag-free but visually broken) |
| Run shader unchanged | ✅ | ✅ | ✅ | ❌ (re-author) | ❌ (port to MSL+GLSL+Vulkan) | N/A (no shader path) |
| PMTiles native | ✅ | ❌ (.map) | ✅ (DIY) | N/A (renderer-only) | ✅ | ✅ |
| iOS Impeller | ✅ | ✅ | ✅ | ⚠️ preview | N/A (native renderer) | ✅ |
| Android (Pixel 4a) | ✅ | ✅ | ✅ | ⚠️ preview | ✅ | ✅ |
| GOSL license | ✅ BSD/Apache/MIT | ❌ **LGPL-3.0** | ✅ | ✅ | ✅ | ✅ |
| Zero telemetry | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Buildable from Windows | ✅ | ✅ | ✅ | ⚠️ master channel | ❌ requires Mac for native shim | ✅ |
| Effort to iOS walk | 3–5 d | N/A (rejected) | 4–8 wk | 2–3 wk + risk | 2–4 wk | proven failed |
| Code-donor reusability | High | None | High | Medium | High but complex | None |

Legend: ✅ pass · ⚠️ caveat · ❌ blocker

---

## Recommended Architecture

### System Overview

```
+--------------------------------------------------------------------+
|                       Presentation (Flutter widgets)                |
|  +--------------+  +-----------+  +------------+  +-------------+  |
|  | PermissionGa |  | MapScreen |  | FogLayer   |  | BlueDotLayer|  |
|  | te (Permit-  |  | (FlutterM |  | (CustomPa- |  | (CircleMar- |  |
|  | sionHandler) |  | ap host)  |  | int + Frag |  | ker via     |  |
|  |              |  |           |  | Program)   |  | MarkerLayer)|  |
|  +------+-------+  +-----+-----+  +-----+------+  +------+------+  |
|         |                |              |                |          |
+---------|----------------|--------------|----------------|----------+
          |                |              |                |
          | Riverpod (state mgmt — single system, see notes below)
          |                v              v                v
+--------------------------------------------------------------------+
|                       Application / Domain                          |
|  +-------------------+  +-----------------+  +------------------+  |
|  | LocationStream    |  | RevealDiscRepo  |  | FogShaderUniform |  |
|  | (geolocator wrap) |  | (in-memory list)|  | s (slot layout)  |  |
|  +---------+---------+  +--------+--------+  +---------+--------+  |
|            |                     |                     |            |
+------------|---------------------|---------------------|------------|
             v                     v                     v
+--------------------------------------------------------------------+
|                          Infrastructure                             |
|  +------------------+   +--------------------+  +---------------+  |
|  | RevealedSdfBuild |   | MirkProjection     |  | WispParticle  |  |
|  | er (port from    |   | (lat/lon -> screen,|  | System (port  |  |
|  | MirkFall)        |   | port from MirkFal) |  | from MirkFall)|  |
|  +------------------+   +--------------------+  +---------------+  |
|                                                                     |
|  +--------------------------------------------------------------+  |
|  | TileSource: PmTilesVectorTileProvider.fromSource(            |  |
|  |   'asset:///assets/maps/Fra_Melun.pmtile')                   |  |
|  +--------------------------------------------------------------+  |
+--------------------------------------------------------------------+
             |
             v (rendering)
+--------------------------------------------------------------------+
|                Flutter Render Pipeline (Impeller)                   |
|  RepaintBoundary(                                                   |
|    MapInteractiveViewer(                                            |
|      MapInheritedModel(camera: <current>,                           |
|        Stack([                                                      |
|          ColoredBox (background),                                   |
|          VectorTileLayer (TileLayer wraps it),                      |
|          FogLayer (CustomPaint w/ FragmentShader),  <-- our shim    |
|          WispLayer (CustomPaint additive),          <-- our shim    |
|          BlueDotLayer (MarkerLayer),                                |
|          [floating UI: recenter button, share-logs])                |
|        ]                                                            |
|      )                                                              |
|    )                                                                |
|  )                                                                  |
|                                                                     |
|  -> single SceneBuilder pass -> Impeller -> Metal/Vulkan/GLES        |
+--------------------------------------------------------------------+
```

### Component responsibilities

| Component | Responsibility | Implementation |
|---|---|---|
| `PermissionGate` | Request `locationWhenInUse`, branch to map vs denied screen. | `permission_handler` + GoRouter `context.go('/map')` on grant. |
| `MapScreen` | Host the `FlutterMap` widget tree; assemble layers in correct stacking order. | `StatefulWidget`. Owns `MapController`. |
| `FogLayer` | Compute clip path; paint fog rect with `FragmentShader` keyed on disc-bbox SDF + camera-derived uniforms. | `StatelessWidget` whose `build()` returns a `MobileLayerTransformer` (or a custom widget that reads `MapCamera.of(context)`) wrapping a `CustomPaint` with size = camera viewport. |
| `WispLayer` | Render active wisps with additive blending. | Same pattern as `FogLayer`. Reads from `WispParticleSystem` ticked by an internal `Ticker`. |
| `BlueDotLayer` | Render user position dot on map. | `MarkerLayer` from flutter_map (no custom painting needed). |
| `LocationStream` | Subscribe to `geolocator` position updates; expose `Stream<Position>`. | Riverpod `StreamProvider<Position>`. |
| `RevealDiscRepository` | In-memory list of `RevealDisc`. On each new GPS fix, append a 25-m disc. | Riverpod `Notifier<List<RevealDisc>>`. |
| `RevealedSdfBuilder` | Verbatim port from MirkFall; builds 256×256 `ui.Image` from disc list + viewport. | UI isolate is fine for <100 discs (<16 ms). Promote to worker isolate if profiling shows otherwise. |
| `MirkProjection` | Verbatim port. lat/lon → canvas Offset. | Pure function, no state. |
| `WispParticleSystem` | Verbatim port. Particle integration and additive rendering. | Stateful, owned by `WispLayer`. |
| `FogShaderUniforms` | Verbatim port — slot-numbered uniform layout. | Pure data. |

### `FogLayer` implementation sketch

The single load-bearing piece of new code (everything else is a port). Three methods worth pinning:

```dart
class FogLayer extends StatefulWidget {
  const FogLayer({super.key, required this.discs});
  final List<RevealDisc> discs;
  ...
}

class _FogLayerState extends State<FogLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  ui.FragmentProgram? _program;
  ui.Image? _sdfImage;
  Object? _sdfCacheKey;
  late DateTime _started;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);          // <-- THE same-pipeline anchor
    return MobileLayerTransformer(
      child: CustomPaint(
        size: camera.size,
        painter: _FogPainter(
          program: _program,
          sdfImage: _sdfImage,
          camera: camera,
          discs: widget.discs,
          elapsed: DateTime.now().difference(_started).inMilliseconds / 1000.0,
        ),
      ),
    );
  }
}

class _FogPainter extends CustomPainter {
  // ... fields ...
  @override
  void paint(Canvas canvas, Size size) {
    // 1) build / reuse SDF (rebuild only when disc-list hash OR viewport bbox hash changes)
    // 2) compute clip path: full-screen rect minus disc circles in screen px
    //    via camera.latLngToScreenOffset for each disc center
    // 3) populate FragmentShader uniforms (41 floats + 1 sampler)
    //    - uResolution = size
    //    - uTime = elapsed
    //    - uOffset = (camera.center.lon * 0.05, -camera.center.lat * 0.05)
    //    - uSdfRect* = identity (0, 0, 1, 1) — same pipeline, no remap needed
    //    - sampler uSdf = sdfImage
    // 4) canvas.clipPath(fogPath); canvas.drawRect(Offset.zero & size, paint..shader = fragShader)
    // 5) wisp system rendered immediately after on the same canvas
  }
}
```

This is structurally identical to the BUG-014 Iteration-1 architecture — but **without** the platform-view split that doomed it. The Canvas given to `paint()` is the same Canvas the TileLayer painted into one tick earlier in the same frame.

### Suggested package layout (mirrors MirkFall conventions for portability)

```
lib/
  main.dart                            # bootstrap + runApp() ONLY
  app.dart                             # MaterialApp + router
  router.dart                          # GoRouter routes (/permission, /map, /denied)
  config/
    constants.dart                     # kMirkFog*, kMetersPerDegreeLat, ...
    licence_header.dart                # GOSL v1.0 banner reference
  domain/
    revealed/
      reveal_disc.dart                 # PORT verbatim
    mirk/
      mirk_viewport_bbox.dart          # PORT verbatim
  application/
    permission/
      permission_controller.dart       # Riverpod notifier
    location/
      location_stream_provider.dart    # geolocator wrapper
    revealed/
      reveal_disc_repository.dart      # in-memory disc list
    fog/
      fog_state.dart                   # SDF cache key, current uniforms
  infrastructure/
    mirk/
      sdf/
        revealed_sdf_builder.dart      # PORT verbatim
      mirk_projection.dart             # PORT verbatim
      tile_cell_iteration.dart         # PORT verbatim (clip-path builder)
      animation_helpers.dart           # PORT verbatim
      shader/
        fog_shader_uniforms.dart       # PORT verbatim
      wisp/
        wisp_particle.dart             # PORT verbatim
        wisp_particle_system.dart      # PORT verbatim
    map/
      pmtiles_loader.dart              # PmTilesVectorTileProvider plumbing
      vector_tile_theme.dart           # default theme (custom theming OUT OF SCOPE)
    logging/
      file_logger.dart                 # logging package -> rotating file
  presentation/
    screens/
      permission_screen.dart
      permission_denied_screen.dart
      map_screen.dart                  # FlutterMap host
    widgets/
      fog_layer.dart                   # NEW — the only renderer-specific shim
      wisp_layer.dart                  # NEW
      blue_dot_layer.dart              # MarkerLayer wrapper
      recenter_button.dart
      share_logs_button.dart
  assets/
    shaders/
      atmospheric_fog.frag             # PORT verbatim
    maps/
      Fra_Melun.pmtile                 # 4 MB bundled asset
```

Rationale:

- **`lib/domain/`** — value types only (no Flutter imports beyond `dart:ui`). Pure, easy to test, port back to MirkFall.
- **`lib/application/`** — use cases and state holders (Riverpod). Imports domain, NOT presentation.
- **`lib/infrastructure/`** — concrete adapters: SDF, projection, tile loader, file logger. Imports domain.
- **`lib/presentation/`** — Flutter widgets only. Imports application + infrastructure for types it must render.
- **`assets/`** — shader and PMTiles. Top-level (Flutter convention).

Naming, paths, and folder structure intentionally mirror MirkFall for clean code-donor port-back.

---

## Architectural Patterns

### Pattern 1: Same-Canvas Fog Layer

**What:** Render fog as a child widget of `FlutterMap` that paints into the same Canvas as `TileLayer` in the same frame.

**When to use:** Every time. This is THE pattern the POC exists to validate.

**Trade-offs:**
- Pro: structurally eliminates BUG-014 (per source-code proof above).
- Pro: shader runs unchanged from MirkFall.
- Con: per-frame `CustomPaint` is on the UI isolate; if SDF rebuild ever exceeds 16 ms it blocks the frame. Mitigation: cache SDF on (disc-list-hash + viewport-bbox-hash) and only rebuild on change; SDF rebuild is already <16 ms for 100 discs per the donor file's docstring.

**Example (sketch):**
```dart
FlutterMap(
  options: MapOptions(initialCenter: melun, initialZoom: 13),
  children: [
    VectorTileLayer(theme: defaultTheme, tileProviders: TileProviders({...})),
    const FogLayer(discs: ...),         // <-- our same-Canvas fog
    const WispLayer(),                  // <-- our wisps
    const BlueDotMarkerLayer(),
  ],
)
```

### Pattern 2: SDF Cache Keyed on `(discListHash, viewportBboxHash)`

**What:** The 256² SDF only changes when the union of disc geometry or the viewport changes. Hash both inputs; reuse the `ui.Image` when the hash matches.

**When to use:** Always — the donor file documents this contract.

**Trade-offs:**
- Pro: SDF rebuild stays off the per-frame budget except when the user actually walks (~1× / sec) or the camera bbox changes (debounced).
- Con: ui.Image objects are GPU-resident; cache one-deep and call `dispose()` on the previous when replacing. Otherwise memory walks.

### Pattern 3: Camera-Driven Uniform Pump

**What:** All shader uniforms that depend on camera state (`uOffset`, screen-space disc centres for the clip path) are derived from `MapCamera.of(context)` inside `paint()` — never from a separately-cached "viewport bbox" arriving from a different transport.

**When to use:** Every frame. This is the core of the same-pipeline guarantee.

**Trade-offs:**
- Pro: zero camera-tracking lag because the camera value is the *same object* the TileLayer used in the same frame.
- Con: the shader's `uSdfRect` uniforms must always be identity `(0, 0, 1, 1)`. The disc-bbox SDF approach (BUG-014 Iteration 4) was an attempt to compensate for the platform-view lag — irrelevant here, and re-introducing it would re-create the ellipse-boundary failure mode.

### Pattern 4: One State-Management System

**What:** Choose Riverpod once, document it in a `lib/application/README.md`, never mix.

**When to use:** Day 1.

**Trade-offs:**
- Pro: matches MirkFall's stack (assumed; if MirkFall uses something else, match THAT instead — code-donor mandate trumps Riverpod preference).
- Con: small upfront cost. Riverpod 2.x has compile-time-safe code-gen that's worth the boilerplate.

---

## Data Flow

### From a GPS fix to a fog pixel

```
geolocator                         (platform-channel stream)
   |
   v
Stream<Position>                   (LocationStream — Riverpod)
   |
   v
RevealDiscRepository.add(disc)     (appends RevealDisc(lat, lon, 25m))
   |   notify
   v
FogState (Riverpod)                (depends on disc list + camera)
   |
   v
[on next FlutterMap rebuild via MapInheritedModel]
   |
   v
FogLayer.build(context)
   |
   v
_FogLayerState reads:
  - widget.discs                   (current list)
  - MapCamera.of(context)          (current camera — same as TileLayer)
   |
   v
_FogPainter.paint(canvas, size):
  if (sdfCacheKey changed):
    sdfImage = RevealedSdfBuilder.buildFromDiscs(discs, viewportBbox)
    [256x256 ui.Image, R-channel midpoint-128 SDF]
  fogShader = program.fragmentShader()
  fogShader.setFloat(0, size.width); fogShader.setFloat(1, size.height); ...
  fogShader.setImageSampler(0, sdfImage)
  fogPath = buildViewportFogClipPathFromDiscs(discs, camera, size)   [port]
  canvas.clipPath(fogPath)
  canvas.drawRect(Offset.zero & size, Paint()..shader = fogShader)
   |
   v
WispLayer.paint() (same Canvas, immediately after)
   |
   v
[Flutter Engine -> Impeller -> Metal/Vulkan/GLES] -> screen pixel
```

Every step from `MapCamera.of(context)` down happens in the **same frame** as the `TileLayer.paint()` call that drew the underlying tiles. There is no platform-channel hop. There is no separate native render thread for the map. The Canvas given to `_FogPainter.paint()` is the same Canvas the `TileLayer` painted into.

### State Management

```
+------------------+   subscribe    +-------------------+
|  Riverpod        | <------------- |  presentation     |
|  Providers       |                |  widgets          |
|                  | -------->      |                   |
|  - permission    |   rebuild      |                   |
|  - location      |                |                   |
|  - reveal discs  |                |                   |
|  - fog state     |                |                   |
+------------------+                +-------------------+
       ^                                    |
       |  mutate                            |
       |                                    |
+------------------+                        |
|  application     | <----------------------+
|  controllers     |   user actions
+------------------+
       |
       v
+------------------+
|  infrastructure  |
|  - geolocator    |
|  - file logger   |
|  - pmtiles asset |
|  - SDF builder   |
+------------------+
```

### Concurrency model (isolates)

| Work | Isolate | Rationale |
|---|---|---|
| Widget builds, layer painting | UI (main) isolate | Standard. No way around it. |
| Per-frame fog `CustomPaint`, fragment shader uniform writes, Canvas calls | UI (main) isolate | All Flutter rendering is single-threaded on the UI isolate. Paint cost dominated by GPU; CPU-side per-frame cost ~negligible. |
| `RevealedSdfBuilder.buildFromDiscs` | UI (main) isolate (initially) | Donor file's documented cost is <16 ms for ~100 discs. POC will not exceed this scale. **Promote to worker isolate** if profiling shows the per-walk SDF rebuild crossing 12 ms. |
| `WispParticleSystem.advance(dt)` | UI (main) isolate | <50 µs per frame for 200 wisps per donor docstring. Stays main. |
| PMTiles parsing / decoding | `vector_map_tiles` internal isolate pool | Already handled by the library. |
| Geolocator stream | Platform thread (under the hood) | Standard. Surfaces as a Dart `Stream` consumed on UI isolate. |

Decision: **start everything on the UI isolate**, instrument the SDF rebuild path with `Stopwatch` log lines (per the donor file already does), promote to a worker isolate iff a UAT walk surfaces jank traceable to SDF rebuild. Don't pre-emptively isolate-split.

---

## Build order — phase ordering tied to risk

The user has stated phase order should align with risk de-risking and that iOS UAT walks happen between phases. The single biggest unknown is **the same-pipeline hypothesis on iOS**. Everything else is conventional Flutter work. So the order should front-load the hypothesis test as much as possible.

**Proposed phase order:**

| # | Phase | What ships | Why this position | iOS UAT signal |
|---|---|---|---|---|
| **0** | Bootstrap & CI | Empty Flutter app, license headers, GOSL banner script, `pubspec.yaml` with all deps strictly pinned, `analysis_options.yaml` strict, in-app file logger + share-logs button, GitHub Actions building IPA + APK on every push, `DEPENDENCIES.md` with first-pass audit. | Without CI producing an IPA the developer can't walk anything on iOS. Without the file logger and share-logs button, iOS bugs are uninvestigable. | Sideload empty IPA, share log file, confirm round-trip works. |
| **1** | Map + PMTiles + gestures (no fog) | Permission gate, `MapScreen`, `FlutterMap` + `VectorTileLayer` + `vector_map_tiles_pmtiles` loading bundled `Fra_Melun.pmtile`, pan/zoom/combined gestures. | This is the second-biggest risk: vector tile FPS on iOS. Cheaper to fail here than to fail with fog wired up. | Walk the map, pan-zoom-pinch around Melun. Pass = >30 fps subjective + tiles look acceptable. |
| **2** | GPS + blue dot + recenter button | Geolocator stream, in-memory `RevealDisc` repository (just to log fixes), `BlueDotMarkerLayer`, recenter FAB. | Provides the GPS fixture the fog needs. Visually trivial. | Walk; blue dot follows; recenter works. |
| **3** | **THE HYPOTHESIS — fog layer with shader (no wisps yet)** | Port `RevealedSdfBuilder`, `MirkProjection`, `tile_cell_iteration`, `FogShaderUniforms`, `animation_helpers`, `atmospheric_fog.frag`, constants. Wire `FogLayer` widget. Identity `uSdfRect`. | This is the architectural test. If it fails, every later phase is wasted. Front-loaded as early as the prerequisites allow. | **The decisive walk.** Pan, zoom, and combined pinch-zoom-pan with fog active. Look for any fog-vs-map slippage. >30 fps target. |
| **4** | Wisps | Port `WispParticle`, `WispParticleSystem`. Add `WispLayer` after `FogLayer`. Spawn on disc emergence. | Visual polish on top of a working hypothesis. | Walk; new GPS fix produces a wisp burst that drifts and fades. FPS holds. |
| **5** | Polish + harden | Strict-pin audit pass, `DEPENDENCIES.md` complete, GOSL header on every `.dart` file, analyzer/format clean, lint warnings zero. | After the visual product is correct, lock everything down for the donor port-back. | Final sideload walk; sanity-check on Pixel 4a. |

**Why not start with the fog?** Because the fog needs (a) a working flutter_map showing tiles, (b) GPS to feed it discs. Phases 1 and 2 are the minimum viable scaffolding for Phase 3 to be testable. Skipping or compressing them makes Phase 3 untestable, not faster.

**Why wisps after the hypothesis?** Wisps add visual noise that masks small fog-tracking errors — testing the hypothesis without them gives the cleanest signal.

---

## Counterfactuals — what would change my mind

| If we discover... | I'd switch to... |
|---|---|
| `vector_map_tiles` 8.x drops below 20 fps on iOS during sustained pinch-zoom of `Fra_Melun.pmtile` (despite user's prior validation) | First: try `vector_map_tiles` 9.x (stable as of late 2024) or 10.0.0-beta on `flutter_gpu` master channel. If neither works: fall back to a raster tileset rendered via `flutter_map`'s standard `TileLayer` (no vector). Loss: cartographic restyling capability. Gain: known-good FPS path on every device. |
| The custom `FogLayer` paints out-of-sync with `TileLayer` despite reading `MapCamera.of(context)` | Inspect whether `vector_map_tiles` introduces an internal `RepaintBoundary` or asynchronous tile-painting that breaks the same-frame guarantee. If so: ship the fog as a polygon-with-shader inside `vector_map_tiles`' theme system, or invest in the `flutter_gpu` migration (Candidate 4) once it ships stable. |
| `flutter_gpu` reaches stable channel during the POC | Re-evaluate Candidate 4 *after* the POC ships. The POC's job is to test the same-pipeline hypothesis on stable Flutter; flutter_gpu is a future optimisation path, not the hypothesis test. |
| Pixel 4a Adreno 618 OpenGL ES fallback exhibits a shader gradient bug (per Flutter [#179268](https://github.com/flutter/flutter/issues/179268)) on the existing shader | Hard-disable the OpenGL ES backend on the affected device class and accept that Pixel 4a is a debug-only device — production target is iOS. If it's ALSO broken on iOS Metal: file a Flutter issue; the same shader runs in MirkFall today, so this would be a regression, not a steady-state. |
| A Mac becomes available to the developer mid-POC | Doesn't change the recommendation. `flutter_map` is still the right architecture; a Mac just makes Candidate 5 feasible *if* `flutter_map` somehow fails. Order of fallback would still be `flutter_map` → MapLibre custom layer (now with a Mac) → custom MVT. |

---

## Anti-Patterns

### Anti-Pattern 1: Re-introducing dynamic `uSdfRect`

**What people do:** "Optimise" the SDF by building it in disc-bbox space and remapping per-pixel via non-identity `uSdfRect` uniforms.

**Why it's wrong:** This is BUG-014 Iteration 4 in spirit. With a same-pipeline architecture there is *nothing to compensate for* — the SDF is built in viewport-normalised space and the shader samples it with identity. Adding a dynamic rect re-introduces the failure mode that broke MirkFall on combined zoom+pan.

**Do this instead:** Always pass `uSdfRectOriginX/Y = 0`, `uSdfRectSizeX/Y = 1`. Rebuild the SDF when (disc-list-hash OR viewport-bbox-hash) changes, otherwise reuse.

### Anti-Pattern 2: Adding a `RepaintBoundary` around `FogLayer`

**What people do:** Wrap the fog `CustomPaint` in a `RepaintBoundary` "for performance".

**Why it's wrong:** A `RepaintBoundary` causes the wrapped subtree to paint into a separate compositor layer, decoupling its paint timing from the parent. That literally re-creates the BUG-014 split (in miniature). The whole architectural argument is "no separate layer".

**Do this instead:** Trust the single outer `RepaintBoundary` that `FlutterMap` already provides. Don't add more.

### Anti-Pattern 3: Reading the camera from `MapController.camera` in `setState`

**What people do:** Stash the current camera in a Riverpod provider on every `MapEventMove`, then read the stashed copy in `_FogPainter.paint()`.

**Why it's wrong:** This re-introduces a transport hop (event → setState → rebuild → paint) and the value can be one frame stale relative to what `TileLayer` is painting **right now**.

**Do this instead:** Read `MapCamera.of(context)` directly inside `FogLayer.build()`. The `MapInheritedModel` ensures every layer sees the same camera in the same build.

### Anti-Pattern 4: Mixing state managers

**What people do:** Riverpod for some state + a `ChangeNotifier` MirkFog controller + an internal `setState` here and there.

**Why it's wrong:** CLAUDE.md project rule: *one* state manager. Mixing complicates testing and donor port-back.

**Do this instead:** Riverpod (or whatever MirkFall uses — match it) everywhere except trivially-local `setState` on widgets that own no public state.

### Anti-Pattern 5: Using `flutter_gpu`-based `vector_map_tiles` 10.0.0-beta during the POC

**What people do:** "Latest is greatest" — pin to the beta because it promises better FPS.

**Why it's wrong:** It requires the master channel of Flutter, which routinely breaks the build. The POC's job is to test the hypothesis on **stable** Flutter so the answer is interpretable. If `vector_map_tiles` 8.x is too slow, that's its own decision to make, post-POC.

**Do this instead:** Strictly pin `vector_map_tiles: 8.0.0` and revisit after the hypothesis validates.

---

## Integration Points

### External services (none beyond GPS and the bundled file)

| Service | Integration | Notes |
|---|---|---|
| iOS / Android GPS | `geolocator` 14.x stream | `locationWhenInUse` only. Timeout per CLAUDE.md timeout rule (set in `constants.dart`). |
| Bundled PMTiles | `PmTilesVectorTileProvider.fromSource('asset:///assets/maps/Fra_Melun.pmtile')` | Loaded via Flutter asset bundle. No network. |

### Internal boundaries

| Boundary | Communication | Notes |
|---|---|---|
| `application` ↔ `domain` | Direct Dart imports | Domain has no Flutter import beyond `dart:ui`. |
| `application` ↔ `infrastructure` | Direct Dart imports | DI via Riverpod overrides at the `ProviderScope`. |
| `presentation` ↔ `application` | Riverpod `ref.watch / ref.read` | One state manager only. |
| `FogLayer` widget ↔ flutter_map | `MapCamera.of(context)` only | The camera object is the only renderer-specific surface in the fog path. Donor port-back to MirkFall replaces this single line with the equivalent maplibre_gl camera read — every other line is unchanged. |

---

## Scaling considerations (within the POC's bounds)

The POC has a single device user, a single bbox, an in-memory disc list. "Scaling" here means *gesture frame budget*, not *user count*.

| Scale | Bottleneck | Mitigation |
|---|---|---|
| 0 discs | none | — |
| 1–100 discs (an hour's walk) | SDF rebuild on disc list change. Per donor doc <16 ms. | Cache on disc-list hash; rebuild only on actual mutation. |
| 100–1000 discs | SDF rebuild starts crossing 16 ms. | (a) Spatial-grid index disc-touched cells (TODO already in donor file). (b) Move SDF build to worker isolate. |
| Pinch-zoom mid-gesture | TileLayer re-rasterising vector tiles + FogLayer re-painting | Trust `vector_map_tiles` tile cache; ensure `FogPainter.shouldRepaint` returns true only when uniforms changed. |
| Wisp count > 200 | LRU evict (already in donor system). | No mitigation needed; donor system handles it. |

---

## Sources

- [`fleaflet/flutter_map`/lib/src/map/widget.dart on master](https://github.com/fleaflet/flutter_map/blob/master/lib/src/map/widget.dart)
- [`fleaflet/flutter_map`/lib/src/map/inherited_model.dart on master](https://github.com/fleaflet/flutter_map/blob/master/lib/src/map/inherited_model.dart)
- [`fleaflet/flutter_map`/lib/src/layer/shared/mobile_layer_transformer.dart on master](https://github.com/fleaflet/flutter_map/blob/master/lib/src/layer/shared/mobile_layer_transformer.dart)
- [pub.dev/packages/flutter_map (8.3.0, BSD-3, ~16 days old)](https://pub.dev/packages/flutter_map)
- [pub.dev/packages/vector_map_tiles (8.0.0 stable, Apache-2.0; 10.0.0-beta on flutter_gpu)](https://pub.dev/packages/vector_map_tiles)
- [pub.dev/packages/vector_map_tiles_pmtiles (1.5.0, MIT)](https://pub.dev/packages/vector_map_tiles_pmtiles)
- [pub.dev/packages/pmtiles (2.0.0, BSD-2)](https://pub.dev/packages/pmtiles)
- [pub.dev/packages/mapsforge_flutter (4.0.0, **LGPL-3.0** — REJECTED)](https://pub.dev/packages/mapsforge_flutter)
- [Flutter docs — Impeller rendering engine](https://docs.flutter.dev/perf/impeller)
- [Flutter engine — Flutter-GPU.md (preview, master only)](https://github.com/flutter/engine/blob/main/docs/impeller/Flutter-GPU.md)
- [Flutter — Writing and using fragment shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders)
- [maplibre/flutter-maplibre-gl — README ("only a subset of the native SDK APIs are currently exposed")](https://github.com/maplibre/flutter-maplibre-gl)
- [MapLibre Native — September 2025 newsletter (custom drawable layer in development)](https://maplibre.org/news/2025-10-04-maplibre-newsletter-september-2025/)
- [Flutter issue #179268 — gradient bugs on Android Impeller OpenGL ES fallback path](https://github.com/flutter/flutter/issues/179268)
- [greensopinion/flutter-vector-map-tiles issue #10 — performance discussion](https://github.com/greensopinion/flutter-vector-map-tiles/issues/10)
- POC project files (read directly):
  - `C:\claude_checkouts\mirk-poc-debug\.planning\PROJECT.md`
  - `C:\claude_checkouts\GOSL-MirkFall\docs\POC-flutter-map-mirk.md`
  - `C:\claude_checkouts\GOSL-MirkFall\docs\phase09-bug-tracking\BUG-014-sdf-rect-offset-axes.md`
  - `C:\claude_checkouts\GOSL-MirkFall\assets\shaders\atmospheric_fog.frag`
  - `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\mirk\sdf\revealed_sdf_builder.dart`
  - `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\mirk\mirk_projection.dart`
  - `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\mirk\wisp\wisp_particle_system.dart`

---

*Architecture research for: pure-Flutter same-Canvas fog-of-war POC*
*Researched: 2026-04-30*
