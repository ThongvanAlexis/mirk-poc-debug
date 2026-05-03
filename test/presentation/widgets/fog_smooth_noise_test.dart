// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

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

/// FOG-11 — `_FogPainter.paint()` forwards a smoothly-evolving
/// `pixelOrigin` argument to `shaderRenderer.render(...)` across a
/// sequence of small programmatic `MapController.move(...)` calls.
///
/// Catches the SHADER-MODULO-WRAP failure mode from 03.1-FALSIFICATION.md
/// observation 2 (developer's "seed of the mirk was changing"). Pre-fix
/// HEAD `5c63197` (Plan 03.1-02 fix in place but pre-Plan-03.1-04 modulo)
/// FAILS this test — the Dart call site's `% 1.0` produces 0.9999→0.0001
/// jumps across consecutive paints at the wrap boundary, AND the captured
/// magnitude lives in normalised [0, 1) space. Post-fix HEAD PASSES —
/// pixelOrigin is full-precision and monotonic.
///
/// Higher-fidelity gate than FOG-09 (which is binary "moved at all?"):
/// FOG-11 asserts CONTINUOUS evolution. Both run on every CI push.
void main() {
  group('FOG-11 (Plan 03.1-04 keystone)', () {
    testWidgets('pixelOrigin evolves smoothly across small consecutive pans (no modulo-wrap discontinuity)', (tester) async {
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
                options: const MapOptions(initialCenter: LatLng(48.5397, 2.6553), initialZoom: 13),
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

      // Sequence of 10 small moves, each ~11 m (~3 raw pixels at zoom 13).
      // Pre-Plan-03.1-04 the Dart call site's `% 1.0` would produce
      // ~size.width-magnitude jumps across the wrap boundary; Plan
      // 03.1-04..12 forwarded full-precision pixelOrigin (then bounded
      // pixel composite under FOG-17a). Plan 03.1-14 Fix B′ flipped the
      // semantic to METER space: the painter forwards
      // `(intMeters % kPocFogIntegerWrapPeriodMeters) + fracMeters` —
      // bounded under 4097 m regardless of zoom × lat. Consecutive
      // values during a smooth pan are sub-meter to single-digit-meter
      // deltas at the Walk #4 hike regime.
      final captureds = <(double, double)>[];
      for (var i = 0; i < 10; i++) {
        mapController.move(LatLng(48.5397 + i * 0.0001, 2.6553 + i * 0.0001), 13);
        await _settleSdf(tester);
        final painter = _findFogPainter(tester);
        painter.paint(_MockCanvas(), const Size(400, 800));
        captureds.add(renderer.renders.last.worldMetersOrigin);
      }

      // Assert every consecutive-paint delta is below the threshold.
      // Plan 03.1-14 Fix B′ — meter-space bounded composite. The active
      // ceiling [kPocFogSmoothMetersMaxDelta] = 4097 m bounds wrap-event
      // magnitudes; smooth-pan deltas are sub-meter at hike regime.
      for (var i = 1; i < captureds.length; i++) {
        final dx = (captureds[i].$1 - captureds[i - 1].$1).abs();
        final dy = (captureds[i].$2 - captureds[i - 1].$2).abs();
        expect(
          dx,
          lessThan(kPocFogSmoothMetersMaxDelta),
          reason:
              'FOG-11 regression at step $i: worldMetersOrigin.x jumped by $dx m (threshold $kPocFogSmoothMetersMaxDelta m). '
              'Plan 03.1-14 Fix B′: a smooth pan produces sub-meter to single-digit-meter deltas; only a wrap event '
              '(every 4096 m of camera meter-space pan) approaches the threshold.',
        );
        expect(dy, lessThan(kPocFogSmoothMetersMaxDelta), reason: 'FOG-11 regression at step $i: worldMetersOrigin.y jumped by $dy m.');
      }

      // Plan 03.1-14 Fix B′ bounded-magnitude regime: the painter
      // forwards `(intMeters % kPocFogIntegerWrapPeriodMeters) +
      // fracMeters`, which lives in [0, kPocFogIntegerWrapPeriodMeters].
      // This range catches BOTH:
      // - pre-fix-style millions (would FAIL upper bound)
      // - naive `% 1.0` regressions (under 1 would FAIL lower bound)
      expect(
        captureds.last.$1,
        inExclusiveRange(0, kPocFogIntegerWrapPeriodMeters + 1),
        reason:
            'FOG-11 magnitude regression: Plan 03.1-14 Fix B′ bounded-magnitude regime — '
            'forwarded value is `(intMeters % kPocFogIntegerWrapPeriodMeters) + fracMeters ∈ [0, kPocFogIntegerWrapPeriodMeters]` '
            '(meter space). Pre-Plan-03.1-14 the painter forwarded a pixel-space bounded composite under 1537 raw px '
            '(superseded). Pre-Plan-03.1-04 the Dart call site applied `% 1.0` and produced values < 1.',
      );

      // Plan 03.1-12 FOG-18 — metersPerPixel range assertion.
      // At zoom 8 lat 0° (worst-case zoomed-out at equator) ≈ 611 m/raw_px.
      // At zoom 19 lat 80° (worst-case zoomed-in at high-lat) ≈ 0.034 m/raw_px.
      // The (0.01, 200) range covers every reasonable zoom × lat regime
      // for the POC's operating envelope; failing this assertion
      // indicates a missing forward-call OR a hardcoded-zero regression
      // at the painter level.
      final mpp = renderer.renders.last.metersPerPixel;
      expect(
        mpp,
        inExclusiveRange(0.01, 200.0),
        reason:
            'FOG-18 metersPerPixel regression: post-Plan-03.1-12 the painter forwards a non-zero '
            'metersPerPixel computed via kWebMercatorMetersPerPxAtEquatorZ0 * cos(lat) / pow(2, zoom). '
            'At zoom 8 lat 0° (worst case zoomed-out) metersPerPixel ≈ 611 m/raw_px; at zoom 19 lat 80° '
            '(worst case zoomed-in) metersPerPixel ≈ 0.034 m/raw_px. The (0.01, 200) range covers every '
            'reasonable zoom × lat regime; failing this assertion indicates a missing forward-call. '
            'Got: $mpp.',
      );
    });
  });
}

/// Resolves the SDF cache's async future via the real event loop —
/// `tester.pump()` alone advances microtasks but the SDF builder uses
/// `ui.decodeImageFromPixels(..., Completer.complete)` which needs a
/// platform tick. Same pattern as FOG-09 keystone in fog_pan_translation_test.dart.
Future<void> _settleSdf(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump();
}

/// Re-locates the `_FogPainter` underneath the `FogLayer` widget on every
/// rebuild — `_FogPainter` is private, cast to public `CustomPainter`.
/// Same idiom as FOG-09 keystone helper.
CustomPainter _findFogPainter(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(find.descendant(of: find.byType(FogLayer), matching: find.byType(CustomPaint)));
  final painter = customPaint.painter;
  if (painter == null) {
    fail('Expected FogLayer descendant CustomPaint to carry a non-null `painter`; got null.');
  }
  return painter;
}

/// Minimal Canvas fake — overrides only what `_FogPainter.paint()` calls.
/// `getTransform()` returns identity (Plan 03.1-05 will rely on a
/// non-identity transform; Plan 03.1-04's FOG-11 test is identity-only
/// because the modulo-wrap failure mode is independent of canvas
/// translation per 03.1-FALSIFICATION.md hypothesis triage).
class _MockCanvas extends Fake implements Canvas {
  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {}

  /// Plan 03.1-08 (FOG-13) — `_FogPainter.paint()` now calls
  /// `canvas.translate(-canvasOffset.dx, -canvasOffset.dy)` after the
  /// clipPath. The mock accepts the call as a no-op; this test asserts on
  /// pixelOrigin tuple values forwarded to the renderer (NOT on canvas
  /// transform stack), so the translate is irrelevant to the assertion.
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
