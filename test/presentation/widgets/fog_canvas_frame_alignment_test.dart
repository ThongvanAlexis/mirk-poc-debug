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
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';

import '../../_helpers/recording_fog_shader_renderer.dart';

/// FOG-12 — `_FogPainter.paint()` reads `canvas.getTransform()` ONCE per
/// paint and pre-shifts the clip-path holes by `-(matrix[12], matrix[13])`
/// so the SDF reveal frame stays co-located with the sibling blue-dot
/// CircleLayer's UNTRANSLATED frame.
///
/// Catches the CANVAS-FRAME-ALIGNMENT failure mode from
/// `03.1-FALSIFICATION.md` observation 4 (developer's "the revealed area
/// is being offsetted from the blue dot during pan/zoom"). Pre-Plan-03.1-05
/// the painter ignored the Canvas transform; the reveal hole drifted from
/// the blue dot by exactly the matrix's `(tx, ty)`. Post-fix the offset
/// subtraction restores co-location.
///
/// Single-snapshot at the matrix level — `_FogPainter.paint()` MUST call
/// `canvas.getTransform()` EXACTLY ONCE per paint. Mirrors FOG-07's
/// single-MapCamera-snapshot guarantee. The same `Float64List` is reused
/// for both the clip-path correction AND the fogTransformLogger emission;
/// a second `getTransform()` would re-introduce a multi-snapshot
/// anti-pattern.
void main() {
  group('FOG-12 (Plan 03.1-05 keystone)', () {
    testWidgets('clip path holes pre-shift by -canvasTx/Ty under non-zero Canvas transform', (tester) async {
      final mapController = MapController();
      addTearDown(mapController.dispose);
      final probe = FrameDeltaProbe();
      addTearDown(() async => probe.dispose());
      final fogTransformLogger = FogTransformLogger();
      addTearDown(fogTransformLogger.stop);
      final discRepository = RevealDiscRepository();
      // Append one disc at the camera centre; the hole center should
      // project to ~(200, 400) in screen space (centre of 400x800).
      discRepository.append(
        RevealDisc(id: 'rvd_canvas_frame_test', sessionId: 't', lat: 48.5397, lon: 2.6553, radiusMeters: 25, fixedAtUtc: DateTime.now().toUtc()),
      );
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
      // Settle the SDF future via the real event loop (same pattern as FOG-09).
      // Without `runAsync`, the painter's `if (sdfImage == null) return;` guard
      // short-circuits paint() and the canvas's clipPaths list stays empty.
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      // Paint #1 — IDENTITY canvas transform. Capture the clip-path bounds.
      final identityCanvas = _RecordingMockCanvas(canvasTx: 0, canvasTy: 0);
      final painter = _findFogPainter(tester);
      painter.paint(identityCanvas, const Size(400, 800));
      expect(identityCanvas.clipPaths, hasLength(1));
      final identityBounds = identityCanvas.clipPaths.last.getBounds();

      // Paint #2 — non-zero canvas transform matching 03.1-FALSIFICATION.md
      // Finding 1 magnitudes (canvasTx=5.035, canvasTy=-44.198).
      // The clip path bounds MUST be shifted by exactly (-5.035, +44.198)
      // relative to the identity-canvas bounds.
      final shiftedCanvas = _RecordingMockCanvas(canvasTx: 5.035, canvasTy: -44.198);
      painter.paint(shiftedCanvas, const Size(400, 800));
      expect(shiftedCanvas.clipPaths, hasLength(1));
      final shiftedBounds = shiftedCanvas.clipPaths.last.getBounds();

      expect(
        (shiftedBounds.left - (identityBounds.left - 5.035)).abs(),
        lessThan(kPocCanvasTransformEpsilon),
        reason:
            'CANVAS-FRAME-ALIGNMENT regression: clip-path bounds did not shift by -canvasTx under non-zero Canvas translation. '
            'Pre-Plan-03.1-05 the painter ignored canvas.getTransform() and the reveal frame drifted from the blue-dot frame.',
      );
      expect(
        (shiftedBounds.top - (identityBounds.top - (-44.198))).abs(),
        lessThan(kPocCanvasTransformEpsilon),
        reason: 'CANVAS-FRAME-ALIGNMENT regression: clip-path bounds did not shift by -canvasTy.',
      );

      // Single-snapshot at the matrix level — `_FogPainter.paint()` must call
      // `canvas.getTransform()` EXACTLY ONCE per paint. Mirrors FOG-07's
      // single-MapCamera-snapshot guarantee. A second read would re-introduce
      // a multi-snapshot anti-pattern at the Canvas-transform level.
      expect(
        shiftedCanvas.getTransformCallCount,
        equals(1),
        reason:
            'single-snapshot invariant — mirrors FOG-07. The painter must read canvas.getTransform() once per paint and reuse the Float64List for both the clip-path correction AND the fogTransformLogger emission.',
      );
    });
  });
}

CustomPainter _findFogPainter(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(find.descendant(of: find.byType(FogLayer), matching: find.byType(CustomPaint)));
  final painter = customPaint.painter;
  if (painter == null) {
    fail('Expected FogLayer descendant CustomPaint to carry a non-null `painter`; got null.');
  }
  return painter;
}

/// Captures `clipPath()` calls + a configurable canvas-transform via
/// `getTransform()`. Same `Fake implements Canvas` idiom as the FOG-09 mock
/// canvas (`fog_pan_translation_test.dart` `_MockCanvas`); adds a
/// `clipPaths` list for the assertion + a constructor for the
/// canvas-transform translation + a `getTransformCallCount` counter for
/// the single-snapshot invariant assertion.
class _RecordingMockCanvas extends Fake implements Canvas {
  _RecordingMockCanvas({required this.canvasTx, required this.canvasTy});

  final double canvasTx;
  final double canvasTy;
  final List<ui.Path> clipPaths = <ui.Path>[];

  /// Tracks how many times the painter calls `getTransform()` per paint.
  /// Plan 03.1-05 must call it EXACTLY ONCE per paint (single-snapshot
  /// discipline at the matrix level — mirrors FOG-07 single-MapCamera-snapshot).
  int getTransformCallCount = 0;

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    clipPaths.add(path);
  }

  @override
  void drawRect(Rect rect, Paint paint) {}

  @override
  Float64List getTransform() {
    getTransformCallCount += 1;
    final m = Float64List(16);
    m[0] = 1.0;
    m[5] = 1.0;
    m[10] = 1.0;
    m[15] = 1.0;
    m[12] = canvasTx;
    m[13] = canvasTy;
    return m;
  }
}
