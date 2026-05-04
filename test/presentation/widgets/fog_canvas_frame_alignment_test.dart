// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_transform_logger.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';

import '../../_helpers/recording_fog_shader_renderer.dart';

/// FOG-12 (Plan 03.1-05 + Plan 03.1-08-FIX) — `_FogPainter.paint()`
/// normalises its local Canvas to the world (identity) frame BEFORE any
/// clip / draw operation, so the SDF reveal frame stays co-located with
/// the sibling blue-dot CircleLayer's UNTRANSLATED frame regardless of
/// whatever translation `MobileLayerTransformer` applied above.
///
/// Catches the CANVAS-FRAME-ALIGNMENT failure mode from
/// `03.1-FALSIFICATION.md` observation 4 (developer's "the revealed area
/// is being offsetted from the blue dot during pan/zoom").
///
/// **Three layered invariants asserted here:**
///
///   1. The painter calls `canvas.translate(-canvasTx, -canvasTy)`
///      BEFORE `canvas.clipPath(...)`. Under the new (Plan 03.1-08-FIX)
///      design, the canvas-translate at the TOP of paint() normalises
///      the prevailing transform to identity; the subsequent clipPath
///      then operates in the world (identity) frame. Pre-fix the
///      translate was AFTER clipPath, so clipPath operated in the
///      canvas-translated frame and the path was pre-shifted by
///      `-canvasOffset` inside `computeFogClipPath` to compensate —
///      that double-compensation broke under build 8a37bfd: when both
///      compensations were active, the reveal hole offset from the
///      blue dot during pan/zoom (regression).
///
///   2. The clip-path geometry is INVARIANT under canvasOffset.
///      `_FogPainter` calls `computeFogClipPath(camera: ..., discs: ...)`
///      WITHOUT a `canvasOffset` argument (defaults to `Offset.zero`).
///      The path is computed in raw world coordinates; the matrix
///      normalisation at the top of paint() handles the device-coord
///      placement. So `clipPaths.last.getBounds()` is identical
///      regardless of the mock canvas's `getTransform()` output.
///
///   3. Single `canvas.getTransform()` call per paint. Mirrors FOG-07
///      single-MapCamera-snapshot. A second read would re-introduce a
///      multi-snapshot anti-pattern at the Canvas-transform level.
///
/// **Reveal-hole position invariant (the user-facing assertion):** by
/// composition of (1) + (2), the device-coord position of the reveal
/// hole is the SAME for any canvasOffset (because the prevailing matrix
/// at clipPath-call time is `M_initial * translate(-canvasOffset) =
/// identity`, and the path is in world coords). This is what the user
/// observes as "blue dot stays inside the reveal hole during pan/zoom".
void main() {
  group('FOG-12 (Plan 03.1-05 + Plan 03.1-08-FIX keystone)', () {
    testWidgets('translate-before-clipPath + clip-path geometry invariant under non-zero Canvas transform', (tester) async {
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
      final wispTransformLogger = WispTransformLogger();
      addTearDown(wispTransformLogger.stop);
      final wispParticleSystem = WispParticleSystem();

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
                    wispParticleSystem: wispParticleSystem,
                    wispTransformLogger: wispTransformLogger,
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

      // Paint #1 — IDENTITY canvas transform. Capture the clip-path bounds
      // AND the call-order index of translate vs clipPath.
      final identityCanvas = _RecordingMockCanvas(canvasTx: 0, canvasTy: 0);
      final painter = _findFogPainter(tester);
      painter.paint(identityCanvas, const Size(400, 800));
      expect(identityCanvas.clipPathCalls, hasLength(1));
      final identityBounds = identityCanvas.clipPathCalls.last.getBounds();

      // Paint #2 — non-zero canvas transform matching 03.1-FALSIFICATION.md
      // Finding 1 magnitudes (canvasTx=5.035, canvasTy=-44.198).
      final shiftedCanvas = _RecordingMockCanvas(canvasTx: 5.035, canvasTy: -44.198);
      painter.paint(shiftedCanvas, const Size(400, 800));
      expect(shiftedCanvas.clipPathCalls, hasLength(1));
      final shiftedBounds = shiftedCanvas.clipPathCalls.last.getBounds();

      // Invariant #1 — translate-before-clipPath. The translate args must
      // exactly cancel the canvas-transform tx/ty (so the prevailing matrix
      // becomes identity at clipPath-time). With pre-fix Plan-03.1-08
      // ordering (clipPath BEFORE translate) this assertion fired with
      // `translate index < clipPath index` reversed.
      expect(
        shiftedCanvas.translateBeforeClipPath,
        isTrue,
        reason:
            'Plan 03.1-08-FIX regression: canvas.translate(-canvasTx, -canvasTy) MUST be called BEFORE canvas.clipPath(...) so the prevailing '
            'transform is normalised to identity before the clip path is registered. Pre-fix Plan 03.1-08 placed translate AFTER clipPath, '
            'requiring computeFogClipPath to pre-shift the path by -canvasOffset; on top of the canvas-translate this double-compensated and '
            're-introduced Walk #1 obs 4 (the hole offset from the blue dot during pan/zoom on build 8a37bfd).',
      );

      // Invariant #2 — clip-path geometry is INVARIANT under canvasOffset.
      // The painter passes the default `canvasOffset: Offset.zero` to
      // computeFogClipPath, so the path bounds are computed in raw world
      // coordinates regardless of the mock canvas's tx/ty.
      //
      // Sub-pixel tolerance for `Path.getBounds()` after
      // `Path.combine(PathOperation.difference, worldPath, holesPath)`. dart:ui's
      // path-difference engine introduces ~1e-6 float noise per axis on
      // non-axis-aligned shapes (the disc oval); 1e-3 is far below any
      // perceptible visual offset.
      const subPixelTolerance = 1e-3;
      expect(
        (shiftedBounds.left - identityBounds.left).abs(),
        lessThan(subPixelTolerance),
        reason:
            'Plan 03.1-08-FIX invariant: clip-path geometry MUST NOT shift with canvasOffset. Production _FogPainter calls '
            'computeFogClipPath(camera: ..., discs: ...) with the default Offset.zero — the path is computed in raw world coordinates and '
            'the canvas-translate at the top of paint() handles device-coord placement. If the bounds shift by -canvasOffset, the painter is '
            'still passing canvasOffset to computeFogClipPath (the broken Plan 03.1-08 double-compensation regression).',
      );
      expect(
        (shiftedBounds.top - identityBounds.top).abs(),
        lessThan(subPixelTolerance),
        reason: 'Plan 03.1-08-FIX invariant: clip-path geometry top edge MUST NOT shift with canvasOffset.',
      );
      expect(
        (shiftedBounds.right - identityBounds.right).abs(),
        lessThan(subPixelTolerance),
        reason: 'Plan 03.1-08-FIX invariant: clip-path geometry right edge MUST NOT shift with canvasOffset.',
      );
      expect(
        (shiftedBounds.bottom - identityBounds.bottom).abs(),
        lessThan(subPixelTolerance),
        reason: 'Plan 03.1-08-FIX invariant: clip-path geometry bottom edge MUST NOT shift with canvasOffset.',
      );

      // Invariant #3 — exactly ONE canvas.getTransform() call per paint.
      // Mirrors FOG-07's single-MapCamera-snapshot guarantee. A second read
      // would re-introduce a multi-snapshot anti-pattern at the Canvas-
      // transform level.
      expect(
        shiftedCanvas.getTransformCallCount,
        equals(1),
        reason:
            'single-snapshot invariant — mirrors FOG-07. The painter must read canvas.getTransform() once per paint and reuse the Float64List '
            'for both the canvas.translate compensation AND the fogTransformLogger emission.',
      );

      // Reveal-hole position invariant (composition of #1 + #2): under the
      // mock canvas's tx/ty the device-coord position of the hole is at
      // `path_local * matrix_at_clipPath_time`. Since translate was called
      // BEFORE clipPath with args (-tx, -ty), the matrix at clipPath-time
      // is `initial_matrix * translate(-tx, -ty) = identity`. So device
      // clip = path_local * identity = path_local — at the same WORLD
      // position regardless of canvasOffset. The hole stays under the
      // blue dot during pan/zoom; this is what the user sees.
      //
      // The mock canvas does not model matrix composition (it's a Fake);
      // the composition argument above relies on the production code's
      // single canvas.translate call. We assert exactly ONE translate call
      // in the production path so the composition is unambiguous.
      expect(
        shiftedCanvas.translateCallArgs,
        hasLength(1),
        reason:
            'single-translate invariant: exactly ONE canvas.translate per paint. A second translate would un-do the matrix normalisation and '
            're-create the hole-offset regression from a different direction.',
      );
      final (translateDx, translateDy) = shiftedCanvas.translateCallArgs.single;
      expect(
        translateDx,
        equals(-5.035),
        reason: 'translate dx must equal -canvasTx so the prevailing matrix is normalised to identity at clipPath-call time.',
      );
      expect(translateDy, equals(44.198), reason: 'translate dy must equal -canvasTy.');
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

/// Captures `clipPath()` + `translate()` + `getTransform()` calls in
/// invocation order so the test can assert (1) translate-BEFORE-clipPath
/// + (2) clip-path geometry invariance + (3) single-getTransform call.
///
/// Same `Fake implements Canvas` idiom as the FOG-09 / FOG-13 mock canvas;
/// adds a `clipPathCalls` list, a `translateCallArgs` list, an ordered
/// `_callOrder` list (op-name strings), a `translateBeforeClipPath` derived
/// flag, and a `getTransformCallCount` counter for the single-snapshot
/// invariant.
class _RecordingMockCanvas extends Fake implements Canvas {
  _RecordingMockCanvas({required this.canvasTx, required this.canvasTy});

  final double canvasTx;
  final double canvasTy;

  /// Captured paths from `clipPath(path)` calls.
  final List<ui.Path> clipPathCalls = <ui.Path>[];

  /// Captured `(dx, dy)` tuples from `translate(dx, dy)` calls.
  final List<(double, double)> translateCallArgs = <(double, double)>[];

  /// Ordered op-name list — index of 'translate' must be less than index
  /// of 'clipPath' for the FOG-12 + FOG-13 (post-Plan-03.1-08-FIX)
  /// invariant. Pre-fix the order was reversed.
  final List<String> _callOrder = <String>[];

  /// Tracks how many times the painter calls `getTransform()` per paint.
  /// Plan 03.1-05 must call it EXACTLY ONCE per paint (single-snapshot
  /// discipline at the matrix level — mirrors FOG-07 single-MapCamera-snapshot).
  int getTransformCallCount = 0;

  /// True iff the painter called `translate` BEFORE `clipPath` in this
  /// paint. False if order reversed OR either call is missing.
  bool get translateBeforeClipPath {
    final translateIdx = _callOrder.indexOf('translate');
    final clipPathIdx = _callOrder.indexOf('clipPath');
    if (translateIdx < 0 || clipPathIdx < 0) return false;
    return translateIdx < clipPathIdx;
  }

  @override
  void save() {
    _callOrder.add('save');
  }

  @override
  void restore() {
    _callOrder.add('restore');
  }

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    _callOrder.add('clipPath');
    clipPathCalls.add(path);
  }

  @override
  void translate(double dx, double dy) {
    _callOrder.add('translate');
    translateCallArgs.add((dx, dy));
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    _callOrder.add('drawRect');
  }

  @override
  Float64List getTransform() {
    _callOrder.add('getTransform');
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
