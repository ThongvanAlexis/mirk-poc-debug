// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show File;
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

/// FOG-19 (Plan 03.1-14 Fix B′) — Dart-side meter-space integer/fractional
/// decomposition of `camera.pixelOrigin × metersPerPixel` keeps the shader
/// input bounded under `kPocFogIntegerWrapPeriodMeters + 1` (= 4097 m)
/// regardless of zoom level.
///
/// **Plan 03.1-14 (Fix B′) re-write:** flipped from FOG-17a pixel-space
/// decomposition assertions to FOG-19 meter-space decomposition
/// assertions. File name preserved for git-history continuity. Pre-Plan-
/// 03.1-14 sub-tests retained as `@Tags(['historical'])` skipped sub-tests
/// for git-history regression-defense (catches accidental revert to
/// pixel-space decomposition).
///
/// ## What's asserted (post-Plan-03.1-14)
///
/// 1. STATIC constant invariant: `kPocFogIntegerWrapPeriodMeters %
///    kPocFogNoiseTilePxMeters == 0` (4096 = 4 × 1024). Ensures the wrap
///    event lands at an integer multiple of the noise tile period in
///    METER space → wrap injects exactly 4 integer cells in noiseUv.
/// 2. STATIC source invariant: `_FogPainter.paint()` contains the
///    `kPocFogIntegerWrapPeriodMeters` reference (mechanical regression
///    defense).
/// 3. BEHAVIOURAL: at zoom 15 lat 48.5° via `mapController.move()`, the
///    forwarded `worldMetersOrigin` tuple has `|x| <=
///    kPocFogIntegerWrapPeriodMeters + 1` AND `|y| <=
///    kPocFogIntegerWrapPeriodMeters + 1`.
/// 4. NUMERICAL: a unit-test of the meter-space decomposition math via a
///    pure helper that mirrors `_FogPainter.paint()` produces:
///    - bounded magnitudes for synthetic Walk #2 (4.26M raw px × mpp) +
///      extrapolated zoom-19 (17.04M raw px × mpp) inputs;
///    - exact fractional preservation for boundary cases.
void main() {
  group('FOG-19 (Plan 03.1-14 Fix B′) — Dart-side meter-space integer/fractional decomposition', () {
    test('STATIC: kPocFogIntegerWrapPeriodMeters is an integer multiple of kPocFogNoiseTilePxMeters', () {
      // 4096 = 4 × 1024. Documented invariant pinning the wrap event to
      // an exact noise-grid boundary in METER space → +4 integer-cell
      // shift in noiseUv at every wrap event.
      expect(
        kPocFogIntegerWrapPeriodMeters % kPocFogNoiseTilePxMeters,
        equals(0.0),
        reason:
            'FOG-19 invariant: kPocFogIntegerWrapPeriodMeters ($kPocFogIntegerWrapPeriodMeters) MUST be an integer '
            'multiple of kPocFogNoiseTilePxMeters ($kPocFogNoiseTilePxMeters). 4096 / 1024 = 4. '
            'If this assertion fails, the integer-wrap event no longer lands at an exact noise-grid boundary in '
            'meter space and the period-commensurability gap that Walk #5 surfaced would re-open.',
      );

      // Documented numerical check: 4096.0 / 1024.0 = 4.0 exactly.
      expect(kPocFogIntegerWrapPeriodMeters / kPocFogNoiseTilePxMeters, equals(4.0));
    });

    test('STATIC source: _FogPainter.paint() contains the kPocFogIntegerWrapPeriodMeters meter-space decomposition', () {
      final source = File('lib/presentation/widgets/fog_layer.dart').readAsStringSync();
      expect(
        source,
        contains('kPocFogIntegerWrapPeriodMeters'),
        reason:
            'Plan 03.1-14 Fix B′ static-source invariant: _FogPainter.paint() must reference '
            'kPocFogIntegerWrapPeriodMeters (the meter-space integer/fractional decomposition modulo divisor). '
            'If this assertion fails, the Plan 03.1-14 Fix B′ has been reverted.',
      );
      expect(
        source,
        contains('truncateToDouble()'),
        reason:
            'Plan 03.1-14 Fix B′ static-source invariant: _FogPainter.paint() must call truncateToDouble() to split worldMeters into integer + fractional parts.',
      );
    });

    test('NUMERICAL: synthetic Walk #2 magnitude (4.26M raw px) at z=15 lat 48.5° decomposes to bounded meter composite', () {
      const lat = kPocInitialCameraLat;
      const z = 15.0;
      final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, z).toDouble();
      const inX = 4_260_000.0;
      const inY = 1_700_000.0;
      final composite = _decomposeMeters(inX, inY, mpp);
      expect(
        composite.$1.abs(),
        lessThanOrEqualTo(kPocFogIntegerWrapPeriodMeters + 1),
        reason: 'Plan 03.1-14 Fix B′ regression: bounded meter composite must stay <= kPocFogIntegerWrapPeriodMeters + 1 (= 4097 m). Got: ${composite.$1}',
      );
      expect(composite.$2.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodMeters + 1));
    });

    test('NUMERICAL: extrapolated zoom-19 magnitude (17.04M raw px) at z=19 lat 48.5° decomposes to bounded meter composite', () {
      const lat = kPocInitialCameraLat;
      const z = 19.0;
      final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, z).toDouble();
      const inX = 17_040_000.0;
      const inY = 4_260_000.0;
      final composite = _decomposeMeters(inX, inY, mpp);
      expect(composite.$1.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodMeters + 1));
      expect(composite.$2.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodMeters + 1));
    });

    test('NUMERICAL: small-magnitude meter boundary (4096.5 m, 1024.25 m) preserves fractional remainder exactly', () {
      // Synthetic worldMeters values (no mpp multiplication needed —
      // simulate decomposition directly).
      final composite = _decomposeMetersDirect(4096.5, 1024.25);
      // 4096.0 % 4096.0 = 0; + 0.5 = 0.5
      expect(composite.$1, closeTo(0.5, 1e-9));
      // 1024.0 % 4096.0 = 1024; + 0.25 = 1024.25
      expect(composite.$2, closeTo(1024.25, 1e-9));
    });

    testWidgets('BEHAVIOURAL: forwarded worldMetersOrigin tuple is bounded after zoom-15 pan', (tester) async {
      // At zoom 15 (kPocMaxZoom), Melun pixelOrigin × mpp produces
      // worldMetersX in the millions. The post-Plan-03.1-14 painter
      // applies the meter-space decomposition; the tuple forwarded to
      // shaderRenderer.render() must be bounded.
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
                options: const MapOptions(initialCenter: LatLng(48.5397, 2.6553), initialZoom: 15),
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
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      final painter = _findFogPainter(tester);
      painter.paint(_MockCanvas(), const Size(400, 800));
      expect(renderer.renders, isNotEmpty, reason: 'paint() must run through the renderer.');
      final forwarded = renderer.renders.last.worldMetersOrigin;
      expect(
        forwarded.$1.abs(),
        lessThanOrEqualTo(kPocFogIntegerWrapPeriodMeters + 1),
        reason:
            'Plan 03.1-14 Fix B′ regression: forwarded worldMetersOrigin.x (${forwarded.$1}) exceeds '
            'kPocFogIntegerWrapPeriodMeters + 1 (${kPocFogIntegerWrapPeriodMeters + 1}). '
            'The meter-space decomposition MUST bound the forwarded value. If this fails, the painter is '
            'forwarding raw pixelOrigin × mpp without the modulo.',
      );
      expect(forwarded.$2.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodMeters + 1));
    });

    testWidgets('FOG-18 (Plan 03.1-12) — recording renderer captures metersPerPixel forwarded by the painter', (tester) async {
      // At zoom 15 lat 48.5° (Walk #4 hike regime), the painter must
      // forward metersPerPixel ≈ 3.16 m/raw_px to the renderer. Defense-
      // in-depth at the painter-renderer interface boundary.
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
                options: const MapOptions(initialCenter: LatLng(48.5397, 2.6553), initialZoom: 15),
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
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      final painter = _findFogPainter(tester);
      painter.paint(_MockCanvas(), const Size(400, 800));
      expect(renderer.renders, isNotEmpty);
      final mpp = renderer.renders.last.metersPerPixel;
      const lat = 48.5397;
      final expectedMpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, 15.0).toDouble();
      expect(
        mpp,
        closeTo(expectedMpp, 0.01),
        reason:
            'FOG-18 painter forward regression: at zoom 15 lat 48.5° the painter must forward '
            'metersPerPixel ≈ $expectedMpp m/raw_px (got $mpp). If this fails, the FOG-18 metersPerPixel '
            'forward at the painter-renderer interface has been disconnected.',
      );
    });

    test('Plan 03.1-14 Fix B′ — total worldMeters product stays under documented precision-safe bound', () {
      // Plan 03.1-14 Fix B′: total worldMeters per-fragment is
      // `boundedMetersComposite + (fragUv * uResolution) * mpp`.
      // boundedComposite ≤ 4097 m; viewport-edge offset ≤ 430 × mpp.
      // At z=15 lat 48.5° (~3.16 m/raw_px): 4097 + 430 × 3.16 ≈ 5456 m.
      const lat = 48.5397;
      const viewportEdgeRawPx = 430.0;
      const maxBoundedMeters = kPocFogIntegerWrapPeriodMeters + 1.0;
      for (final z in <double>[10.0, 13.0, 15.0]) {
        final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, z).toDouble();
        final maxWorldMeters = maxBoundedMeters + viewportEdgeRawPx * mpp;
        expect(
          maxWorldMeters,
          lessThan(250_000.0),
          reason:
              'POC-operating worldMeters must stay under 250_000 m at z=$z lat=$lat (got $maxWorldMeters m). This pins the post-Plan-03.1-14 fp32 precision-safe envelope.',
        );
      }
    });
  });

  // Historical regression-defense: pre-Plan-03.1-14 pixel-space FOG-17a
  // decomposition. Skipped by default; manually unskip to verify a
  // future revert hasn't silently re-introduced the period-commensurability
  // gap.
  group('Historical: pre-Plan-03.1-14 pixel-space FOG-17a decomposition', () {
    test(
      'STATIC: kPocFogIntegerWrapPeriodPx is an integer multiple of kPocFogNoiseTilePx (1536 = 4 × 384)',
      () {
        expect(kPocFogIntegerWrapPeriodPx % kPocFogNoiseTilePx, equals(0.0));
        expect(kPocFogIntegerWrapPeriodPx / kPocFogNoiseTilePx, equals(4.0));
      },
      tags: const <String>['historical'],
      skip: 'Pre-Plan-03.1-14 pixel-space invariant retained for git-history regression-defense; not gating CI.',
    );
  });
}

/// Pure-Dart mirror of the `_FogPainter.paint()` Plan 03.1-14 Fix B′
/// meter-space decomposition (full pipeline: pxOrigin × mpp → decompose).
(double, double) _decomposeMeters(double pxX, double pxY, double mpp) {
  final wmX = pxX * mpp;
  final wmY = pxY * mpp;
  return _decomposeMetersDirect(wmX, wmY);
}

/// Pure-Dart helper — decompose worldMeters directly (skipping the
/// pxOrigin × mpp step). Used by the boundary-case test that supplies
/// synthetic worldMeters values directly.
(double, double) _decomposeMetersDirect(double wmX, double wmY) {
  final intMetersX = wmX.truncateToDouble();
  final intMetersY = wmY.truncateToDouble();
  final fracMetersX = wmX - intMetersX;
  final fracMetersY = wmY - intMetersY;
  final boundedMetersX = (intMetersX % kPocFogIntegerWrapPeriodMeters) + fracMetersX;
  final boundedMetersY = (intMetersY % kPocFogIntegerWrapPeriodMeters) + fracMetersY;
  return (boundedMetersX, boundedMetersY);
}

/// Re-locates the `_FogPainter` underneath the `FogLayer` widget on every
/// rebuild — `_FogPainter` is private, so the test casts to the public
/// `CustomPainter` interface and invokes `paint(canvas, size)` directly.
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
