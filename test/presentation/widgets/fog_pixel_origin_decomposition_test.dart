// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show File;
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

/// FOG-17a (Plan 03.1-10) — CPU-side integer/fractional decomposition
/// of `camera.pixelOrigin` keeps the shader input bounded under
/// `kPocFogIntegerWrapPeriodPx + 1` (= 1537 raw px) regardless of zoom
/// level. Walk #2 captured pixelOriginX up to 4.26M; pure FOG-17
/// world-coordinate sampling at that magnitude exposes catastrophic
/// fp32 ULP (~0.5 raw px). The decomposition splits pixelOrigin into
/// integer + fractional Dart-side and forwards the bounded composite
/// `(intPx % kPocFogIntegerWrapPeriodPx) + fracPx`.
///
/// ## What's asserted
///
/// 1. STATIC constant invariant: `kPocFogIntegerWrapPeriodPx %
///    kPocFogNoiseTilePx == 0` (1536 = 4 × 384). Ensures the wrap event
///    lands at an integer multiple of the noise tile period so the
///    base-octave noise pattern is preserved across the wrap.
/// 2. STATIC source invariant: `_FogPainter.paint()` contains the
///    `kPocFogIntegerWrapPeriodPx` reference (mechanical regression
///    defense — if the decomposition gets reverted the substring
///    disappears).
/// 3. BEHAVIOURAL: against a synthetic Walk #2-style camera magnitude
///    via `mapController.move()` at zoom 15 (max allowed by
///    `kPocMaxZoom`; pixelOrigin reaches ~2.1M which is in the
///    bounded-magnitude regime requiring the fix), the forwarded
///    pixelOrigin tuple has `|x| ≤ kPocFogIntegerWrapPeriodPx + 1` AND
///    `|y| ≤ kPocFogIntegerWrapPeriodPx + 1`.
/// 4. NUMERICAL: a unit-test of the decomposition math itself via a
///    pure helper that mirrors `_FogPainter.paint()` produces:
///    - bounded magnitudes for synthetic Walk #2 (4.26M) + extrapolated
///      zoom-19 (17.04M) inputs;
///    - exact fractional preservation for boundary cases (1536.5 →
///      0.5; 384.25 → 384.25);
///    - sign-correct handling of negative pixelOrigin inputs.
void main() {
  group('FOG-17a (Plan 03.1-10) — CPU-side integer/fractional decomposition', () {
    test('STATIC: kPocFogIntegerWrapPeriodPx is an integer multiple of kPocFogNoiseTilePx', () {
      // 1536 = 4 * 384. Documented invariant pinning the wrap event to
      // an exact noise-grid boundary so the base-octave hash3 lattice is
      // preserved across the wrap (the FBM-rotated octaves are NOT
      // preserved — see noise-function inspection in PLAN.md).
      expect(
        kPocFogIntegerWrapPeriodPx % kPocFogNoiseTilePx,
        equals(0.0),
        reason:
            'FOG-17a invariant: kPocFogIntegerWrapPeriodPx ($kPocFogIntegerWrapPeriodPx) MUST be an integer '
            'multiple of kPocFogNoiseTilePx ($kPocFogNoiseTilePx). 1536 / 384 = 4. '
            'If this assertion fails, the integer-wrap event no longer lands at an exact noise-grid boundary '
            'and the post-wrap base-octave noise pattern would visibly discontinuity-step at every wrap.',
      );

      // Documented numerical check: 1536.0 / 384.0 = 4.0 exactly.
      expect(kPocFogIntegerWrapPeriodPx / kPocFogNoiseTilePx, equals(4.0));
    });

    test('STATIC source: _FogPainter.paint() contains the kPocFogIntegerWrapPeriodPx decomposition', () {
      final source = File('lib/presentation/widgets/fog_layer.dart').readAsStringSync();
      expect(
        source,
        contains('kPocFogIntegerWrapPeriodPx'),
        reason:
            'FOG-17a static-source invariant: _FogPainter.paint() must reference '
            'kPocFogIntegerWrapPeriodPx (the integer/fractional decomposition modulo divisor). '
            'If this assertion fails, the FOG-17a fix has been reverted.',
      );
      expect(
        source,
        contains('truncateToDouble()'),
        reason:
            'FOG-17a static-source invariant: _FogPainter.paint() must call truncateToDouble() to split '
            'pixelOrigin into integer + fractional parts.',
      );
    });

    test('NUMERICAL: synthetic Walk #2 magnitude (4.26M, 1.7M) decomposes to bounded composite', () {
      const inX = 4260000.0;
      const inY = 1700000.0;
      final composite = _decompose(inX, inY);
      expect(
        composite.$1.abs(),
        lessThanOrEqualTo(kPocFogIntegerWrapPeriodPx + 1),
        reason:
            'Walk #2 worst-observed pixelOriginX (4.26M) must decompose to a value bounded under kPocFogIntegerWrapPeriodPx + 1 (= 1537 raw px). '
            'Got: ${composite.$1}. fp32 ULP at 1536 is ~2.4e-4 raw px — three orders of magnitude better than ULP at 4.26M (~0.5 raw px).',
      );
      expect(composite.$2.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodPx + 1));
    });

    test('NUMERICAL: extrapolated zoom-19 magnitude (17.04M, 4.26M) decomposes to bounded composite', () {
      const inX = 17040000.0;
      const inY = 4260000.0;
      final composite = _decompose(inX, inY);
      expect(composite.$1.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodPx + 1));
      expect(composite.$2.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodPx + 1));
    });

    test('NUMERICAL: small-magnitude boundary (1536.5, 384.25) preserves fractional remainder exactly', () {
      // 1536.0 % 1536.0 = 0; + 0.5 = 0.5
      // 384.0  % 1536.0 = 384; + 0.25 = 384.25
      final composite = _decompose(1536.5, 384.25);
      expect(composite.$1, closeTo(0.5, 1e-9));
      expect(composite.$2, closeTo(384.25, 1e-9));
    });

    test('NUMERICAL: negative magnitudes decompose to bounded composite', () {
      // pxX = -100.0 → intPx = -100, fracPx = 0; -100 % 1536 = 1436 (Dart `%`
      // returns value in [0, divisor) for positive divisor); composite = 1436.
      // pxY = -1536.5 → intPx = -1536, fracPx = -0.5; -1536 % 1536 = 0;
      // composite = 0 + (-0.5) = -0.5.
      final composite = _decompose(-100.0, -1536.5);
      expect(composite.$1.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodPx + 1));
      expect(composite.$2.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodPx + 1));
      // Specific decomposition verification.
      expect(composite.$1, closeTo(1436.0, 1e-9), reason: '-100 % 1536 = 1436 (Dart `%` semantics); fracPx = 0.0');
      expect(composite.$2, closeTo(-0.5, 1e-9), reason: '-1536 % 1536 = 0; fracPx = -0.5; composite = -0.5');
    });

    testWidgets('BEHAVIOURAL: forwarded pixelOrigin tuple is bounded after zoom-15 pan', (tester) async {
      // At zoom 15 (kPocMaxZoom), Melun pixelOrigin reaches ~2.1M (above
      // the 1537-raw-px wrap period). The post-Plan-03.1-10 painter
      // applies the FOG-17a decomposition in Dart-side; the tuple
      // forwarded to shaderRenderer.render() must be bounded.
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
      final forwarded = renderer.renders.last.pixelOrigin;
      expect(
        forwarded.$1.abs(),
        lessThanOrEqualTo(kPocFogIntegerWrapPeriodPx + 1),
        reason:
            'FOG-17a regression: forwarded pixelOrigin.x (${forwarded.$1}) exceeds kPocFogIntegerWrapPeriodPx + 1 '
            '(${kPocFogIntegerWrapPeriodPx + 1}). At zoom 15 the raw camera.pixelOrigin reaches ~2.1M; '
            'the FOG-17a decomposition MUST bound the forwarded value. If this fails, the painter is '
            'forwarding raw pixelOrigin and the fp32 precision regression has resurfaced.',
      );
      expect(forwarded.$2.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodPx + 1));
    });
  });
}

/// Pure-Dart mirror of the `_FogPainter.paint()` decomposition.
/// Used by the NUMERICAL tests to assert the math at synthetic
/// magnitudes the FlutterMap camera-constraint cannot reach.
(double, double) _decompose(double pxX, double pxY) {
  final intPxX = pxX.truncateToDouble();
  final intPxY = pxY.truncateToDouble();
  final fracPxX = pxX - intPxX;
  final fracPxY = pxY - intPxY;
  final boundedX = (intPxX % kPocFogIntegerWrapPeriodPx) + fracPxX;
  final boundedY = (intPxY % kPocFogIntegerWrapPeriodPx) + fracPxY;
  return (boundedX, boundedY);
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
