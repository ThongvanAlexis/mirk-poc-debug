# Phase 2: Map (no fog) - Research

**Researched:** 2026-05-01
**Domain:** Vector-tile map rendering on Flutter (`flutter_map 7.0.2` + `vector_map_tiles 8.0.0` + `vector_map_tiles_pmtiles 1.5.0`), GPS streaming (`geolocator 14.0.2`), camera tweening, and the 4 MB asset → support-dir copy lifecycle.
**Confidence:** HIGH on the API surface and the bundled-asset schema (verified against pub-cache source on this machine + pub.dev API docs); MEDIUM on iOS pan/zoom FPS at z=13–15 (no published benchmarks — the Phase 2 walk IS the benchmark, per STATE.md).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**PMTiles copy lifecycle**
- **Trigger:** in `PermissionGateScreen` after `Permission.locationWhenInUse` becomes granted, BEFORE `context.go('/map')`. Map screen mounts with file already in place — no FutureBuilder thrash.
- **First-launch UX:** no extra UI. The `await` extends the post-grant moment by ~100-500 ms; user sees the permission gate screen briefly remain. Subsequent launches: zero-latency idempotent skip.
- **Idempotency check:** `File.exists()` AND `lengthSync() == bundled-asset.lengthInBytes`. No SHA256 (deferred to v2 ROB-02).
- **Target dir:** `getApplicationSupportDirectory()`.
- **Path:** `p.join(supportDir, 'maps', 'Fra_Melun.pmtile')` — never `'/'` concatenation.
- **Failure recovery:** catch `FileSystemException`, log to FileLogger at `Level.SEVERE`, route to a generic error screen with the underlying message. No retry button.
- **Log line on first launch (success):** `Copied Fra_Melun.pmtile (~4 MB) in <N> ms`.

**GPS subscription**
- **Source:** `Geolocator.getPositionStream(LocationSettings(...))`. Cache the latest fix in a `Position? _lastFix` field on `_MapScreenState`. Never call `Geolocator.getLastKnownPosition()` (LOC-03).
- **Accuracy:** `LocationAccuracy.best` (~10 m on iPhone outdoors).
- **Distance filter:** 5 m.
- **Lifecycle:** subscribe in `MapScreen.initState`, cancel the `StreamSubscription` in `dispose`. NO pause-on-background — iOS already throttles `whenInUse` location updates to ~zero in background.
- **Pre-fix UX:** map renders at the LOC default (Melun centre, z=13) without a blue dot; recenter FAB shows its disabled state per LOC-05.
- **Blue dot rendering:** 7 px filled circle (`#2b7cd6`) with a 2 px white stroke at `_lastFix.toLatLng()`. Conditionally rendered only when `_lastFix != null`.

**Map camera bounds & gestures**
- **Min/max zoom:** locked to `[10, 15]`.
- **Pan bounds:** soft pad — `CameraConstraint.contain(bounds: bbox.expanded(~0.02°))`. Bbox: lon `[2.60, 2.72]`, lat `[48.50, 48.57]`.
- **Rotation gesture:** ENABLED (deviation from "POC parity with parent"). **Compass UI:** always-visible icon top-right, positioned UNDER the FPS overlay; tapping animates the bearing back to north (re-use the same 500 ms ease-in-out tween the recenter FAB uses, but only on the bearing axis).
- **Double-tap zoom:** enabled (flutter_map default).
- **Pan inertia / fling:** enabled (flutter_map default).
- **MapOptions sketch:** `interactionOptions: InteractionOptions(flags: InteractiveFlag.all)`.

**Recenter FAB UX**
- **Target:** always animate to `(_lastFix.latLng, zoom: 15)` per LOC-04. No zoom-preservation, no toggle behaviour.
- **Animation:** 500 ms `Curves.easeInOut` interpolation from current camera state (lat, lon, zoom) to (`_lastFix.latLng`, z=15). Hand-rolled `AnimationController` driving `MapController.move` per frame, OR the `flutter_map_animations` pattern if pin-friendly (researcher confirms — adds one direct dep).
- **Position:** bottom-right, default `Scaffold.floatingActionButton` slot.
- **Disabled state:** when `_lastFix == null`, `onPressed: null`.
- **Repeat-tap during animation:** cancel the in-flight `AnimationController`, capture the current interpolated camera state, start a new 500 ms tween to the latest `_lastFix`.
- **Icon:** `Icons.my_location`.

**Forward-decision for Phase 3 (locked here)**
- Fog rendering in the ~2 km pan-overpan band: SDF and clip path are world-space. Fog renders normally over the grey off-bbox area. No bbox-clamp masking layer.

### Claude's Discretion

- Exact compass icon glyph (`Icons.explore`, `Icons.compass_calibration`, custom asset, etc.) — bias toward Material icons.
- Recenter FAB icon (`Icons.my_location` is the obvious pick).
- Whether to use `flutter_map_animations` (BSD-3? — researcher must audit) or hand-roll the 500 ms tween. Hand-roll is preferred if it costs ≤ ~30 LOC.
- Tooltip strings for FAB and compass — French + English via `AppLocalizations` like Phase 1.
- Error screen visual layout (uses Phase 1's denied-screen pattern as a reference; same `buildPocAppBar`).
- Logging granularity per GPS fix: at minimum INFO log every fix at `Logger('domain.location')`.
- Animation curves and exact durations within the bracket.
- The `MapScreenServices` value object's exact shape.

### Deferred Ideas (OUT OF SCOPE)

- Walk-replay tool (record GPS fixes during a walk, replay on Pixel 4a / Windows desktop).
- Label thinning for perf (Pitfall 5).
- Off-bbox grey background colour customisation.
- GPS accuracy-degraded fixes (no accuracy filter for v1).
- Cross-restart auto-resume routing bug (deferred from Phase 1 AUTH-04).
- `flutter_map_animations` package adoption — only if hand-roll exceeds ~30 LOC.
- Compass icon as a tap-target conflict with rotation.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID      | Description                                                                                  | Research Support                                                                                                                                                                                  |
|---------|----------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| MAP-01  | One-time copy `Fra_Melun.pmtile` from `rootBundle` → `<getApplicationSupportDirectory()>/maps/`; idempotent skip on subsequent launches | `rootBundle.load('assets/maps/Fra_Melun.pmtile')` returns `ByteData`; `File(...).writeAsBytes(...)` is the standard pattern; `File.exists() + lengthSync()` makes the idempotency check ≪ 1 ms. See **Code Examples §1**. |
| MAP-02  | Render PMTiles via flutter_map 7.0.2 + vector_map_tiles 8.0.0 + vector_map_tiles_pmtiles 1.5.0, default style | Bundled archive's `vector_layers` IDs are `boundaries, buildings, earth, landcover, landuse, places, pois, roads, water` — Protomaps schema. `ProtomapsThemes.lightV3()` is the only network-egress-free default theme that matches. See **Standard Stack** + **Code Examples §2**. |
| MAP-03  | Initial camera centred on Melun (lat `48.5397`, lon `2.6553`, zoom `13`)                     | `MapOptions(initialCenter: LatLng(48.5397, 2.6553), initialZoom: 13)`. See **Code Examples §3**.                                                                                                  |
| MAP-04  | One-finger pan                                                                               | `InteractiveFlag.drag` — included in `InteractiveFlag.all`. See **Architecture Patterns §3**.                                                                                                     |
| MAP-05  | Pinch zoom                                                                                   | `InteractiveFlag.pinchZoom` + `InteractiveFlag.pinchMove` — included in `.all`.                                                                                                                   |
| MAP-06  | Combined pan+zoom smoothness                                                                 | flutter_map 7.0.2's `enableMultiFingerGestureRace` (default `false`) lets pinch+drag combine without one winning. Default `pinchZoomThreshold: 0.5` and `pinchMoveThreshold: 40.0` are sane.      |
| LOC-01  | Subscribe to `Geolocator.getPositionStream` with a sensible accuracy/distance filter         | `LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5)`. See **Code Examples §4**.                                                                                                 |
| LOC-02  | Render blue dot (radius 7 px, `#2b7cd6`, white stroke 2 px) at user position                 | `CircleLayer(circles: [CircleMarker(point: _lastFix.toLatLng(), radius: 7, color: Color(0xFF2B7CD6), borderStrokeWidth: 2, borderColor: Colors.white)])` — `useRadiusInMeter: false` (default). See **Code Examples §5**. |
| LOC-03  | Cache `_lastFix` in memory; do NOT call `Geolocator.getLastKnownPosition()`                  | Field on `_MapScreenState`; subscription handler does `setState(() => _lastFix = pos)`. iOS-known-bug docs reference the unreliable plugin path.                                                  |
| LOC-04  | Recenter FAB animates to `_lastFix` at zoom 15                                               | Hand-rolled `AnimationController` (500 ms, `Curves.easeInOut`) driving `_mapController.move(LatLng, zoom)` per frame. ~25 LOC — under the CONTEXT 30-LOC threshold; hand-roll wins, no new dep. See **Code Examples §6**. |
| LOC-05  | When `_lastFix == null`, the recenter button is disabled                                     | `onPressed: _lastFix == null ? null : _onRecenterPressed` — Material auto-greys.                                                                                                                  |
| PERF-02 | iPhone 17 Pro pan-FPS without fog ≥ 40                                                       | **Set `VectorTileLayer(layerMode: VectorTileLayerMode.raster)` (the default) — explicitly documented as "Provides the best frame rate" in vector_map_tiles 8.0.0 source.** Other levers: `concurrency: 4` (default, isolate-based parsing), `memoryTileCacheMaxSize`, `memoryTileDataCacheMaxSize`. See **Pitfall 1** for the falsification fallback. |

</phase_requirements>

## Summary

The stack is fully resolved and pinned in `pubspec.yaml`. The **single most important performance lever** for PERF-02 is `VectorTileLayerMode.raster` (the default in 8.0.0) — vector_map_tiles' source explicitly documents this mode as "Provides the best frame rate"; the alternative (`vector` mode) "can result in low frame rates". Do not override the default.

The bundled `Fra_Melun.pmtile` is a **Protomaps-schema** archive (vector_layers: `boundaries, buildings, earth, landcover, landuse, places, pois, roads, water`), generated by Planetiler (per its `planetiler:version` metadata field), zoom 0–15, MVT tile type, gzip-compressed tiles. **Use `ProtomapsThemes.lightV3()`** — V4 themes embed remote sprite URLs which would break AUDIT-03; V3 themes have no `sprites` field at all. The glyphs URL in V3 themes is metadata only — `vector_tile_renderer 5.2.0` source contains zero `package:http` / `HttpClient` calls and renders text via Flutter's local `TextPainter`, so no network egress occurs at runtime.

The local-file PMTiles loader is `await PmTilesVectorTileProvider.fromSource(absoluteFilesystemPath)` — the package auto-detects path vs URL by the `http://` / `https://` prefix. The provider holds a `PmTilesArchive` whose `close()` method MUST be called on widget disposal (mandatory per the `pmtiles 1.2.0` API), otherwise a `RandomAccessFile` handle leaks per map screen lifecycle.

For the recenter tween, `flutter_map 7.0.2`'s `MapController.move(LatLng, double zoom)` is **instant only** — no built-in animation. The third-party `flutter_map_animations 0.7.1` is the highest version that supports flutter_map 7.x (later versions require flutter_map 8.x). However the hand-rolled `AnimationController + tween + MapController.move` per frame is ~25 LOC — comfortably under the CONTEXT 30-LOC threshold — so **hand-roll wins, no new dep**, no DEPENDENCIES.md churn.

GPS background pause is handled automatically: `whenInUse` permission + no `UIBackgroundModes:location` in Info.plist (confirmed Phase 1 AUTH-05) + no Background Modes capability in Xcode means iOS suspends the location updates as soon as the app backgrounds. CONTEXT's "NO pause-on-background" decision is correct — no app-side code is needed.

**Primary recommendation:** Single `MapScreen` `StatefulWidget` rewrite. Body is a `Stack` of `[FlutterMap(controller, options: MapOptions(initialCenter, initialZoom: 13, minZoom: 10, maxZoom: 15, cameraConstraint: CameraConstraint.contain(bounds: meleunBboxPadded), interactionOptions: InteractionOptions(flags: InteractiveFlag.all)), children: [VectorTileLayer(tileProviders, theme: ProtomapsThemes.lightV3()), CircleLayer(circles: blueDot), MapCompass()]), FpsCounterOverlay (top-right, Phase 1 widget), RecenterFab (bottom-right)]`. PMTiles copy hooks into `PermissionGateScreen` between grant detection and `context.go('/map')`. No new direct dependencies.

## Standard Stack

### Core (already pinned in `pubspec.yaml` — no churn this phase)

| Library                   | Version | Purpose                                      | Why Standard                                                                                                                                                                                                              |
|---------------------------|---------|----------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `flutter_map`             | 7.0.2   | The map widget itself + camera + gestures    | Locked by Phase 1 RESEARCH Path A. The 7.x line is the chain that resolves cleanly with `vector_map_tiles 8.0.0`. flutter_map 8.x exists but the donor `vector_map_tiles 8.0.0` does not declare 8.x compatibility safely. |
| `vector_map_tiles`        | 8.0.0   | MVT tile decoder + theming + tile provider abstraction | The donor stack. 9.0-beta and 10.0 (with `flutter_gpu`) both exist but are explicitly pre-release per the 8.0.0 README — POC stays on 8.0.0. |
| `vector_map_tiles_pmtiles`| 1.5.0   | Adapter to read a PMTiles archive as a `VectorTileProvider` | Provides the **only** in-package Protomaps theme set (`ProtomapsThemes.lightV3()` etc.) so we don't need a separate `protomaps_themes_flutter` dep. 1.5.0 explicitly bundles `protomaps-themes-base@4.1.0` per the changelog. |
| `vector_tile_renderer`    | 5.2.0   | The `Theme` engine that consumes the JSON from `ProtomapsThemes` | Already pinned. Source-audit-clean for AUDIT-03 (zero `HttpClient` / `package:http`). Glyphs are rendered via Flutter's local `TextPainter` regardless of the theme's `glyphs` URL field. |
| `pmtiles`                 | 1.2.0   | Pure-Dart PMTiles v3 archive reader          | `PmTilesArchive.from(pathOrUrl)` is the entry point. `close()` is mandatory for the file-handle lifecycle. |
| `latlong2`                | 0.9.1   | `LatLng` value object                        | Used by every flutter_map API (`MapOptions.initialCenter`, `MapController.move`, `CircleMarker.point`). |
| `geolocator`              | 14.0.2  | GPS `Stream<Position>`                       | `getPositionStream(LocationSettings(...))`. Returns `Position` with `.latitude`, `.longitude`, `.accuracy`, `.timestamp`, `.altitude`, `.heading`, `.speed`. |
| `permission_handler`      | 12.0.1  | Re-used in `PermissionGateScreen` only — Phase 2 only consumes the outcome (the route already routes to `/map` after grant). | No Phase 2 churn. |
| `path_provider`           | 2.1.5   | `getApplicationSupportDirectory()`           | Returns iOS-non-iCloud-backed dir on iOS; `~/AppData/...` on Windows; private app dir on Android. |
| `path`                    | 1.9.1   | `p.join(supportDir, 'maps', 'Fra_Melun.pmtile')` | CLAUDE.md mandate. Never concat manually. |
| `logging`                 | 1.3.0   | `Logger('infrastructure.pmtiles')` / `Logger('domain.location')` / `Logger('presentation.map')` | Phase 1 hierarchy already in place. |

### Supporting

| Library                | Version | Purpose                              | When to Use                                                                                                                                                                              |
|------------------------|---------|--------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `flutter` SDK          | 3.41.7  | `AnimationController`, `Tween<double>`, `Curves.easeInOut`, `TickerProviderStateMixin` for the recenter tween | Hand-roll the camera tween; no new dep needed (the CONTEXT-locked < 30 LOC threshold is met).                                                                                            |
| `flutter` SDK          | 3.41.7  | `rootBundle.load('assets/maps/Fra_Melun.pmtile')` for the first-launch copy | The asset is already declared in `pubspec.yaml`'s `flutter.assets`.                                                                                                                      |

### Alternatives Considered

| Instead of                                                | Could Use                       | Tradeoff                                                                                                                                                                                                                                                                              |
|-----------------------------------------------------------|---------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Hand-rolled tween                                         | `flutter_map_animations 0.7.1` (MIT) | +1 direct dep, +DEPENDENCIES.md row, +audit cycle. README example is 4-6 LOC vs ~25 LOC hand-roll. **Rejected** — CONTEXT 30-LOC threshold met; the planner takes the hand-roll path. Highest 7.x-compat version is 0.7.1; later versions require flutter_map 8.x. (LOW-MEDIUM confidence on the *exact* highest 7.x version — pub.dev versions page didn't render the constraints; cross-check at planning time.) |
| `ProtomapsThemes.lightV4()`                               | (built-in)                      | V4 theme constructor sets `sprites: 'https://protomaps.github.io/basemaps-assets/sprites/v4/light'` — sprites would be lazy-fetched at render time, violating AUDIT-03's zero-network-egress rule. **Rejected** in favour of `ProtomapsThemes.lightV3()` which has no sprites field. |
| `VectorTileLayerMode.vector`                              | (alt mode)                      | Sharper pan/zoom transitions, but vector_map_tiles 8.0.0 source comments explicitly state: "can result in low frame rates." PERF-02 is the gate — **stay with `raster` (the default).**                                                                                                |
| Custom OMT theme JSON bundled as asset                    | (alt theme)                     | The bundled PMTiles is Protomaps-schema (verified by metadata extraction — vector_layers `boundaries/buildings/earth/landcover/landuse/places/pois/roads/water`), NOT OMT. An OMT theme would render an empty map. **Rejected** — schema mismatch.                                  |
| `CameraConstraint.containCenter(bounds: …)`               | (alt constraint)                | Constrains only the camera's centre to within bounds — looser than `contain` which constrains the camera's entire viewport. CONTEXT chose `contain` with `~0.02°` overpan padding for the soft-edge feel. **Honour CONTEXT — use `contain`.**                                          |
| `MarkerLayer` with a custom `Marker` widget               | `CircleLayer + CircleMarker`    | `MarkerLayer` is "more flexible" but allocates a Flutter widget per marker; `CircleMarker` is the immutable "more performant" path per its dartdoc. The blue dot is one circle — `CircleLayer` wins.                                                                                  |
| Polling `Geolocator.getCurrentPosition()` on a timer      | `getPositionStream`             | Wastes battery, misses fixes between polls, no distance filter. **Reject.**                                                                                                                                                                                                          |

**No new packages — `pubspec.yaml` is unchanged for Phase 2.**

## Architecture Patterns

### Recommended Project Structure

```
lib/
├── config/
│   └── constants.dart                       # add map-specific constants here (see CONTEXT note)
├── domain/
│   └── map/
│       └── map_screen_services.dart         # NEW — value object for DI
├── infrastructure/
│   ├── pmtiles/
│   │   └── pmtiles_asset_copier.dart        # NEW — rootBundle → support-dir copy + idempotency
│   └── location/
│       └── geolocator_service.dart          # NEW — wraps getPositionStream, injectable for tests
└── presentation/
    ├── screens/
    │   ├── map_screen.dart                  # rewritten — body becomes FlutterMap stack
    │   ├── permission_gate_screen.dart      # ONE behavioural extension — PMTiles copy hook
    │   └── error_screen.dart                # NEW (or extend permission_denied_screen.dart)
    └── widgets/
        ├── recenter_fab.dart                # NEW — owns AnimationController for camera tween
        ├── map_compass.dart                 # NEW — always-visible icon, snap-to-north tween
        ├── blue_dot_marker.dart             # NEW — 7px / #2B7CD6 / 2px white stroke CircleMarker factory
        ├── poc_app_bar.dart                 # untouched (Phase 1)
        └── fps_counter_overlay.dart         # untouched (Phase 1)
```

### Pattern 1: Constructor-Injected Services (Established)

Phase 1 locked plain `StatefulWidget` + `setState` + constructor-injected services. Phase 2 follows.

```dart
// lib/domain/map/map_screen_services.dart
@immutable
class MapScreenServices {
  const MapScreenServices({
    required this.pmtilesPath,
    required this.positionStreamFactory,
    this.logger,
  });

  /// Absolute filesystem path to the PMTiles archive (already on disk by
  /// the time MapScreen is built — guaranteed by the PermissionGate copy hook).
  final String pmtilesPath;

  /// Factory so tests can swap in a fake stream of `Position` events.
  final Stream<Position> Function() positionStreamFactory;

  /// Optional override (defaults to `Logger('presentation.map')`).
  final Logger? logger;
}
```

`MapScreen.fromServices(this.services)` factory + `MapScreen()` default that wires production services internally — keeps tests trivial and prod call sites short. The router's builder picks the production wiring; widget tests inject fakes.

### Pattern 2: PMTiles Copy in `PermissionGateScreen`

```dart
Future<void> _onCtaPressed() async {
  final result = await Permission.locationWhenInUse.request();
  if (!mounted) return;
  if (!result.isGranted) {
    context.go('/denied');
    return;
  }
  try {
    await PmtilesAssetCopier.ensureCopied();   // ~100-500 ms first launch, ~1 ms subsequent
  } on FileSystemException catch (e) {
    if (!mounted) return;
    Logger('infrastructure.pmtiles').severe('PMTiles copy failed', e);
    context.go('/error', extra: e.message);
    return;
  }
  if (!mounted) return;
  context.go('/map');
}
```

The `_checkAndMaybeNavigate` path (initState + AppLifecycleState.resumed) needs the **same copy hook** — both grant detection paths must converge through `ensureCopied` before `context.go('/map')`. CONTEXT calls this out explicitly.

### Pattern 3: `FlutterMap` Body in `MapScreen.build`

```dart
FlutterMap(
  mapController: _mapController,
  options: MapOptions(
    initialCenter: const LatLng(kPocInitialCameraLat, kPocInitialCameraLon),
    initialZoom: kPocInitialZoom,                                    // 13
    minZoom: kPocMinZoom,                                            // 10
    maxZoom: kPocMaxZoom,                                            // 15
    cameraConstraint: CameraConstraint.contain(bounds: kPocPaddedBbox),
    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
    backgroundColor: const Color(0xFFE0E0E0),                        // off-bbox grey, default
    onMapEvent: _onMapEvent,                                         // optional — useful for compass UI bearing tracking
  ),
  children: <Widget>[
    VectorTileLayer(
      tileProviders: TileProviders(<String, VectorTileProvider>{'protomaps': _tileProvider}),
      theme: ProtomapsThemes.lightV3(),
      // layerMode left at default VectorTileLayerMode.raster — explicitly the best-frame-rate path
    ),
    if (_lastFix != null)
      CircleLayer(circles: <CircleMarker>[BlueDotMarker.build(_lastFix!.toLatLng())]),
  ],
)
```

The `MapController` is owned by `_MapScreenState` so the recenter tween can drive `_mapController.move(LatLng, zoom)` per `AnimationController.tick`.

The `ProtomapsThemes.lightV3()` source key is `"protomaps"` (per the theme constructor's default `sources` map) — `TileProviders({'protomaps': provider})` is therefore the correct mapping. **Wrong source key would trigger the assertion:** `"tileProviders must provide at least one provider that matches the given theme. … The theme uses the following sources: protomaps."` (verbatim from `vector_tile_layer.dart` 8.0.0).

### Pattern 4: Hand-Rolled Recenter Tween (under 30 LOC)

```dart
class _RecenterFabState extends State<RecenterFab> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  void _animateRecenter(Position fix) {
    _controller?.dispose();                         // cancel in-flight tween if any
    final from = widget.mapController.camera;      // MapCamera snapshot — atomic
    final toLat = fix.latitude;
    final toLon = fix.longitude;
    final fromZoom = from.zoom;
    const toZoom = kPocRecenterZoom;                // 15
    final fromLat = from.center.latitude;
    final fromLon = from.center.longitude;
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: kPocRecenterAnimationMs));
    final curved = CurvedAnimation(parent: c, curve: Curves.easeInOut);
    curved.addListener(() {
      final t = curved.value;
      widget.mapController.move(
        LatLng(fromLat + (toLat - fromLat) * t, fromLon + (toLon - fromLon) * t),
        fromZoom + (toZoom - fromZoom) * t,
      );
    });
    c.forward();
    _controller = c;
  }

  @override void dispose() { _controller?.dispose(); super.dispose(); }
}
```

~25 LOC inclusive of `dispose` — under the CONTEXT 30-LOC threshold. The compass snap-to-north reuses the same idiom, tweening only `bearing` via `_mapController.rotate(degree)` (rotate signature: `rotate(double degree, {String? id}) → bool`).

### Anti-Patterns to Avoid

- **Reading `MapCamera.maybeOf(context)` outside a `FlutterMap` subtree.** It returns `null`. Use `_mapController.camera` from your state (works any time after the first frame).
- **Calling `MapController.move` BEFORE the map is laid out.** Returns `false` and silently no-ops. Wait for the first `onMapReady` callback, OR guard the recenter tween against `_lastFix != null && context.mounted`.
- **Building `ProtomapsThemes.lightV3()` per `build()` call.** The Theme contains pre-parsed style data; create it once (e.g. as a `late final` field on `_MapScreenState` or wrap in a memoization).
- **Forgetting `archive.close()`.** Each `PmTilesVectorTileProvider.fromSource(...)` opens a `RandomAccessFile`. If the widget disposes without closing, the file handle leaks. Pattern: keep a reference to the `PmTilesVectorTileProvider` in `_MapScreenState`, call `_tileProvider.archive.close()` in `dispose`.
- **Subscribing to `Geolocator.getPositionStream()` inside `build()`.** Subscribe in `initState` exactly once; cancel in `dispose`.
- **Touching `BuildContext` after an `await` without `if (!mounted) return;`.** CLAUDE.md mandate, lint-enforced via `use_build_context_synchronously: error`.
- **Hard-coding `'/'` or `'\\'` in paths.** Always use `p.join(...)`. CLAUDE.md mandate.
- **`useRadiusInMeter: true` on the blue dot.** LOC-02 specifies pixels (7 px). Default `false` is correct.

## Don't Hand-Roll

| Problem                                          | Don't Build                                          | Use Instead                                                                                  | Why                                                                                                                                                                                            |
|--------------------------------------------------|------------------------------------------------------|----------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Reading PMTiles v3 archives                      | A homebrew binary parser                             | `pmtiles 1.2.0` (`PmTilesArchive.from(path)`)                                                | The PMTiles v3 spec has a 127-byte header, optional gzip/brotli/zstd internal compression, and a tile-directory tree with run-length encoding. Re-implementing is a multi-day footgun.        |
| Decoding MVT (Mapbox Vector Tile) protobuf       | Custom decoder                                       | `vector_tile_renderer 5.2.0`                                                                 | Already pinned, BSD-3, AUDIT-03-clean.                                                                                                                                                         |
| Rendering an MVT theme with expressions/data-driven styling | Custom paint pipeline                       | `vector_map_tiles 8.0.0` `VectorTileLayer` + `Theme`                                         | Theme JSON expression engine is non-trivial (zoom-based interpolation, data-driven property functions, filter expressions). Pure pain to re-implement.                                         |
| Camera-tween animation                           | (CONTEXT-locked: hand-rolled IS the path here)       | `AnimationController` + `MapController.move` per frame                                       | The hand-roll is < 30 LOC and avoids a new audited dependency; CONTEXT locks this. `flutter_map_animations 0.7.1` exists as the alternative if the planner ever exceeds 30 LOC.               |
| GPS streaming with platform parity               | Custom Method-channel calls to Core Location / FusedLocationProvider | `geolocator 14.0.2` `getPositionStream`                                              | iOS Core Location authorization state machine + Android Google Play Services FLP setup are >100 LOC of platform glue each.                                                                      |
| Idempotent asset copy                            | "Just check if file exists then write"               | The same — but use `length` parity, not just `exists()`                                      | A truncated previous copy (battery died mid-write) leaves a present-but-broken file; `lengthSync() == bundled-length` catches this in <1 ms. CONTEXT explicitly chose size parity, no SHA256.   |
| Compass icon UI                                  | Custom CustomPainter compass                          | Stock `Icons.explore` rotated by `Transform.rotate(angle: -bearing)`                         | Cheap, accessible, theme-aware.                                                                                                                                                                |
| Path manipulation                                | String concatenation with `/`                         | `package:path` `p.join(...)`                                                                 | CLAUDE.md mandate. Cross-platform-correct.                                                                                                                                                     |

**Key insight:** The whole vector-tiles stack is the result of years of accumulated MVT/Mapbox-style-spec / Skia-paint-pipeline domain expertise. The `ProtomapsThemes.lightV3()` JSON alone is hundreds of layer rules. A re-implementation — even of a "simple subset" — would be a multi-week distraction from the actual hypothesis (same-Canvas fog/map sync). The POC stays on the established stack.

## Common Pitfalls

### Pitfall 1: Vector-tile FPS dropping below the 40-fps PERF-02 gate at z=13–15

**What goes wrong:** Pan/zoom drops to 20–30 fps on iPhone 17 Pro at zoom 13–15 in central Melun, blocking Phase 3.

**Why it happens:** vector_map_tiles 8.0 renders MVT tiles into Skia canvases on the UI isolate. Label collision detection and complex styled fills (especially `landuse` polygons + `places` text labels at high zoom) are CPU-bound. Tile parsing happens on isolates (default `concurrency: 4`) but final paint is main-thread.

**How to avoid (Phase 2 first attempt):**
1. **Keep `VectorTileLayerMode.raster` (the default).** Source dartdoc: "Provides the best frame rate." Do not flip to `vector` mode.
2. Keep `concurrency: 4` (default — uses isolates for tile parsing).
3. Keep `maximumTileSubstitutionDifference: 2` (default — visual quality smooth during zoom changes).
4. Avoid building the `Theme` per-frame — build once as `late final`.
5. Avoid `MapOptions.keepAlive: true` if not strictly needed (leaves a tile cache live in memory).

**Falsification fallback (deferred-items if PERF-02 fails the walk):** Label thinning. `ProtomapsThemes.lightV3()` returns a `Theme` whose `layers` list can be filtered:
```dart
// Future Phase 2 mitigation if PERF-02 fails — NOT in initial Phase 2 scope.
Theme thinned = ProtomapsThemes.lightV3();
// Wrap in a custom builder that filters layers whose ID starts with `places_`
// or `roads_label_` at zoom < 14.
```
The CONTEXT defers this — start with the default theme, only thin if the walk fails the gate. This is the **path to falsification** for the planner to be aware of.

**Warning signs:** `FpsCounterOverlay` reads < 40 fps during a pan, especially at z=14–15 over central Melun (high-density POI / labels area).

### Pitfall 2: PMTiles archive file handle leak on widget rebuild

**What goes wrong:** Map screen disposes (e.g. user navigates away) but `RandomAccessFile` underneath the `PmTilesArchive` stays open. iOS's process file-descriptor budget is generous but not infinite; the leak is invisible until SideStore-sideloaded test sessions accumulate enough rebuilds.

**Why it happens:** `PmTilesVectorTileProvider.fromSource` calls `PmTilesArchive.from(path)` which calls `_FileReadAt` which holds a `RandomAccessFile` reference. The provider has no `dispose()` method that walks down to it; you have to call `archive.close()` explicitly.

**How to avoid:**
```dart
class _MapScreenState extends State<MapScreen> {
  PmTilesVectorTileProvider? _tileProvider;

  @override
  void initState() {
    super.initState();
    PmTilesVectorTileProvider.fromSource(widget.services.pmtilesPath)
        .then((p) { if (mounted) setState(() => _tileProvider = p); });
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    await _tileProvider?.archive.close();
  }
}
```

The async `dispose` pattern is acceptable — Flutter allows `Future<void> dispose()` and the `super.dispose()` first call is the safe ordering.

**Warning signs:** None visible in dev — discoverable only via instruments / sustained-session leaks. A widget test asserting that `archive.close()` is called on dispose is the cheap insurance.

### Pitfall 3: Theme/source-key mismatch silently rendering an empty map

**What goes wrong:** You wire `TileProviders({'openmaptiles': provider})` but `ProtomapsThemes.lightV3()`'s sources map declares `"protomaps"`. flutter_map shows a grey/empty canvas instead of erroring.

**Why it happens:** Actually, in `vector_map_tiles 8.0.0` this throws an `assert` at construction time:
```
tileProviders must provide at least one provider that matches the given theme.
…
The theme uses the following sources: protomaps.
```
But `assert` only fires in debug mode. In release mode (the IPA you sideload), the construction silently passes and the map appears empty / grey.

**How to avoid:** Use the literal string `'protomaps'` as the `TileProviders` map key — match the `ProtomapsThemes` constructor's default source name. Pin this in a constant: `const String kPocTileProviderSourceKey = 'protomaps';`.

**Warning signs:** Map appears as a uniform grey rectangle (the off-bbox `MapOptions.backgroundColor`) at all zoom levels. Logs show "tile not found" warnings repeatedly.

### Pitfall 4: PMTiles in `getApplicationDocumentsDirectory()` instead of `getApplicationSupportDirectory()`

**What goes wrong:** On iOS, the Documents directory is iCloud-backed by default (`NSUbiquitousContainerKey`). A 4 MB binary blob ends up in the user's iCloud, eating their backup budget and re-syncing on every launch. **CONTEXT explicitly calls this out.**

**Why it happens:** `path_provider` exposes both `getApplicationDocumentsDirectory()` (iCloud-backed on iOS) and `getApplicationSupportDirectory()` (NOT iCloud-backed). The naming-similarity confuses many devs.

**How to avoid:** Always use `getApplicationSupportDirectory()` for opaque app-managed assets. Documents is for user-visible files (the Files app on iOS shows it).

**Warning signs:** None visible during dev. Discoverable only via the user's iCloud storage backup view, or via the `NSURLIsExcludedFromBackupKey` `xattr` audit.

### Pitfall 5: GPS subscription leak on hot-reload during dev

**What goes wrong:** During `flutter run` hot-reload, `MapScreen` rebuilds without disposing the old `_MapScreenState`. Multiple `Geolocator.getPositionStream` subscriptions stack up. Visible only by spurious `_lastFix` jumps in dev builds.

**Why it happens:** Hot-reload preserves State in some scenarios but spawns new ones in others. The `WidgetsBindingObserver` lifecycle observers compound similarly.

**How to avoid:** Cancel the subscription in `dispose` no matter what:
```dart
@override
void dispose() {
  _positionSubscription?.cancel();
  _positionSubscription = null;
  super.dispose();
}
```
Optionally guard the subscription against double-subscribe in `initState` (`if (_positionSubscription != null) return;`).

**Warning signs:** Logs show duplicate `domain.location` `Got fix: …` lines in dev with the same timestamp.

### Pitfall 6: Race between PMTiles copy completion and `MapScreen` build

**What goes wrong:** If a future refactor moves the PMTiles copy off the gate screen and onto `MapScreen.initState`, the `FlutterMap` builds before the file exists; `PmTilesVectorTileProvider.fromSource` throws "file not found"; the screen renders error.

**Why it happens:** `flutter_map`'s `VectorTileLayer` synchronously requires a `VectorTileProvider` at construction time. There's no built-in `FutureBuilder` integration.

**How to avoid:** **Honour CONTEXT — keep the copy in `PermissionGateScreen`.** Map screen mounts with the file already on disk. No FutureBuilder thrash, no white-flash during the 100-500 ms first-launch copy. Tests should also write the test PMTiles file to the temp dir BEFORE pumping the `MapScreen` widget.

**Warning signs:** First-launch test fails with `FileSystemException: Cannot open file`. (Should never happen if CONTEXT is honoured.)

### Pitfall 7: `MapController.move` called before first frame

**What goes wrong:** Recenter FAB tapped immediately on cold launch (before the first map frame); `_mapController.move(...)` returns `false` and silently no-ops.

**Why it happens:** `MapController` requires the inner `_FlutterMapState` to be attached to the widget tree before `move` can succeed. Pre-first-frame is "detached".

**How to avoid:** The CONTEXT-locked LOC-05 disabled-state already handles this — when `_lastFix == null`, `onPressed: null` (FAB greyed out). The first GPS fix arrives strictly after the first map frame in any realistic flow, so by the time the FAB is enabled, the map is laid out.

Optional defensive guard: subscribe to `_mapController.mapEventStream` and only enable the FAB after the first `MapEventMove` (or `MapEventOnReady` from `MapOptions.onMapReady`).

**Warning signs:** First tap of the FAB does nothing; second tap works. Add an `onMapReady` callback that flips a `bool _mapReady` flag; gate the FAB on `_mapReady && _lastFix != null` if you observe this.

### Pitfall 8: `glyphs` URL in `ProtomapsThemes` vs AUDIT-03

**What goes wrong:** Reviewer reads the `ProtomapsThemes` source, sees `https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf`, panics about AUDIT-03 zero-network-egress.

**Why it doesn't actually fire:** `vector_tile_renderer 5.2.0`'s renderer ignores the `glyphs` URL entirely — text is rendered via Flutter's local `TextPainter` against system fonts (Roboto on Android, San Francisco on iOS). Source-grep confirms zero `HttpClient` / `package:http` calls in `vector_tile_renderer/lib/`. The `glyphs` field is parsed for spec-compliance and discarded.

**How to document:** Add a comment in `MapScreen` near the `ProtomapsThemes.lightV3()` call:
```dart
// Note: ProtomapsThemes.lightV3() embeds a `glyphs` URL in the theme JSON,
// but vector_tile_renderer 5.2.0 ignores it (text rendered via Flutter's
// local TextPainter, no HttpClient anywhere in vector_tile_renderer).
// AUDIT-03 stays clean. Verified by source-grep on 2026-05-01.
```
Future audits won't have to re-discover this.

**Warning signs:** None — but a CI audit step that greps the resolved deps for `package:http` import would catch any future regression.

## Code Examples

### §1 — PMTiles copy (MAP-01)

```dart
// lib/infrastructure/pmtiles/pmtiles_asset_copier.dart
class PmtilesAssetCopier {
  static const _bundledPath = 'assets/maps/Fra_Melun.pmtile';
  static const _basename    = 'Fra_Melun.pmtile';
  static final _log = Logger('infrastructure.pmtiles');

  /// Idempotent. Returns the absolute filesystem path to the copied archive.
  /// Throws [FileSystemException] on copy failure.
  static Future<String> ensureCopied() async {
    final supportDir = await getApplicationSupportDirectory();
    final mapsDir    = Directory(p.join(supportDir.path, 'maps'));
    if (!await mapsDir.exists()) await mapsDir.create(recursive: true);
    final dstPath = p.join(mapsDir.path, _basename);
    final dst     = File(dstPath);

    final bundled = await rootBundle.load(_bundledPath);
    final bundledBytes = bundled.lengthInBytes;

    if (await dst.exists() && dst.lengthSync() == bundledBytes) {
      // Silent — CONTEXT mandate: nothing logged on subsequent launches.
      return dstPath;
    }

    final sw = Stopwatch()..start();
    await dst.writeAsBytes(bundled.buffer.asUint8List(), flush: true);
    sw.stop();
    _log.info('Copied $_basename (~${(bundledBytes / (1024 * 1024)).toStringAsFixed(1)} MB) in ${sw.elapsedMilliseconds} ms');
    return dstPath;
  }
}
```

The log line phrasing matches the CONTEXT specifics §2 exact-phrasing requirement: `"Copied Fra_Melun.pmtile (~4 MB) in <N> ms"`. The 4.0 → 4.1 MB rounding stays cosmetic.

### §2 — Provider + Theme wiring (MAP-02)

```dart
// In _MapScreenState.initState (or via the services factory):
PmTilesVectorTileProvider.fromSource(widget.services.pmtilesPath)
    .then((provider) {
  if (!mounted) {
    provider.archive.close();         // disposed before the future resolved
    return;
  }
  setState(() => _tileProvider = provider);
});

// In build():
final theme = _theme ??= ProtomapsThemes.lightV3();   // memoize on first build

VectorTileLayer(
  tileProviders: TileProviders(<String, VectorTileProvider>{
    kPocTileProviderSourceKey: _tileProvider!,        // 'protomaps'
  }),
  theme: theme,
);
```

### §3 — MapOptions (MAP-03, MAP-04, MAP-05, MAP-06)

```dart
MapOptions(
  initialCenter: const LatLng(kPocInitialCameraLat, kPocInitialCameraLon),  // 48.5397, 2.6553
  initialZoom: kPocInitialZoom,                                              // 13
  minZoom: kPocMinZoom,                                                      // 10
  maxZoom: kPocMaxZoom,                                                      // 15
  cameraConstraint: CameraConstraint.contain(
    bounds: LatLngBounds(
      const LatLng(kPocBboxLatMin - kPocPanBoundsPadDegrees, kPocBboxLonMin - kPocPanBoundsPadDegrees),
      const LatLng(kPocBboxLatMax + kPocPanBoundsPadDegrees, kPocBboxLonMax + kPocPanBoundsPadDegrees),
    ),
  ),
  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
);
```

`InteractiveFlag.all` includes `drag | flingAnimation | pinchMove | pinchZoom | doubleTapZoom | rotate | scrollWheelZoom | doubleTapDragZoom`. CONTEXT keeps all of them, including `rotate` (deviation from parent for the same-Canvas hypothesis stress test).

### §4 — Geolocator subscription (LOC-01, LOC-03)

```dart
// lib/infrastructure/location/geolocator_service.dart
class GeolocatorService {
  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: kPocGpsDistanceFilterMeters,   // 5
  );
  static final _log = Logger('domain.location');

  /// Returns a fresh stream — subscribe once per MapScreen instance.
  static Stream<Position> stream() {
    _log.info('Subscribing to Geolocator.getPositionStream(accuracy=best, distanceFilter=5)');
    return Geolocator.getPositionStream(locationSettings: _settings);
  }
}

// In _MapScreenState:
StreamSubscription<Position>? _positionSubscription;

@override
void initState() {
  super.initState();
  _positionSubscription = widget.services.positionStreamFactory().listen(
    (Position fix) {
      if (!mounted) return;
      setState(() => _lastFix = fix);
      _log.info('Fix: ${fix.latitude.toStringAsFixed(5)}, ${fix.longitude.toStringAsFixed(5)} ±${fix.accuracy.toStringAsFixed(0)}m');
    },
    onError: (Object e) => _log.warning('Position stream error', e),
  );
}

@override
void dispose() {
  _positionSubscription?.cancel();
  _positionSubscription = null;
  // ... archive.close() etc.
  super.dispose();
}
```

iOS `whenInUse` permission + no `UIBackgroundModes:location` (Phase 1 AUTH-05 ✓) means iOS will automatically suspend `getPositionStream` when the app backgrounds — **no app code needed.** CONTEXT decision honoured.

### §5 — Blue dot (LOC-02)

```dart
// lib/presentation/widgets/blue_dot_marker.dart
class BlueDotMarker {
  static const _fillColor   = Color(0xFF2B7CD6);
  static const _strokeColor = Colors.white;
  static const _radiusPx    = 7.0;
  static const _strokePx    = 2.0;

  static CircleMarker build(LatLng point) => CircleMarker(
    point: point,
    radius: _radiusPx,
    useRadiusInMeter: false,        // pixels — LOC-02 mandates px
    color: _fillColor,
    borderStrokeWidth: _strokePx,
    borderColor: _strokeColor,
  );
}

// In MapScreen.build:
if (_lastFix != null)
  CircleLayer(circles: <CircleMarker>[BlueDotMarker.build(LatLng(_lastFix!.latitude, _lastFix!.longitude))]),
```

### §6 — Recenter tween (LOC-04, LOC-05)

```dart
// lib/presentation/widgets/recenter_fab.dart  (~25 LOC core)
class RecenterFab extends StatefulWidget {
  const RecenterFab({super.key, required this.mapController, required this.lastFix});
  final MapController mapController;
  final Position? lastFix;

  @override
  State<RecenterFab> createState() => _RecenterFabState();
}

class _RecenterFabState extends State<RecenterFab> with TickerProviderStateMixin {
  AnimationController? _ctl;

  void _onPressed() {
    final fix = widget.lastFix;
    if (fix == null) return;            // belt-and-braces; FAB is also disabled in build
    _ctl?.dispose();
    final cam = widget.mapController.camera;
    final fromLat = cam.center.latitude, fromLon = cam.center.longitude, fromZ = cam.zoom;
    final toLat = fix.latitude, toLon = fix.longitude;
    const toZ = kPocRecenterZoom;       // 15
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: kPocRecenterAnimationMs));
    final t = CurvedAnimation(parent: c, curve: Curves.easeInOut);
    t.addListener(() {
      final v = t.value;
      widget.mapController.move(
        LatLng(fromLat + (toLat - fromLat) * v, fromLon + (toLon - fromLon) * v),
        fromZ + (toZ - fromZ) * v,
      );
    });
    _ctl = c;
    c.forward();
  }

  @override
  void dispose() { _ctl?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FloatingActionButton(
    tooltip: AppLocalizations.of(context)?.recenterTooltip,
    onPressed: widget.lastFix == null ? null : _onPressed,    // LOC-05 disabled state
    child: const Icon(Icons.my_location),
  );
}
```

The compass snap-to-north widget reuses the same idiom — only difference is the call to `widget.mapController.rotate(angleDegrees)` per frame instead of `move`. ~25 LOC for that one too.

### §7 — Compass widget (Claude's discretion CONTEXT — bearing snap-to-north on tap)

```dart
// lib/presentation/widgets/map_compass.dart (sketch)
class MapCompass extends StatefulWidget {
  const MapCompass({super.key, required this.mapController});
  final MapController mapController;
  // Internally: subscribe to mapController.mapEventStream, when MapEventRotate
  // arrives, rebuild with the new bearing. On tap, tween bearing → 0.
}
```

Subscribe to `widget.mapController.mapEventStream.where((e) => e is MapEventRotate)` to keep the compass icon's `Transform.rotate(-bearingRadians)` synced; on tap, run a 250 ms `Curves.easeInOut` tween that calls `mapController.rotate(currentBearing * (1 - t))` per frame.

### §8 — Constants additions to `lib/config/constants.dart`

```dart
// Phase 2 — map screen tunables (CONTEXT §Constants section)
const double kPocInitialCameraLat        = 48.5397;
const double kPocInitialCameraLon        = 2.6553;
const double kPocInitialZoom             = 13;
const double kPocRecenterZoom            = 15;
const double kPocMinZoom                 = 10;
const double kPocMaxZoom                 = 15;
const double kPocBboxLatMin              = 48.50;
const double kPocBboxLatMax              = 48.57;
const double kPocBboxLonMin              = 2.60;
const double kPocBboxLonMax              = 2.72;
const double kPocPanBoundsPadDegrees     = 0.02;
const int    kPocRecenterAnimationMs     = 500;
const int    kPocCompassAnimationMs      = 250;
const int    kPocGpsDistanceFilterMeters = 5;
const String kPmtilesAssetPath           = 'assets/maps/Fra_Melun.pmtile';
const String kPmtilesBasename            = 'Fra_Melun.pmtile';
const String kPocTileProviderSourceKey   = 'protomaps';
```

## State of the Art

| Old Approach                                      | Current Approach                                          | When Changed       | Impact                                                                                                         |
|---------------------------------------------------|-----------------------------------------------------------|--------------------|----------------------------------------------------------------------------------------------------------------|
| Raster tile servers (z/x/y PNG/JPEG)              | Vector tiles (MVT) with client-side theming               | ~2020 mainstream   | Smaller archive size, themable on device, sharp at any zoom — but CPU cost shifts to the client.               |
| `vector_map_tiles 7.x` Skia/canvas backend        | `vector_map_tiles 10.x` `flutter_gpu` backend (beta)      | 2025               | 2-3× FPS improvement claimed in 10.0.0 README. **Not in our chain — we're locked to 8.0.0** (donor parity).   |
| `flutter_map 6.x` `MapOptions(center:, zoom:)`    | `flutter_map 7.x` `MapOptions(initialCenter:, initialZoom:)` | 2024 (v7 release) | Param renames; v7.0.2 also fixed perf regressions in PolygonLayer + PolylineLayer.                             |
| `permission_handler.openAppSettings()` (snake_case) | (camelCase already)                                     | n/a                | Phase 1 already on the modern API.                                                                             |
| `Share.shareXFiles(...)` (deprecated in share_plus 12.x) | `SharePlus.instance.share(ShareParams(...))`            | share_plus 12.0    | Phase 1 already migrated.                                                                                      |
| `Geolocator.getLastKnownPosition()`               | Cache `_lastFix` from the live stream (LOC-03)            | Always (POC mandate) | Plugin's `getLastKnownPosition` is unreliable on iOS — known plugin issue, hence the explicit POC ban.        |

**Deprecated/outdated (do NOT use):**
- `ProtomapsThemes.light()` (un-versioned) → `ProtomapsThemes.lightV3()` (un-versioned variants are `@Deprecated('Prefer to use a versioned theme')` in `vector_map_tiles_pmtiles 1.5.0`).
- `ProtomapsThemes.lightV4()` — V4 themes embed remote sprite URLs (`https://protomaps.github.io/basemaps-assets/sprites/v4/light`). AUDIT-03 forbids automatic network egress; V4 sprites would be lazy-fetched on render. **Stay on V3.**
- `silenceTileNotFound: true` parameter on `PmTilesVectorTileProvider.fromSource` — `@Deprecated('This option is no longer used and will get removed in a future update.')` per the 1.5.0 source.

## Open Questions

1. **Will PERF-02 pass on iPhone 17 Pro at z=13–15 over central Melun with the default `VectorTileLayerMode.raster`?**
   - What we know: vector_map_tiles 8.0 source explicitly documents `raster` mode as best-frame-rate; iPhone 17 Pro is the strongest currently-available iOS device; ProMotion 120 Hz target means the bar is "≥ 40 fps with headroom."
   - What's unclear: No published benchmarks of `vector_map_tiles 8.0` on iPhone 17 Pro at this zoom range with this dataset (Protomaps OMT-equivalent layer density over central Paris suburbs).
   - Recommendation: Phase 2 walk IS the answer — design the plan so a label-thinning fallback is achievable in 1 plan if the gate fails, with the falsification path captured in `deferred-items.md`.

2. **Does `MapController.rotate(degree)` accept a degree value relative to current bearing, or absolute (0 = north)?**
   - What we know: dartdoc says "Rotates the map to a decimal `degree` around the current center, where 0° is North." → absolute.
   - What's unclear: Whether passing the same degree twice no-ops, or whether a 720° rotation arrives at 0° via a 2-revolution path.
   - Recommendation: Bearing-snap-to-north tween should compute the shortest-path-on-the-circle delta, not a naive `t * (0 - currentBearing)` which would spin two full turns if currentBearing happened to be 720°. In practice flutter_map normalises to `[0,360)` so this is unlikely; but pin it down at planning time with a unit test.

3. **Exact highest `flutter_map_animations` version that supports `flutter_map 7.x`.**
   - What we know: changelog says "version 7 support" was added at v0.7.0; v0.8.0 and above need flutter_map v8.
   - What's unclear: Whether v0.7.1 / v0.7.2 are intermediate patch releases all on the 7.x base.
   - Recommendation: Moot for this phase — CONTEXT picks hand-roll. If a future phase needs the dep, planner verifies the version constraint against the resolved pubspec.lock.

4. **`PmTilesVectorTileProvider.fromSource` accepts an absolute path; does it tolerate Windows backslashes (`C:\path\to\file.pmtile`) for the desktop dev runs?**
   - What we know: Source uses `pathOrUrl.startsWith('http://')` only as the URL discriminator; everything else flows to filesystem.
   - What's unclear: Whether the underlying `dart:io` path resolution on Windows accepts both slashes universally.
   - Recommendation: Use `p.join(...)` everywhere — produces the platform-native separator. POC should "just work" on Windows desktop runs (a stated dev-loop platform).

5. **Does the `ProtomapsThemes.lightV3()` source key pin `'protomaps'` regardless of the underlying PMTiles archive's source name?**
   - What we know: The bundled archive (Protomaps Planetiler-built) doesn't carry a "source name" in its metadata — only the schema (vector_layers IDs). The theme's `sources: {"protomaps": ...}` is a string identifier that `vector_map_tiles` matches against the `tileProviders` map key. The PMTiles archive itself is source-agnostic.
   - Confirmation: Source-grep of `vector_tile_layer.dart` 8.0.0 → assertion message "The theme uses the following sources: protomaps." → exactly the literal string.
   - Recommendation: Hard-code `kPocTileProviderSourceKey = 'protomaps'` in constants. Confirmed.

## Validation Architecture

### Test Framework
| Property            | Value                                                                                                                                  |
|---------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| Framework           | `flutter_test` (SDK-bundled, Phase 1 ✓) + `package:test 1.30.0` for `tool/test/` scripts                                              |
| Config file         | `analysis_options.yaml` (strict-casts/inference/raw-types) + Phase 1 patterns from `test/presentation` and `test/infrastructure/logging` |
| Quick run command   | `flutter test test/presentation/screens/map_screen_test.dart`                                                                          |
| Full suite command  | `flutter test`                                                                                                                         |

### Phase Requirements → Test Map

| Req ID  | Behavior                                                                  | Test Type     | Automated Command                                                                                              | File Exists? |
|---------|---------------------------------------------------------------------------|---------------|----------------------------------------------------------------------------------------------------------------|--------------|
| MAP-01  | First-launch copy + idempotent skip + size-parity check                   | unit          | `flutter test test/infrastructure/pmtiles/pmtiles_asset_copier_test.dart -x`                                  | ❌ Wave 0   |
| MAP-01  | FileSystemException path → caught + logged + routes to /error             | widget        | `flutter test test/presentation/screens/permission_gate_screen_pmtiles_failure_test.dart -x`                  | ❌ Wave 0   |
| MAP-02  | `VectorTileLayer` constructed with `'protomaps'` source key + V3 theme    | widget        | `flutter test test/presentation/screens/map_screen_test.dart --plain-name "VectorTileLayer wired" -x`         | ❌ Wave 0   |
| MAP-03  | Initial camera at (48.5397, 2.6553, z=13)                                 | widget        | `flutter test test/presentation/screens/map_screen_test.dart --plain-name "initial camera Melun z13" -x`      | ❌ Wave 0   |
| MAP-04  | `InteractiveFlag.drag` enabled (in `.all`)                                | widget        | (same file) `--plain-name "InteractionOptions all flags"`                                                      | ❌ Wave 0   |
| MAP-05  | `InteractiveFlag.pinchZoom` enabled                                       | widget        | (same file) `--plain-name "pinch zoom flag set"`                                                              | ❌ Wave 0   |
| MAP-06  | Combined pan+zoom — `enableMultiFingerGestureRace: false` (default)       | widget        | (same file) `--plain-name "combined gestures race disabled"`                                                  | ❌ Wave 0   |
| LOC-01  | `getPositionStream` subscribed in `initState` with 5 m / `best`           | widget        | `flutter test test/presentation/screens/map_screen_gps_test.dart -x` (with fake stream factory)               | ❌ Wave 0   |
| LOC-02  | Blue dot rendered at `_lastFix` only when non-null; correct colour/stroke | widget        | (same file) `--plain-name "blue dot CircleMarker properties"`                                                  | ❌ Wave 0   |
| LOC-03  | No call to `Geolocator.getLastKnownPosition` anywhere in `lib/`           | static-source | `dart test tool/test/check_no_last_known_position_test.dart -x` (CI gate, see Wave 0 gap)                     | ❌ Wave 0   |
| LOC-04  | Recenter FAB animates camera to `_lastFix` at z=15 over 500 ms            | widget        | `flutter test test/presentation/widgets/recenter_fab_test.dart -x`                                            | ❌ Wave 0   |
| LOC-05  | FAB `onPressed: null` when `_lastFix == null`                             | widget        | (same file) `--plain-name "disabled when no fix"`                                                             | ❌ Wave 0   |
| LOC-04  | Repeat-tap mid-animation cancels old controller + restarts                | widget        | (same file) `--plain-name "repeat tap during animation"`                                                      | ❌ Wave 0   |
| PERF-02 | iPhone 17 Pro pan-FPS ≥ 40 at z=13–15                                     | manual UAT    | sideload IPA + walk; verbal `approved` exit gate (mirrors Phase 1 LOG-05 walk)                                | n/a (manual) |

**Compass tween, archive disposal, and PMTiles size-parity-mismatch (corrupted previous copy)** also need test files added in Wave 0 (see gaps list).

### Sampling Rate

- **Per task commit:** `flutter test test/presentation/screens/map_screen_test.dart test/infrastructure/pmtiles/ test/infrastructure/location/ test/presentation/widgets/recenter_fab_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green on Windows + CI Android + CI iOS before `/gsd:verify-work 02-map-no-fog`. Manual UAT (PERF-02 walk) is the human-verify exit gate.

### Wave 0 Gaps

- [ ] `test/infrastructure/pmtiles/pmtiles_asset_copier_test.dart` — covers MAP-01 (copy + idempotent + size-mismatch + FileSystemException paths). Uses a temp dir + a synthetic 4-byte fake PMTiles asset.
- [ ] `test/infrastructure/location/geolocator_service_test.dart` — covers LOC-01 settings (LocationAccuracy.best, distanceFilter: 5). Mock-able via `GeolocatorPlatform.instance` test seam (mirrors Phase 1's `PermissionHandlerPlatform.instance` pattern in `permission_gate_screen_test.dart`).
- [ ] `test/presentation/screens/map_screen_test.dart` — covers MAP-02..06 + LOC-02 + LOC-05. Pumps `MapScreen.fromServices(fakeServices)` with a fake stream factory and a fake-on-disk PMTiles file in the test temp dir.
- [ ] `test/presentation/screens/map_screen_gps_test.dart` — covers LOC-01 lifecycle (initState subscribe, dispose cancel, fix → setState).
- [ ] `test/presentation/screens/permission_gate_screen_pmtiles_failure_test.dart` — covers the FileSystemException catch + error route in the gate screen extension.
- [ ] `test/presentation/widgets/recenter_fab_test.dart` — covers LOC-04 (animation duration + curve + final position) and LOC-05 (disabled state) and the repeat-tap-cancellation edge case.
- [ ] `test/presentation/widgets/map_compass_test.dart` — covers compass tween + bearing-stream-sync.
- [ ] `test/presentation/widgets/blue_dot_marker_test.dart` — covers LOC-02 colour/stroke/radius + visibility-when-null.
- [ ] `tool/test/check_no_last_known_position_test.dart` — static-source assertion CI gate (mirrors the LOG-05 static-source pattern from Phase 1, per Plan 01-04 W-4 fix).
- [ ] `lib/domain/map/map_screen_services.dart` — new file, services value object.
- [ ] `lib/infrastructure/pmtiles/pmtiles_asset_copier.dart` — new file.
- [ ] `lib/infrastructure/location/geolocator_service.dart` — new file.
- [ ] `lib/presentation/widgets/recenter_fab.dart`, `lib/presentation/widgets/map_compass.dart`, `lib/presentation/widgets/blue_dot_marker.dart` — new widget files.
- [ ] `lib/presentation/screens/error_screen.dart` (or extend `permission_denied_screen.dart`) — new error route landing.
- [ ] Updated `lib/presentation/router.dart` — add `/error` route.
- [ ] Updated `lib/config/constants.dart` — Phase 2 constants block (see §8 above).
- [ ] Updated `lib/l10n/app_en.arb` + `app_fr.arb` — `recenterTooltip`, `compassTooltip`, `errorScreenTitle`, `errorScreenRetryHelp` strings + regen via `flutter gen-l10n`.

**No DEPENDENCIES.md row added** — Phase 2 introduces zero new direct dependencies. All required packages already pinned in Phase 1.

## Sources

### Primary (HIGH confidence)

- Local pub-cache source inspection on this machine (the most authoritative — these are the exact versions of code that will compile):
  - `C:/Users/oliver/AppData/Local/Pub/Cache/hosted/pub.dev/vector_map_tiles-8.0.0/lib/src/vector_tile_layer.dart` — `VectorTileLayer` constructor + `defaultConcurrency = 4`, `VectorTileLayerMode.raster` default, assertion message
  - `vector_map_tiles-8.0.0/lib/src/vector_tile_layer_mode.dart` — `raster` "Provides the best frame rate" / `vector` "can result in low frame rates"
  - `vector_map_tiles_pmtiles-1.5.0/lib/src/themes/protomaps_themes.dart` — V3 vs V4 sprite URLs, `glyphs` URL template, source name `"protomaps"`
  - `vector_map_tiles_pmtiles-1.5.0/lib/src/vector_tile_provider.dart` — `PmTilesVectorTileProvider.fromSource(String)` + `archive` field
  - `pmtiles-1.2.0/lib/src/archive.dart` — `PmTilesArchive.from(pathOrUrl)` + `close()` method
  - `flutter_map-7.0.2/lib/src/layer/circle_layer/circle_marker.dart` — `CircleMarker` constructor (radius/color/borderColor/borderStrokeWidth/useRadiusInMeter)
  - `vector_tile_renderer-5.2.0/lib/` — source-grep zero `HttpClient` / `package:http`, glyphs URL is metadata-only
- Bundled `Fra_Melun.pmtile` metadata extraction (Python script, this session) — confirmed Protomaps schema (vector_layers IDs), zoom 0–15, MVT, gzip-compressed tiles, Planetiler-generated.
- pub.dev API documentation:
  - https://pub.dev/documentation/flutter_map/7.0.2/flutter_map/MapOptions-class.html — full constructor verbatim
  - https://pub.dev/documentation/flutter_map/7.0.2/flutter_map/MapController-class.html — `move`, `rotate`, `fitCamera`, `mapEventStream`, `camera` signatures
  - https://pub.dev/documentation/flutter_map/7.0.2/flutter_map/CameraConstraint-class.html — `contain` / `containCenter` / `unconstrained` factories
  - https://pub.dev/documentation/flutter_map/7.0.2/flutter_map/InteractionOptions-class.html — full constructor + flag list
  - https://pub.dev/documentation/flutter_map/7.0.2/flutter_map/InteractiveFlag-class.html — flag constants
  - https://pub.dev/documentation/geolocator/14.0.2/geolocator/AppleSettings-class.html — full constructor
- Repo READMEs:
  - https://github.com/Baseflow/flutter-geolocator (geolocator README, iOS background-pause behaviour with whenInUse)
- Phase 1 artefacts: `DEPENDENCIES.md` (telemetry-clean rows for every Phase 2 package), `STATE.md`, `PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/phases/02-map-no-fog/02-CONTEXT.md`.

### Secondary (MEDIUM confidence)

- pub.dev package overview pages (https://pub.dev/packages/vector_map_tiles, https://pub.dev/packages/vector_map_tiles_pmtiles, https://pub.dev/packages/flutter_map_animations) — version-listing and dep-graph signals; less authoritative than reading the source directly but used to corroborate compatibility windows.
- https://github.com/josxha/flutter_map_plugins/blob/main/vector_map_tiles_pmtiles/example/example.md — the canonical local-PMTiles example (`fromSource('eitherAnUrlOrFileSystemPath')`).
- https://github.com/TesteurManiak/flutter_map_animations — `AnimatedMapController.animateTo` API + MIT licence; cross-checked the v0.7.0 "version 7 support" entry in the changelog.

### Tertiary (LOW confidence — flagged)

- WebSearch result claiming `flutter_map_animations 0.7.1` is the highest 7.x-compat version. Cross-verifiable later by reading the version-specific pubspec.yaml; not blocking since CONTEXT picks the hand-roll path. **Re-verify if the planner ever switches to `flutter_map_animations`.**
- WebSearch chatter about vector_map_tiles 8.x performance issues (GitHub Issues #10, #120) — no maintainer-quoted FPS numbers in this research session. The PERF-02 walk is the empirical answer.

## Metadata

**Confidence breakdown:**

- **Standard stack:** HIGH — every package is already pinned in `pubspec.yaml` and audited in `DEPENDENCIES.md`; constructor signatures and behaviour read directly from local pub-cache source.
- **Architecture:** HIGH — pattern is a direct continuation of Phase 1's plain-StatefulWidget + constructor-injected services; `MapScreen` rewrite is structurally identical to Phase 1's placeholder shell with the body swap. PMTiles copy hook into `PermissionGateScreen` is one method addition.
- **PMTiles schema match:** HIGH — physically extracted the bundled archive's metadata in this research session; vector_layers IDs match Protomaps basemap exactly.
- **AUDIT-03 cleanliness of V3 themes:** HIGH — source-grep of `vector_tile_renderer 5.2.0` confirms zero `HttpClient` / `package:http` calls; `ProtomapsThemes.lightV3()` source has no `sprites` field.
- **PERF-02 outcome:** MEDIUM — the entire ecosystem points to `VectorTileLayerMode.raster` default being the best path, but no published iPhone 17 Pro / z=13–15 / Protomaps-OMT-density benchmark exists. The walk IS the answer; STATE.md acknowledges this is the highest-probability project-blocking risk. Falsification fallback (label thinning) is documented in deferred-items.
- **Pitfalls:** HIGH — every pitfall is verified against either the source or a known platform-level behaviour (iOS Documents iCloud-backing, geolocator background pause with whenInUse).
- **Code examples:** HIGH — every snippet uses constructor signatures verbatim from the local pub-cache source.

**Research date:** 2026-05-01
**Valid until:** 2026-06-01 (30 days — stack is on stable, version-pinned releases; the flutter_map ecosystem moves slowly on the 7.x line).
