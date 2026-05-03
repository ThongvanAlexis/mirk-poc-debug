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
      // ~size.width-magnitude jumps across the wrap boundary; post-fix
      // the painter forwards full-precision pixelOrigin so consecutive
      // values are single-digit raw-pixel deltas.
      final captureds = <(double, double)>[];
      for (var i = 0; i < 10; i++) {
        mapController.move(LatLng(48.5397 + i * 0.0001, 2.6553 + i * 0.0001), 13);
        await _settleSdf(tester);
        final painter = _findFogPainter(tester);
        painter.paint(_MockCanvas(), const Size(400, 800));
        captureds.add(renderer.renders.last.pixelOrigin);
      }

      // Assert every consecutive-paint delta is below the threshold.
      // Pre-Plan-03.1-04 the modulo wrap produces ~size.width-magnitude
      // jumps (>>1e3) — would FAIL here. Post-fix the deltas are
      // single-digit raw pixels.
      for (var i = 1; i < captureds.length; i++) {
        final dx = (captureds[i].$1 - captureds[i - 1].$1).abs();
        final dy = (captureds[i].$2 - captureds[i - 1].$2).abs();
        expect(
          dx,
          lessThan(kPocFogSmoothCoordinateMaxDelta),
          reason:
              'FOG-11 regression at step $i: pixelOrigin.x jumped by $dx (threshold $kPocFogSmoothCoordinateMaxDelta). '
              'A modulo-wrap discontinuity at the Dart call site would produce ~size.width-magnitude jumps; '
              'a smooth pan produces single-digit raw-pixel deltas.',
        );
        expect(dy, lessThan(kPocFogSmoothCoordinateMaxDelta), reason: 'FOG-11 regression at step $i: pixelOrigin.y jumped by $dy.');
      }

      // Defence-in-depth: assert the captured value MAGNITUDE is in the
      // raw-pixel regime, not the normalised-UV regime. Any future
      // regression that re-introduces a Dart-side `% 1.0` would compress
      // the values into [0, 1) and trip this assertion. Pre-Plan-03.1-04
      // the Dart call site applied `% 1.0` and produced captured values < 1.
      expect(
        captureds.last.$1,
        greaterThan(100),
        reason:
            'FOG-11 magnitude regression: pixelOrigin.x must be in raw-pixel units (zoom 13 magnitude ~1e6), not normalised [0, 1). '
            'Pre-Plan-03.1-04 the Dart call site applied `% 1.0` and produced values < 1.',
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
