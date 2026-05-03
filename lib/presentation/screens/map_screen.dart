// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
// `Theme` is exported from BOTH material.dart (Material's InheritedWidget) and
// vector_tile_renderer (the rendering style descriptor used by vector_map_tiles).
// Prefix the renderer import so the type used by VectorTileLayer.theme reads
// `vtr.Theme` and never collides with Material's Theme below.
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/map/map_screen_services.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/shader/digit_atlas_builder.dart';
import 'package:mirk_poc_debug/presentation/widgets/blue_dot_marker.dart';
import 'package:mirk_poc_debug/presentation/widgets/debug_spiral_layer.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';
import 'package:mirk_poc_debug/presentation/widgets/fps_counter_overlay.dart';
import 'package:mirk_poc_debug/presentation/widgets/frame_delta_probe_overlay.dart';
import 'package:mirk_poc_debug/presentation/widgets/map_compass.dart';
import 'package:mirk_poc_debug/presentation/widgets/poc_app_bar.dart';
import 'package:mirk_poc_debug/presentation/widgets/recenter_fab.dart';
import 'package:mirk_poc_debug/state/debug_spiral_state.dart';

/// The Phase 2+3 walkable map screen (route `/map`).
///
/// Renders the bundled `Fra_Melun.pmtile` archive via flutter_map +
/// vector_map_tiles + `ProtomapsThemes.lightV3()`, with a GPS-driven blue
/// dot, an always-visible compass (top-right, under the FPS counter), the
/// Phase 3 fog of war (FogLayer rendered as a child of the same FlutterMap —
/// FOG-04 same-Canvas keystone), the frame-delta probe overlay (FOG-08), and
/// a Material recenter FAB (bottom-right). Layout matches `02-CONTEXT.md` +
/// `03-CONTEXT.md` Decisions sections.
///
/// ## Phase 3 wiring (Plan 03-07)
///
///   - **FOG-01**: every GPS fix appends a 25 m disc to
///     `services.discRepository`. The hand-rolled disc ID is
///     `rvd_<microsSinceEpoch>_<randomU32>_<counter>` per RESEARCH §Open
///     Question 4 (no `ulid` dependency).
///   - **FOG-04**: the `FogLayer` mounts inside the FlutterMap children list,
///     between the `VectorTileLayer` and the blue-dot `CircleLayer`. The
///     same-Canvas paint is the architectural answer to BUG-014 (parallel
///     layers fall behind by exactly one frame).
///   - **FOG-08**: `FrameDeltaProbeOverlay` sits at
///     `top:kPocFrameDeltaProbeOverlayTopPx (104)`,
///     `right:kPocFrameDeltaProbeOverlayRightPx (8)` — directly below the
///     FpsCounterOverlay (top:8) + MapCompass (top:56) cluster.
///
/// ## Lifecycle invariants
///
///   - PMTiles file already on disk by mount time (gate-screen guarantee).
///   - Position stream subscribed exactly once (initState), cancelled in
///     dispose (Pitfall 5).
///   - PmTilesArchive opened in initState, closed in dispose (Pitfall 2 —
///     file-handle leak prevention).
///   - `FrameDeltaProbe.start()` called in initState; `dispose()`
///     fire-and-forget in `dispose()` (Future-returning).
///   - `SdfCache` + `SdfRebuildLogger` constructed in initState, both
///     released in dispose.
///   - Fog shader loaded async via `ui.FragmentProgram.fromAsset(
///     kPocFogShaderAssetPath)`; on failure the FogLayer simply does not
///     mount (graceful degradation — the pre-walk `/sanity` smoke test +
///     03-FALSIFICATION.md Plan 03-08 gate catches a broken shader before
///     sideload).
///   - `dispose()` is synchronous (Flutter contract); the Future-returning
///     cancel/close calls are fire-and-forget — see [_MapScreenState.dispose]
///     for rationale.
///   - Theme built ONCE via `late final` (RESEARCH §Anti-patterns — NOT
///     per-build).
class MapScreen extends StatefulWidget {
  /// Test / DI constructor — accepts a [MapScreenServices] value object so
  /// tests can pump fakes (synthetic stream, on-disk PMTiles temp file,
  /// in-memory disc repository, no-op probe).
  const MapScreen.fromServices(this.services, {super.key});

  /// Constructor-injected services (PMTiles path + GPS stream factory +
  /// reveal-disc repository + frame-delta probe + optional logger override).
  final MapScreenServices services;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Compass overlay sits 8 px below the FpsCounterOverlay (top: 8, height
  // ~40 px including padding) — 8 + ~40 + 8 = 56.
  static const double _compassTopPx = 56;
  static const double _overlayRightPx = 8;
  static const double _fpsTopPx = 8;

  static final Logger _defaultLogger = Logger('presentation.map');

  /// Random source for the disc-ID `randomU32` slot. Single instance per
  /// screen so we don't pay `Random()` initialisation per fix.
  final Random _random = Random();

  final MapController _mapController = MapController();
  late final vtr.Theme _theme;
  Position? _lastFix;
  StreamSubscription<Position>? _positionSubscription;
  PmTilesVectorTileProvider? _tileProvider;

  // Phase 3 state.
  ui.FragmentShader? _fogShader;
  SdfCache? _sdfCache;
  SdfRebuildLogger? _sdfRebuildLogger;

  // Plan 03.1-08-FIX FIX 2 — debug-spiral diagnostic state. Lazy-loaded
  // on first toggle ON so the production cold-start path (toggle OFF)
  // does NOT pay the ~30-50 ms digit-atlas rasterization cost. Both
  // `_debugSpiralShader` and `_debugSpiralAtlas` stay null until the
  // user flips the toggle ON; afterwards they remain loaded for the
  // screen lifetime so subsequent toggle flips are instant.
  ui.FragmentShader? _debugSpiralShader;
  ui.Image? _debugSpiralAtlas;
  bool _debugSpiralLoadInFlight = false;

  /// Per-screen-lifetime monotonically incrementing counter folded into the
  /// disc ID so two fixes within the same microsecond still produce distinct
  /// IDs (defence-in-depth — the ulid replacement contract).
  int _discCounter = 0;

  Logger get _log => widget.services.logger ?? _defaultLogger;

  @override
  void initState() {
    super.initState();
    // Built ONCE; per-build allocation is a documented anti-pattern in
    // RESEARCH §Anti-patterns (rebuild churn dominates frame budget at z15).
    _theme = ProtomapsThemes.lightV3();
    _sdfRebuildLogger = SdfRebuildLogger()..start();
    _sdfCache = SdfCache(rebuildLogger: _sdfRebuildLogger!);
    widget.services.frameDeltaProbe.start();
    widget.services.fogTransformLogger.start();
    _subscribeToPositions();
    unawaited(_loadTileProvider());
    unawaited(_loadFogShader());
    // Plan 03.1-08-FIX FIX 2 — listen to the global debug-spiral toggle.
    // When the user flips ON for the first time, kick off the lazy load
    // of the debug shader + digit atlas. The notifier listener fires on
    // every flip; the load is idempotent via the `_debugSpiralLoadInFlight`
    // guard + the `_debugSpiralShader != null` short-circuit.
    debugSpiralEnabled.addListener(_onDebugSpiralToggleChanged);
    if (debugSpiralEnabled.value) {
      // If the user already flipped the toggle on /sanity before
      // navigating to /map, kick the load right away so the spiral
      // appears as soon as the tile provider resolves.
      unawaited(_loadDebugSpiralAssetsIfNeeded());
    }
  }

  /// Plan 03.1-08-FIX FIX 2 — reacts to the global [debugSpiralEnabled]
  /// notifier flipping. On flip-ON triggers the lazy load (idempotent;
  /// reuses cached assets). On flip-OFF does nothing — the cached
  /// shader/atlas live until screen dispose. `setState` triggers a
  /// rebuild so the layer swap takes effect.
  void _onDebugSpiralToggleChanged() {
    if (!mounted) return;
    if (debugSpiralEnabled.value) {
      unawaited(_loadDebugSpiralAssetsIfNeeded());
    } else {
      // OFF — production fog renders. Just rebuild to swap layer back.
      setState(() {});
    }
  }

  /// Lazy-loads `atmospheric_fog_debug_spiral.frag` + the digit atlas.
  /// Idempotent (returns early if already loaded or load in flight).
  /// First call triggers ~30-50 ms of async work (atlas rasterization
  /// dominates); subsequent calls are O(1).
  ///
  /// Test seam: when `services.fogProgramLoaderOverride` is non-null
  /// (the same override used by the production fog shader), reuses the
  /// override here so widget tests can supply a never-completing future
  /// to keep the load pending. The override does not distinguish between
  /// production and debug paths — tests that need to assert the
  /// debug-spiral asset path can do so by inspecting the path argument
  /// passed to a custom override.
  Future<void> _loadDebugSpiralAssetsIfNeeded() async {
    if (_debugSpiralShader != null && _debugSpiralAtlas != null) return;
    if (_debugSpiralLoadInFlight) return;
    _debugSpiralLoadInFlight = true;
    try {
      // Use the same loader override as the production fog so widget
      // tests can keep the load pending without diverging the test seam.
      final loader = widget.services.fogProgramLoaderOverride ?? () => ui.FragmentProgram.fromAsset(kPocDebugSpiralShaderAssetPath);
      final program = await loader();
      if (!mounted) return;
      final atlas = await DigitAtlasBuilder.atlas;
      if (!mounted) return;
      setState(() {
        _debugSpiralShader = program.fragmentShader();
        _debugSpiralAtlas = atlas;
      });
    } on Object catch (e, st) {
      _log.severe('Failed to load debug-spiral shader/atlas (Plan 03.1-08-FIX FIX 2)', e, st);
    } finally {
      _debugSpiralLoadInFlight = false;
    }
  }

  void _subscribeToPositions() {
    _positionSubscription = widget.services.positionStreamFactory().listen((Position fix) {
      if (!mounted) return;
      setState(() => _lastFix = fix);
      _log.info('Fix: ${fix.latitude.toStringAsFixed(5)}, ${fix.longitude.toStringAsFixed(5)} ±${fix.accuracy.toStringAsFixed(0)}m');
      // FOG-01: every fix → 25 m disc appended to the in-memory repository.
      // FogLayer (via discRepository.addListener) picks up the change on its
      // next build, the SDF cache busts on the new hash, the new disc joins
      // the analytic SDF, and the next paint reveals the new spot.
      _discCounter++;
      widget.services.discRepository.append(
        RevealDisc(
          id: _handRolledDiscId(),
          sessionId: kPocPlaceholderSessionId,
          lat: fix.latitude,
          lon: fix.longitude,
          radiusMeters: kPocRevealDiscRadiusMeters,
          fixedAtUtc: DateTime.now().toUtc(),
        ),
      );
    }, onError: (Object e, StackTrace st) => _log.warning('Position stream error', e, st));
  }

  /// Hand-rolled disc ID per RESEARCH §Open Question 4 — no `ulid` dep.
  ///
  /// Format: `rvd_<microsSinceEpoch>_<randomU32>_<counter>`. The triple
  /// (timestamp, random u32, monotonic counter) makes a within-process
  /// collision impossible during a 5-minute walk (~50 fixes); the prefix
  /// matches the parent project's `RevealDisc.id` convention.
  String _handRolledDiscId() {
    final r = _random.nextInt(_discIdRandomU32Modulus);
    final us = DateTime.now().microsecondsSinceEpoch;
    return 'rvd_${us}_${r}_$_discCounter';
  }

  /// Loads the Phase 3 fog fragment program from the asset bundle. On any
  /// failure (asset missing, malformed bytecode), logs `severe` and leaves
  /// `_fogShader` null — the FogLayer simply does not mount, the user sees
  /// a no-fog map, and the pre-walk `/sanity` smoke test (Plan 03-06) +
  /// the falsification gate (Plan 03-08) prevent shipping a broken IPA.
  ///
  /// Test seam: when `services.fogProgramLoaderOverride` is non-null, the
  /// override drives the load instead of `ui.FragmentProgram.fromAsset`.
  /// Widget tests use a `Completer<ui.FragmentProgram>().future` to keep
  /// the load pending — the real platform loader hangs indefinitely in
  /// headless `flutter test` (same constraint as `ShaderSanityScreen`).
  Future<void> _loadFogShader() async {
    try {
      final loader = widget.services.fogProgramLoaderOverride ?? () => ui.FragmentProgram.fromAsset(kPocFogShaderAssetPath);
      final program = await loader();
      if (!mounted) return;
      setState(() => _fogShader = program.fragmentShader());
    } on Object catch (e, st) {
      _log.severe('Failed to load fog shader (Pitfall 3 — pre-walk /sanity should have caught this)', e, st);
    }
  }

  Future<void> _loadTileProvider() async {
    try {
      final provider = await PmTilesVectorTileProvider.fromSource(widget.services.pmtilesPath);
      if (!mounted) {
        // Same fire-and-forget shape as dispose: if the screen unmounted
        // while we were loading, close the just-opened archive without
        // awaiting (we are already past the build path).
        unawaited(provider.archive.close());
        return;
      }
      setState(() => _tileProvider = provider);
    } on Object catch (e, st) {
      // Stays on the loading state — the user sees a grey rect. Acceptable
      // POC fallback; real failure should already have been caught at the
      // gate screen's ensureCopied call (Plan 02-02).
      _log.severe('Failed to open PmTiles archive', e, st);
    }
  }

  @override
  void dispose() {
    // Synchronous void dispose (Flutter contract: framework never awaits).
    // The Future-returning cancel/close/dispose calls are fire-and-forget —
    // they release their underlying resources as soon as the call lands; the
    // returned Future merely signals completion of any final cleanup, which
    // we don't gate on. Awaiting here would NOT make this safer (the
    // framework still wouldn't wait), it would only make a future regression
    // to async dispose less visible.
    debugSpiralEnabled.removeListener(_onDebugSpiralToggleChanged);
    unawaited(_positionSubscription?.cancel() ?? Future<void>.value());
    _positionSubscription = null;
    unawaited(_tileProvider?.archive.close() ?? Future<void>.value());
    _tileProvider = null;
    _sdfCache?.dispose();
    _sdfCache = null;
    _sdfRebuildLogger?.stop();
    _sdfRebuildLogger = null;
    widget.services.fogTransformLogger.stop();
    unawaited(widget.services.frameDeltaProbe.dispose());
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildPocAppBar(context),
      floatingActionButton: RecenterFab(mapController: _mapController, lastFix: _lastFix),
      body: Stack(
        children: <Widget>[
          if (_tileProvider == null)
            ColoredBox(color: Colors.grey[850]!, child: const SizedBox.expand())
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(kPocInitialCameraLat, kPocInitialCameraLon),
                initialZoom: kPocInitialZoom,
                minZoom: kPocMinZoom,
                maxZoom: kPocMaxZoom,
                cameraConstraint: CameraConstraint.contain(
                  bounds: LatLngBounds(
                    const LatLng(kPocBboxLatMin - kPocPanBoundsPadDegrees, kPocBboxLonMin - kPocPanBoundsPadDegrees),
                    const LatLng(kPocBboxLatMax + kPocPanBoundsPadDegrees, kPocBboxLonMax + kPocPanBoundsPadDegrees),
                  ),
                ),
                // UX-02 (Plan 03.1-10) — disable two-finger rotation gestures so MobileLayerTransformer
                // never accumulates rotation matrix elements (matrix[0,1,4,5]) in the canvas transform.
                // Walk #3 (Plan 03.1-09 sub-section C) surfaced rotation-correlated fog mis-coverage:
                // Plan 03.1-08's `canvas.translate(-canvasOffset)` compensates only translation; rotation
                // remains uncompensated, leaving wedges of un-fogged map at viewport corners during
                // pinch-zoom-rotate. Disabling rotation is the developer-endorsed POC scope reduction
                // per Walk #3 Q2 verbatim ("disable rotation for now, only pan and zoom, north is up.
                // simplier"). FOG-16 path (b) full canvas-inverse-transform stays deferred to
                // hypothetical post-POC iteration. The MapCompass widget is RETAINED — it always
                // displays 0° (north up); leaving it in place is harmless and provides a visual
                // confirmation that rotation is locked.
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: <Widget>[
                VectorTileLayer(
                  tileProviders: TileProviders(<String, VectorTileProvider>{
                    // RESEARCH §Pitfall 3: source key MUST equal the source
                    // name baked into ProtomapsThemes.lightV3() (literal
                    // 'protomaps' — see kPocTileProviderSourceKey).
                    kPocTileProviderSourceKey: _tileProvider!,
                  }),
                  theme: _theme,
                  // layerMode left at default VectorTileLayerMode.raster —
                  // best frame rate per RESEARCH §Pitfall 1.
                ),
                // FOG-04 same-Canvas keystone — FogLayer / DebugSpiralLayer
                // is a CHILD of the SAME FlutterMap as the tile layer, never
                // a sibling. Mounts only once the relevant shader load is
                // done. Order in the children list = z-order: tiles → fog →
                // blue dot.
                //
                // Plan 03.1-08-FIX FIX 2 — when the global
                // [debugSpiralEnabled] notifier is ON AND the lazy debug
                // assets resolved, render the DebugSpiralLayer instead of
                // the production FogLayer. The notifier listener
                // (_onDebugSpiralToggleChanged) calls setState on every flip
                // so this conditional re-evaluates. Production fog renders
                // unchanged when toggle is OFF.
                if (debugSpiralEnabled.value && _debugSpiralShader != null && _debugSpiralAtlas != null)
                  DebugSpiralLayer(shader: _debugSpiralShader!, atlas: _debugSpiralAtlas!)
                else if (_fogShader != null && _sdfCache != null)
                  FogLayer(
                    discRepository: widget.services.discRepository,
                    shader: _fogShader,
                    sdfCache: _sdfCache!,
                    frameDeltaProbe: widget.services.frameDeltaProbe,
                    fogTransformLogger: widget.services.fogTransformLogger,
                  ),
                if (_lastFix != null)
                  CircleLayer<Object>(circles: <CircleMarker<Object>>[BlueDotMarker.build(LatLng(_lastFix!.latitude, _lastFix!.longitude))]),
              ],
            ),
          const Positioned(top: _fpsTopPx, right: _overlayRightPx, child: FpsCounterOverlay()),
          // MapCompass.initState reads `mapController.camera.rotation`, which
          // throws "FlutterMap widget rendered at least once" before the
          // FlutterMap is mounted. Gate the compass on `_tileProvider != null`
          // so it only enters the tree after FlutterMap is in the tree on the
          // same frame. (RecenterFab is safe — it only touches the camera in
          // the user-tap handler, never in initState.)
          if (_tileProvider != null)
            Positioned(
              top: _compassTopPx,
              right: _overlayRightPx,
              child: MapCompass(mapController: _mapController),
            ),
          // FOG-08 user-facing — sits BELOW FpsCounterOverlay (top:8) and
          // MapCompass (top:56). Mounts unconditionally so the walker sees
          // "no samples yet" placeholder before the first probe rollup,
          // rather than wondering whether the overlay is wired at all.
          Positioned(
            top: kPocFrameDeltaProbeOverlayTopPx,
            right: kPocFrameDeltaProbeOverlayRightPx,
            child: FrameDeltaProbeOverlay(probe: widget.services.frameDeltaProbe),
          ),
        ],
      ),
    );
  }
}

/// Modulus for the `randomU32` slot of the hand-rolled disc ID. `Random.nextInt`
/// is exclusive on the bound; `1 << 32 == 4_294_967_296` gives the full u32
/// range `[0, 2^32)`.
const int _discIdRandomU32Modulus = 1 << 32;

/// Placeholder session ID for the POC. Phase 3 ships in-memory only with no
/// session lifecycle — every disc carries this literal so [RevealDisc.mergeWith]
/// asserts cleanly during any future compaction work, and so post-walk
/// debugging can grep the JSONL log for the POC tag.
const String kPocPlaceholderSessionId = 'poc';
