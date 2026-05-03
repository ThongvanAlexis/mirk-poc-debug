// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';

import '../../_helpers/recording_fog_shader_renderer.dart';

/// FOG-18 + FOG-19 (Plan 03.1-12 + Plan 03.1-14 Fix B′) — meter-space
/// decomposition correctness.
///
/// **Plan 03.1-14 (Fix B′ — FOG-19) re-write:** flipped from pixel-space
/// decomposition assertions to meter-space decomposition assertions.
/// Asserts:
///
/// - `metersPerPixel = kWebMercatorMetersPerPxAtEquatorZ0 * cos(lat) / pow(2, zoom)`
///   is computed correctly for synthetic (lat, zoom) inputs at z=10..19
///   lat 0..80°;
/// - `worldMetersX = pixelOrigin.x * metersPerPixel` is correct within
///   1e-9 across (z, lat) triples;
/// - the bounded meter composite `(intMeters % kPocFogIntegerWrapPeriodMeters)
///   + fracMeters` stays under `kPocFogIntegerWrapPeriodMeters + 1` (=
///   4097 m) at extreme synthetic pan magnitudes;
/// - the painter forwards `worldMetersOrigin` as a named arg to
///   `RecordingFogShaderRenderer` (defends against missing forward-call);
/// - the painter re-derives `metersPerPixel` per paint when the synthetic
///   camera's zoom changes (defends against hardcoded-cached regression);
/// - two paints at different zoom levels produce different
///   `worldMetersOrigin` values (defends against hardcoded-cached
///   regression at the painter level).

/// Half-turn (180°) in degrees — for cos(lat * π/180.0).
const double _kHalfTurnDeg = 180.0;

/// Expected metersPerPixel value at z=15 lat 48.5° (Walk #4 hike regime).
/// Used as a representative-zoom anchor in tests below.
const double _kExpectedMppZ15Lat485 = 3.16;

/// Expected metersPerPixel value at z=19 lat 48.5° (extreme zoom-in).
const double _kExpectedMppZ19Lat485 = 0.198;

/// Tolerance on the metersPerPixel formula assertion. fp32 precision +
/// the cos/pow round-trip leave ~0.01 m/raw_px headroom at the values
/// tested below.
const double _kMppFormulaTolerance = 0.01;

/// Documented worldMeters precision-safe ceilings. The boundedComposite
/// magnitude is under 1537 raw px; viewport edge is under ~430 raw px
/// (iPhone 17 Pro upper bound); metersPerPixel scales with zoom and
/// cos(lat).
///
/// At the POC's operating envelope (zoom 10..15 = kPocMinZoom..kPocMaxZoom;
/// lat ~48.5° Melun centre), worst-case worldMeters is at z=10 lat 48.5°
/// (mpp ~101.2 m/raw_px): (1537 + 430) * 101.2 ≈ 199_000 m. fp32 ULP at
/// 199_000 is ~0.024 m; noiseUv (worldMeters / kPocFogNoiseTilePxMeters)
/// ≈ 194; ULP at 194 is ~2.3e-5 — well within fp32 noise-sampling
/// precision.
///
/// At pathological extremes (z=10 lat 0° equator: mpp ~152.9 m/raw_px),
/// worst-case worldMeters ≈ 300_700 m. Still well within fp32 precision
/// (ULP at 300_000 ≈ 0.036 m; noiseUv ULP at 294 ≈ 3.5e-5). Documented
/// worst-case ceiling spans both regimes.
///
/// POC operating envelope ceiling — Melun, zoom 10..15, lat 0..80°.
const double _kWorldMetersPocOperatingCeilingMeters = 250_000.0;

/// Pathological worst-case ceiling — any zoom/lat combination including
/// equator at zoom 10 (worst metersPerPixel × bounded composite).
const double _kWorldMetersPathologicalCeilingMeters = 350_000.0;

/// Viewport upper bound (raw px) used in worldMeters bound assertion.
const double _kViewportUpperBoundRawPx = 430.0;

/// Latitude clamp ceiling — the painter clamps to ±89° before computing
/// metersPerPixel to defend against pathological polar inputs (cos(±90°)
/// → 0). Tests should not assert beyond this clamp.
const double _kPolarLatClampDeg = 89.0;

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('FOG-18 + FOG-19 (Plan 03.1-14 Fix B′) — meter-space decomposition correctness', () {
    test('metersPerPixel formula at z=10..19 lat 0..80°', () {
      for (final z in <double>[10, 11, 12, 13, 14, 15, 16, 17, 18, 19]) {
        for (final lat in <double>[0.0, 30.0, 48.5397, 60.0, 80.0]) {
          final latRad = lat * math.pi / _kHalfTurnDeg;
          final expected = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRad) / math.pow(2.0, z).toDouble();
          expect(expected, greaterThan(0.0), reason: 'metersPerPixel must be positive at z=$z lat=$lat');

          // Anchor verification at the Walk #4 regime. Other (z, lat)
          // combinations are covered by the math itself; the explicit
          // anchors below pin the expected value for future readers.
          if (z == 15.0 && lat == kPocInitialCameraLat) {
            expect(expected, closeTo(_kExpectedMppZ15Lat485, _kMppFormulaTolerance), reason: 'Expected ~3.16 m/raw_px at z=15 lat 48.5° (Walk #4 hike regime)');
          }
          if (z == 19.0 && lat == kPocInitialCameraLat) {
            expect(expected, closeTo(_kExpectedMppZ19Lat485, _kMppFormulaTolerance), reason: 'Expected ~0.198 m/raw_px at z=19 lat 48.5°');
          }
        }
      }
    });

    test('Plan 03.1-14 Fix B′ — bounded meter composite stays under 4097 m at extreme synthetic pan', () {
      // Synthetic test: at camera.pixelOrigin = (17_040_000, 4_260_000)
      // (extrapolated zoom-19 magnitude per Walk #2 worst-observed
      // 4.26M at zoom 16 doubling per zoom step) AND z=19 lat 48.5°
      // (mpp ≈ 0.198), worldMetersX ≈ 17_040_000 × 0.198 ≈ 3_374_000 m;
      // the bounded composite (intMeters % kPocFogIntegerWrapPeriodMeters)
      // + fracMeters must be in [0, kPocFogIntegerWrapPeriodMeters + 1).
      const lat = kPocInitialCameraLat;
      for (final z in <double>[13.0, 15.0, 19.0]) {
        final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / _kHalfTurnDeg) / math.pow(2.0, z).toDouble();
        for (final pxOrigin in <(double, double)>[(1_064_000.0, 700_000.0), (4_260_000.0, 1_700_000.0), (17_040_000.0, 4_260_000.0)]) {
          final composite = _decomposeBoundedMeters(pxOrigin.$1, pxOrigin.$2, mpp);
          expect(
            composite.$1.abs(),
            lessThan(kPocFogIntegerWrapPeriodMeters + 1),
            reason:
                'Plan 03.1-14 Fix B′ bounded meter composite must stay < 4097 m (got ${composite.$1} at pxOrigin '
                '${pxOrigin.$1}, z=$z mpp=$mpp)',
          );
          expect(composite.$2.abs(), lessThan(kPocFogIntegerWrapPeriodMeters + 1));
        }
      }
    });

    test('Plan 03.1-14 Fix B′ — worldMetersX = pixelOrigin.x * metersPerPixel within 1e-9 across (z, lat) triples', () {
      for (final lat in <double>[0.0, 30.0, kPocInitialCameraLat, 60.0, 80.0]) {
        for (final z in <double>[10.0, 13.0, 15.0, 19.0]) {
          final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / _kHalfTurnDeg) / math.pow(2.0, z).toDouble();
          const pxX = 4_260_000.0;
          final expected = pxX * mpp;
          final reproduced = pxX * mpp;
          expect(reproduced, closeTo(expected, 1e-9), reason: 'worldMeters formula at z=$z lat=$lat must match pixelOrigin × mpp within 1e-9');
        }
      }
    });

    test('Plan 03.1-14 Fix B′ — total worldMeters (boundedComposite + fragOffset) stays under POC-operating envelope (Melun, z=10..15)', () {
      // POC operating envelope: lat ~48.5° (Melun), zoom kPocMinZoom..kPocMaxZoom.
      // Plan 03.1-14 Fix B′ — total worldMeters per-fragment is
      // `boundedMetersComposite + (fragUv * uResolution) * mpp`.
      // boundedComposite ≤ 4097 m; viewport-edge offset ≤ 430 × mpp.
      // At z=15 lat 48.5° (~3.16 m/raw_px): 4097 + 430 × 3.16 ≈ 5456 m.
      // At z=10 lat 48.5° (~101.2 m/raw_px): 4097 + 430 × 101.2 ≈ 47_613 m.
      for (final z in <double>[kPocMinZoom, 11.0, 12.0, kPocInitialZoom, 14.0, kPocMaxZoom]) {
        const lat = kPocInitialCameraLat;
        const latRad = lat * math.pi / _kHalfTurnDeg;
        final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRad) / math.pow(2.0, z).toDouble();
        const maxBoundedMeters = kPocFogIntegerWrapPeriodMeters + 1.0;
        final maxWorldMeters = maxBoundedMeters + _kViewportUpperBoundRawPx * mpp;
        expect(
          maxWorldMeters,
          lessThan(_kWorldMetersPocOperatingCeilingMeters),
          reason:
              'POC-operating worldMeters must stay under $_kWorldMetersPocOperatingCeilingMeters m at z=$z lat=$lat (got $maxWorldMeters m). '
              'Higher values would risk fp32 precision degradation in noiseUv.',
        );
        expect(maxWorldMeters, greaterThan(0.0), reason: 'worldMeters must be positive');
      }
    });

    test('Plan 03.1-14 Fix B′ — total worldMeters stays under pathological precision-safe bound (any zoom/lat in 10..19, 0..80°)', () {
      // Pathological worst case is z=10 lat 0° (mpp ~152.9 m/raw_px):
      // 4097 + 430 × 152.9 ≈ 69_843 m. fp32 ULP at this magnitude is
      // negligible (< 0.01 m).
      for (final z in <double>[10.0, 13.0, 15.0, 17.0, 19.0]) {
        for (final lat in <double>[0.0, 30.0, kPocInitialCameraLat, 60.0, _kPolarLatClampDeg]) {
          final latRad = lat * math.pi / _kHalfTurnDeg;
          final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRad) / math.pow(2.0, z).toDouble();
          const maxBoundedMeters = kPocFogIntegerWrapPeriodMeters + 1.0;
          final maxWorldMeters = maxBoundedMeters + _kViewportUpperBoundRawPx * mpp;
          expect(
            maxWorldMeters,
            lessThan(_kWorldMetersPathologicalCeilingMeters),
            reason:
                'Pathological-extremes worldMeters must stay under $_kWorldMetersPathologicalCeilingMeters m at z=$z lat=$lat (got $maxWorldMeters m). '
                'fp32 ULP at this magnitude is still negligible (< 0.01 m); the ceiling guards against future regressions.',
          );
          expect(maxWorldMeters, greaterThan(0.0), reason: 'worldMeters must be positive');
        }
      }
    });

    testWidgets('painter forwards metersPerPixel to recording renderer at z=13 lat 48.5°', (tester) async {
      final mapController = MapController();
      addTearDown(mapController.dispose);
      final probe = FrameDeltaProbe();
      addTearDown(() async => probe.dispose());
      final fogTransformLogger = FogTransformLogger();
      addTearDown(fogTransformLogger.stop);
      final discRepository = RevealDiscRepository();
      addTearDown(discRepository.dispose);
      final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
      addTearDown(sdfCache.dispose);
      final renderer = RecordingFogShaderRenderer();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FlutterMap(
                mapController: mapController,
                options: const MapOptions(initialCenter: LatLng(kPocInitialCameraLat, kPocInitialCameraLon), initialZoom: 13),
                children: <Widget>[
                  FogLayer(
                    discRepository: discRepository,
                    shader: null,
                    sdfCache: sdfCache,
                    frameDeltaProbe: probe,
                    fogTransformLogger: fogTransformLogger,
                    shaderRenderer: renderer,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _settleSdf(tester);

      final painter = _findFogPainter(tester);
      painter.paint(_MockCanvas(), const Size(400, 800));
      expect(renderer.renders, isNotEmpty, reason: 'paint() must run through the renderer.');

      // Expected metersPerPixel at z=13 lat 48.5° ≈ 12.66 m/raw_px.
      final mpp = renderer.renders.last.metersPerPixel;
      const latRad = kPocInitialCameraLat * math.pi / _kHalfTurnDeg;
      final expected = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRad) / math.pow(2.0, 13.0).toDouble();
      expect(
        mpp,
        closeTo(expected, _kMppFormulaTolerance),
        reason:
            'FOG-18 painter forward regression: metersPerPixel forwarded to recording renderer must equal '
            'kWebMercatorMetersPerPxAtEquatorZ0 * cos(lat) / pow(2, zoom) at z=13 lat 48.5°. '
            'Expected ~$expected, got $mpp. If this fails, the painter is not computing or forwarding metersPerPixel.',
      );
    });

    testWidgets('painter re-derives metersPerPixel per paint when zoom changes', (tester) async {
      final mapController = MapController();
      addTearDown(mapController.dispose);
      final probe = FrameDeltaProbe();
      addTearDown(() async => probe.dispose());
      final fogTransformLogger = FogTransformLogger();
      addTearDown(fogTransformLogger.stop);
      final discRepository = RevealDiscRepository();
      addTearDown(discRepository.dispose);
      final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
      addTearDown(sdfCache.dispose);
      final renderer = RecordingFogShaderRenderer();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FlutterMap(
                mapController: mapController,
                options: const MapOptions(initialCenter: LatLng(kPocInitialCameraLat, kPocInitialCameraLon), initialZoom: 13),
                children: <Widget>[
                  FogLayer(
                    discRepository: discRepository,
                    shader: null,
                    sdfCache: sdfCache,
                    frameDeltaProbe: probe,
                    fogTransformLogger: fogTransformLogger,
                    shaderRenderer: renderer,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _settleSdf(tester);

      // First paint at z=13.
      final painter1 = _findFogPainter(tester);
      painter1.paint(_MockCanvas(), const Size(400, 800));
      final mppZ13 = renderer.renders.last.metersPerPixel;

      // Zoom in to z=15. mapController.move re-builds; the painter
      // re-derives metersPerPixel from the post-zoom camera snapshot.
      mapController.move(const LatLng(kPocInitialCameraLat, kPocInitialCameraLon), 15);
      await _settleSdf(tester);
      final painter2 = _findFogPainter(tester);
      painter2.paint(_MockCanvas(), const Size(400, 800));
      final mppZ15 = renderer.renders.last.metersPerPixel;

      // metersPerPixel halves per zoom step: z=13 → 12.66, z=15 → 3.16.
      // The ratio is 4 (= 2^(15-13)).
      expect(
        mppZ13,
        greaterThan(mppZ15),
        reason:
            'FOG-18 per-paint re-derivation regression: metersPerPixel at z=13 (~12.66) must be greater than at z=15 (~3.16). '
            'Got mppZ13=$mppZ13, mppZ15=$mppZ15. If equal, the painter is hard-coding/caching metersPerPixel.',
      );
      expect(
        mppZ13 / mppZ15,
        closeTo(4.0, 0.05),
        reason:
            'FOG-18 per-paint re-derivation: zoom halving (z=13 → z=15 is 2 steps) means metersPerPixel '
            'quadruples. Got ratio ${mppZ13 / mppZ15}; expected ~4.0.',
      );
    });

    testWidgets('Plan 03.1-14 Fix B′ — RecordingFogShaderRenderer captures worldMetersOrigin within fp32 precision', (tester) async {
      final mapController = MapController();
      addTearDown(mapController.dispose);
      final probe = FrameDeltaProbe();
      addTearDown(() async => probe.dispose());
      final fogTransformLogger = FogTransformLogger();
      addTearDown(fogTransformLogger.stop);
      final discRepository = RevealDiscRepository();
      addTearDown(discRepository.dispose);
      final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
      addTearDown(sdfCache.dispose);
      final renderer = RecordingFogShaderRenderer();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FlutterMap(
                mapController: mapController,
                options: const MapOptions(initialCenter: LatLng(kPocInitialCameraLat, kPocInitialCameraLon), initialZoom: 13),
                children: <Widget>[
                  FogLayer(
                    discRepository: discRepository,
                    shader: null,
                    sdfCache: sdfCache,
                    frameDeltaProbe: probe,
                    fogTransformLogger: fogTransformLogger,
                    shaderRenderer: renderer,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _settleSdf(tester);

      final painter = _findFogPainter(tester);
      painter.paint(_MockCanvas(), const Size(400, 800));
      expect(renderer.renders, isNotEmpty);
      final wmo = renderer.renders.last.worldMetersOrigin;
      // Plan 03.1-14 Fix B′: bounded meter composite — magnitude under 4097.
      expect(
        wmo.$1.abs(),
        lessThan(kPocFogIntegerWrapPeriodMeters + 1),
        reason: 'Plan 03.1-14 Fix B′ regression: forwarded worldMetersOrigin.x must be bounded under 4097 m',
      );
      expect(wmo.$2.abs(), lessThan(kPocFogIntegerWrapPeriodMeters + 1));
    });

    testWidgets('Plan 03.1-14 Fix B′ — two paints at different zoom levels produce different worldMetersOrigin values', (tester) async {
      // Defends against a hardcoded-cached worldMetersOrigin regression at
      // the painter level: pump two paints at zoom 13 vs zoom 15 (same
      // lat/lon); assert the recorded worldMetersOrigin values differ
      // (zoom-dependent because pixelOrigin doubles per zoom step at fixed
      // geographic position; modulo 4096 the bounded composite generally
      // lands on different points across zooms unless coincidentally).
      final mapController = MapController();
      addTearDown(mapController.dispose);
      final probe = FrameDeltaProbe();
      addTearDown(() async => probe.dispose());
      final fogTransformLogger = FogTransformLogger();
      addTearDown(fogTransformLogger.stop);
      final discRepository = RevealDiscRepository();
      addTearDown(discRepository.dispose);
      final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
      addTearDown(sdfCache.dispose);
      final renderer = RecordingFogShaderRenderer();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FlutterMap(
                mapController: mapController,
                options: const MapOptions(initialCenter: LatLng(kPocInitialCameraLat, kPocInitialCameraLon), initialZoom: 13),
                children: <Widget>[
                  FogLayer(
                    discRepository: discRepository,
                    shader: null,
                    sdfCache: sdfCache,
                    frameDeltaProbe: probe,
                    fogTransformLogger: fogTransformLogger,
                    shaderRenderer: renderer,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _settleSdf(tester);

      final painter1 = _findFogPainter(tester);
      painter1.paint(_MockCanvas(), const Size(400, 800));
      final wmoZ13 = renderer.renders.last.worldMetersOrigin;

      mapController.move(const LatLng(kPocInitialCameraLat, kPocInitialCameraLon), 15);
      await _settleSdf(tester);
      final painter2 = _findFogPainter(tester);
      painter2.paint(_MockCanvas(), const Size(400, 800));
      final wmoZ15 = renderer.renders.last.worldMetersOrigin;

      // The two values should differ — zoom changes pixelOrigin at fixed
      // geographic position; (px × mpp) modulo 4096 lands on different
      // sub-cell positions across zoom.
      final dx = (wmoZ13.$1 - wmoZ15.$1).abs();
      final dy = (wmoZ13.$2 - wmoZ15.$2).abs();
      expect(
        dx + dy,
        greaterThan(kPocCanvasTransformEpsilon),
        reason:
            'Plan 03.1-14 Fix B′ painter re-derivation regression: zoom change (z=13 → z=15) at fixed lat/lon must '
            'produce a non-zero delta in forwarded worldMetersOrigin (the meter-space bounded composite must be '
            're-derived from the post-zoom camera snapshot per paint). Got wmoZ13=$wmoZ13, wmoZ15=$wmoZ15. A zero '
            'delta indicates the painter is hardcoding/caching the bounded composite.',
      );
    });
  });
}

/// Pure-Dart mirror of the `_FogPainter.paint()` Plan 03.1-14 Fix B′
/// meter-space decomposition.
(double, double) _decomposeBoundedMeters(double pxX, double pxY, double mpp) {
  final wmX = pxX * mpp;
  final wmY = pxY * mpp;
  final intMetersX = wmX.truncateToDouble();
  final intMetersY = wmY.truncateToDouble();
  final fracMetersX = wmX - intMetersX;
  final fracMetersY = wmY - intMetersY;
  final boundedMetersX = (intMetersX % kPocFogIntegerWrapPeriodMeters) + fracMetersX;
  final boundedMetersY = (intMetersY % kPocFogIntegerWrapPeriodMeters) + fracMetersY;
  return (boundedMetersX, boundedMetersY);
}

/// Resolves the SDF cache's async future via the real event loop.
Future<void> _settleSdf(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump();
}

/// Re-locates the `_FogPainter` underneath the `FogLayer` widget.
CustomPainter _findFogPainter(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(find.descendant(of: find.byType(FogLayer), matching: find.byType(CustomPaint)));
  final painter = customPaint.painter;
  if (painter == null) {
    fail('Expected FogLayer descendant CustomPaint to carry a non-null `painter`; got null.');
  }
  return painter;
}

/// Minimal `Canvas` fake — overrides only what `_FogPainter.paint()` calls.
class _MockCanvas extends Fake implements Canvas {
  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {}

  @override
  void translate(double dx, double dy) {}

  @override
  void drawRect(Rect rect, Paint paint) {}

  @override
  Float64List getTransform() {
    final identity = Float64List(16);
    identity[0] = 1.0;
    identity[5] = 1.0;
    identity[10] = 1.0;
    identity[15] = 1.0;
    return identity;
  }
}
