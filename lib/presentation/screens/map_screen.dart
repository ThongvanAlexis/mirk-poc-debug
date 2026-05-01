// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

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
import 'package:mirk_poc_debug/presentation/widgets/blue_dot_marker.dart';
import 'package:mirk_poc_debug/presentation/widgets/fps_counter_overlay.dart';
import 'package:mirk_poc_debug/presentation/widgets/map_compass.dart';
import 'package:mirk_poc_debug/presentation/widgets/poc_app_bar.dart';
import 'package:mirk_poc_debug/presentation/widgets/recenter_fab.dart';

/// The Phase 2 walkable map screen (route `/map`).
///
/// Renders the bundled `Fra_Melun.pmtile` archive via flutter_map +
/// vector_map_tiles + `ProtomapsThemes.lightV3()`, with a GPS-driven blue
/// dot, an always-visible compass (top-right, under the FPS counter), and
/// a Material recenter FAB (bottom-right). Layout matches `02-CONTEXT.md`
/// Decisions section.
///
/// Lifecycle invariants:
///   - PMTiles file already on disk by the time this screen mounts (the
///     gate screen's `_ensureMapDataAndNavigate` copy hook from Plan 02-02
///     guarantees this; Pitfall 6).
///   - Position stream subscribed exactly once (initState), cancelled in
///     dispose (Pitfall 5).
///   - PmTilesArchive opened in initState, closed in dispose (Pitfall 2 —
///     file-handle leak prevention).
///   - `dispose()` is synchronous (Flutter contract); the `cancel()` and
///     `close()` Futures are fire-and-forget — see [_MapScreenState.dispose]
///     for the rationale.
///   - Theme built ONCE via `late final` (RESEARCH §Anti-patterns — NOT
///     per-build).
class MapScreen extends StatefulWidget {
  /// Test / DI constructor — accepts a [MapScreenServices] value object so
  /// tests can pump fakes (synthetic stream, on-disk PMTiles temp file).
  /// Production path is the same constructor: the router's `/map` builder
  /// resolves the live PMTiles path + binds `GeolocatorService.stream` and
  /// passes the resulting [MapScreenServices] here.
  const MapScreen.fromServices(this.services, {super.key});

  /// Constructor-injected services (PMTiles path + GPS stream factory +
  /// optional logger override).
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

  final MapController _mapController = MapController();
  late final vtr.Theme _theme;
  Position? _lastFix;
  StreamSubscription<Position>? _positionSubscription;
  PmTilesVectorTileProvider? _tileProvider;

  Logger get _log => widget.services.logger ?? _defaultLogger;

  @override
  void initState() {
    super.initState();
    // Built ONCE; per-build allocation is a documented anti-pattern in
    // RESEARCH §Anti-patterns (rebuild churn dominates frame budget at z15).
    _theme = ProtomapsThemes.lightV3();
    _subscribeToPositions();
    unawaited(_loadTileProvider());
  }

  void _subscribeToPositions() {
    _positionSubscription = widget.services.positionStreamFactory().listen((Position fix) {
      if (!mounted) return;
      setState(() => _lastFix = fix);
      _log.info('Fix: ${fix.latitude.toStringAsFixed(5)}, ${fix.longitude.toStringAsFixed(5)} ±${fix.accuracy.toStringAsFixed(0)}m');
    }, onError: (Object e, StackTrace st) => _log.warning('Position stream error', e, st));
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
    // The Future-returning cancel/close calls are fire-and-forget — they
    // release their underlying resources as soon as the call lands; the
    // returned Future merely signals completion of any final cleanup,
    // which we don't gate on. Awaiting here would NOT make this safer
    // (the framework still wouldn't wait), it would only make a future
    // regression to async dispose less visible.
    unawaited(_positionSubscription?.cancel() ?? Future<void>.value());
    _positionSubscription = null;
    unawaited(_tileProvider?.archive.close() ?? Future<void>.value());
    _tileProvider = null;
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
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
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
        ],
      ),
    );
  }
}
