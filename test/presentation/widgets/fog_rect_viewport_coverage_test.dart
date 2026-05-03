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

/// FOG-13 — `_FogPainter.paint()` calls `canvas.translate(-canvasTx, -canvasTy)`
/// AFTER `canvas.clipPath(...)` and BEFORE `canvas.drawRect(...)` so the
/// fog-rect cover paints in the world-aligned screen frame instead of the
/// canvas-translated frame.
///
/// Catches the fog-rect viewport-coverage failure mode introduced by Plan
/// 03.1-05's clip-path-only compensation. Pre-Plan-03.1-08:
///   * `computeFogClipPath(canvasOffset: ...)` shifted the clip path by
///     `-canvasOffset` (Plan 03.1-05 / FOG-12 — confirmed-by-walk-2).
///   * `canvas.drawRect(Offset.zero & size, fogPaint)` was NOT compensated.
///     At Walk #2's worst sustained `(canvasTx, canvasTy) = (+757.35, +319.46)`
///     the rect painted almost entirely off-screen, leaving viewport-edge
///     strips of un-fogged map visible at high zoom (developer's verbatim
///     *"Mirk shader is somehow rotating and not covering the whole map
///     when zooming in"* + screenshot showing top-right + bottom-right
///     diagonal strips of un-fogged street map).
///
/// Plan 03.1-08 fix: Option (b) from `03.1-FALSIFICATION-2.md` sub-section D
/// row C-1 — `_FogPainter.paint()` calls `canvas.translate(-canvasTx,
/// -canvasTy)` immediately after the existing `canvas.save()` /
/// `canvas.clipPath(...)` block. The translate lives INSIDE the
/// save/restore block so the next layer in the stack sees a clean Canvas.
/// The clip-path shift composition is correct because clipPath geometry is
/// established BEFORE the translate, and clipPath is not affected by
/// subsequent canvas.translate calls.
///
/// Single-snapshot discipline preserved (mirrors FOG-07 / FOG-12): the
/// painter reads `canvas.getTransform()` exactly once per paint and reuses
/// the Float64List for both the clip-path correction AND the new
/// `canvas.translate` call.
///
/// Pre-Plan-03.1-08 HEAD FAILS this test (no `translate` call recorded
/// between `clipPath` and `drawRect`). Post-fix HEAD PASSES.
void main() {
  group('FOG-13 (Plan 03.1-08 keystone)', () {
    testWidgets(
      '_FogPainter.paint() calls canvas.translate(-canvasTx, -canvasTy) AFTER clipPath and BEFORE drawRect at extreme canvas-translation magnitudes',
      (tester) async {
        final painter = await _pumpAndFindFogPainter(tester);

        // Walk #2's worst sustained `(canvasTx, canvasTy) = (+757.35, +319.46)`
        // for ~50 seconds — see 03.1-FALSIFICATION-2.md sub-section C.
        final mockCanvas = _RecordingMockCanvas(canvasTx: 757.35, canvasTy: 319.46);
        painter.paint(mockCanvas, const Size(390, 844));

        // The painter must call (in this order):
        //   1. getTransform — read the matrix.
        //   2. save — open the clip+translate block.
        //   3. clipPath — Plan 03.1-05 clip-path shift compensation.
        //   4. translate — Plan 03.1-08 FOG-13 fix (canvas-translation compensation
        //      for the rect-cover paint).
        //   5. drawRect — fog cover, now in the world-aligned frame.
        //   6. restore — close the block.
        final indexByOp = <String, int>{};
        for (var i = 0; i < mockCanvas.calls.length; i++) {
          indexByOp.putIfAbsent(mockCanvas.calls[i].op, () => i);
        }

        expect(indexByOp['getTransform'], isNotNull, reason: 'painter must call canvas.getTransform() to read the canvas-translation matrix.');
        expect(indexByOp['save'], isNotNull, reason: 'painter must wrap the clip+translate block in canvas.save()/restore().');
        expect(indexByOp['clipPath'], isNotNull, reason: 'painter must clip to the fog reveal-hole geometry (Plan 03.1-05 FOG-12).');
        expect(
          indexByOp['translate'],
          isNotNull,
          reason:
              'FOG-13 regression: painter did NOT call canvas.translate(-canvasTx, -canvasTy). '
              'Without this, canvas.drawRect(Offset.zero & size, fogPaint) paints in the canvas-translated frame, '
              'leaving viewport-edge strips of un-fogged map visible at high zoom (Walk #2 sub-section C).',
        );
        expect(indexByOp['drawRect'], isNotNull, reason: 'painter must paint the fog cover via canvas.drawRect.');
        expect(indexByOp['restore'], isNotNull, reason: 'painter must close the clip+translate block via canvas.restore().');

        expect(
          indexByOp['getTransform']! < indexByOp['save']!,
          isTrue,
          reason: 'getTransform must precede save (the matrix read happens before the clip+translate block opens).',
        );
        expect(indexByOp['save']! < indexByOp['clipPath']!, isTrue, reason: 'save must precede clipPath.');
        expect(
          indexByOp['clipPath']! < indexByOp['translate']!,
          isTrue,
          reason:
              'translate must come AFTER clipPath. clipPath geometry is established BEFORE the translate, so the '
              'clip-path shift composes correctly with the new canvas-translation. If translate landed BEFORE '
              'clipPath, the clip path would be double-shifted (the existing -canvasOffset shift inside '
              'computeFogClipPath PLUS the new canvas.translate) — the fog hole would drift off the blue dot.',
        );
        expect(
          indexByOp['translate']! < indexByOp['drawRect']!,
          isTrue,
          reason:
              'translate must come BEFORE drawRect. drawRect bounds are subject to the prevailing canvas transform; '
              'if translate ran AFTER drawRect, the rect-cover would still paint in the canvas-translated frame and '
              'the FOG-13 regression would persist.',
        );
        expect(indexByOp['drawRect']! < indexByOp['restore']!, isTrue, reason: 'restore must come last (closes the clip+translate block).');

        // Exactly ONE translate call — single-snapshot discipline at the matrix
        // level (mirrors FOG-07 single-MapCamera-snapshot and FOG-12
        // single-getTransform-call invariants).
        final translateCalls = mockCanvas.calls.where((c) => c.op == 'translate').toList();
        expect(
          translateCalls,
          hasLength(1),
          reason:
              'single-snapshot invariant — the painter must call canvas.translate exactly once per paint. '
              'A second translate would double-shift the rect-cover and re-introduce the FOG-13 symptom from a '
              'different direction.',
        );

        // Translate args must match -canvasTx / -canvasTy within
        // kPocCanvasTransformEpsilon (1e-6 — far below floating-point noise
        // and orders of magnitude below the ~757-pixel regression we catch).
        final translateArgs = translateCalls.single.args;
        expect(translateArgs, isA<(double, double)>(), reason: 'translate args must be a (double, double) tuple of (dx, dy).');
        final (dx, dy) = translateArgs as (double, double);
        expect(
          (dx - (-757.35)).abs(),
          lessThan(kPocCanvasTransformEpsilon),
          reason:
              'FOG-13 regression: canvas.translate dx must equal -canvasTx (-757.35) so the rect-cover paints in '
              'the world-aligned frame. Pre-Plan-03.1-08 there was no translate call at all; if a translate is '
              'present but with a different argument, the compensation is wrong.',
        );
        expect((dy - (-319.46)).abs(), lessThan(kPocCanvasTransformEpsilon), reason: 'FOG-13 regression: canvas.translate dy must equal -canvasTy (-319.46).');

        // The recorded drawRect must paint a viewport-sized rect at origin.
        // The painter's job is to call drawRect with `Offset.zero & size`; the
        // Plan 03.1-08 canvas.translate above does the world-alignment in the
        // canvas-transform stack rather than at the rect-bounds level (Option
        // b vs Option c — see plan rationale). So at the test boundary the
        // rect itself is still (0, 0, 390, 844).
        final drawRectCalls = mockCanvas.calls.where((c) => c.op == 'drawRect').toList();
        expect(drawRectCalls, hasLength(1), reason: 'painter must call drawRect exactly once per paint.');
        final drawRectArgs = drawRectCalls.single.args as (Rect, Paint);
        expect(
          drawRectArgs.$1,
          equals(const Rect.fromLTWH(0, 0, 390, 844)),
          reason: 'fog-rect cover bounds must be Offset.zero & size (the canvas.translate above does the world-alignment).',
        );
      },
    );

    testWidgets('when canvasTransform is identity (canvasTx=0, canvasTy=0), canvas.translate(0, 0) is still called so the call sequence is invariant', (
      tester,
    ) async {
      final painter = await _pumpAndFindFogPainter(tester);
      final mockCanvas = _RecordingMockCanvas(canvasTx: 0, canvasTy: 0);
      painter.paint(mockCanvas, const Size(390, 844));

      // The implementation does NOT special-case identity — it always
      // calls translate(-canvasTx, -canvasTy), even when both are zero.
      // This keeps the call sequence invariant regardless of the canvas
      // transform, and keeps the production code path branchless (a
      // canvas.translate(0, 0) is a documented no-op in dart:ui's
      // Canvas implementation).
      final translateCalls = mockCanvas.calls.where((c) => c.op == 'translate').toList();
      expect(
        translateCalls,
        hasLength(1),
        reason:
            'painter must always call translate, even at identity. A special-case branch (skip translate when '
            'canvasOffset == Offset.zero) would couple the call sequence to the input matrix; a simple always-'
            'translate keeps the invariant single-shape.',
      );
      final (dx, dy) = translateCalls.single.args as (double, double);
      expect(dx, equals(0.0), reason: 'identity-matrix translate dx == 0.0.');
      expect(dy, equals(0.0), reason: 'identity-matrix translate dy == 0.0.');
    });
  });
}

/// Mounts a real `FlutterMap` + `FogLayer` at Melun zoom 13, lets the SDF
/// future settle through `tester.runAsync`, and returns the painter so the
/// test can drive paint() directly with an injected `_RecordingMockCanvas`.
///
/// Same pattern as `fog_canvas_frame_alignment_test.dart` (FOG-12) and
/// `fog_pan_translation_test.dart` (FOG-09); without the runAsync settle
/// loop the painter's `if (sdfImage == null) return;` guard short-circuits
/// paint() and no calls are recorded against the mock canvas.
Future<CustomPainter> _pumpAndFindFogPainter(WidgetTester tester) async {
  final mapController = MapController();
  addTearDown(mapController.dispose);
  final probe = FrameDeltaProbe();
  addTearDown(() async => probe.dispose());
  final fogTransformLogger = FogTransformLogger();
  addTearDown(fogTransformLogger.stop);
  final discRepository = RevealDiscRepository();
  // Append one disc at the camera centre so computeFogClipPath produces a
  // non-degenerate clip path (world-rect-minus-one-disc).
  discRepository.append(
    RevealDisc(id: 'rvd_fog_rect_viewport_coverage_test', sessionId: 't', lat: 48.5397, lon: 2.6553, radiusMeters: 25, fixedAtUtc: DateTime.now().toUtc()),
  );
  addTearDown(discRepository.dispose);
  final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
  addTearDown(sdfCache.dispose);
  final renderer = RecordingFogShaderRenderer();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          // iPhone 17 Pro logical viewport — matches Walk #2's device.
          width: 390,
          height: 844,
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
  await tester.runAsync(() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump();

  final customPaint = tester.widget<CustomPaint>(find.descendant(of: find.byType(FogLayer), matching: find.byType(CustomPaint)));
  final painter = customPaint.painter;
  if (painter == null) {
    fail('Expected FogLayer descendant CustomPaint to carry a non-null `painter`; got null.');
  }
  return painter;
}

/// Captures the FULL call sequence on a fake `Canvas`. Each override appends
/// a `({String op, Object? args})` record to [calls] in invocation order so
/// the test can assert ordering (clipPath BEFORE translate BEFORE drawRect)
/// + argument values + call counts (single-snapshot at the matrix level).
///
/// Extends the FOG-12 mock-canvas pattern (`fog_canvas_frame_alignment_test.dart`
/// `_RecordingMockCanvas`) with a `translate` recorder and an ordered `calls`
/// list. The FOG-12 mock's `clipPaths` list is preserved (via the call sequence)
/// for any future composition test that needs both shapes.
class _RecordingMockCanvas extends Fake implements Canvas {
  _RecordingMockCanvas({required this.canvasTx, required this.canvasTy});

  final double canvasTx;
  final double canvasTy;

  /// Ordered list of every Canvas operation invoked by the painter, with
  /// the operation name + raw args. Tests assert on `calls.indexWhere(...)`
  /// to verify ordering invariants (clipPath BEFORE translate BEFORE
  /// drawRect) and on `calls.where(op==X).single.args` to verify argument
  /// values (translate dx/dy match -canvasTx/-canvasTy).
  final List<({String op, Object? args})> calls = <({String op, Object? args})>[];

  @override
  void save() {
    calls.add((op: 'save', args: null));
  }

  @override
  void restore() {
    calls.add((op: 'restore', args: null));
  }

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    calls.add((op: 'clipPath', args: path));
  }

  @override
  void translate(double dx, double dy) {
    calls.add((op: 'translate', args: (dx, dy)));
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    calls.add((op: 'drawRect', args: (rect, paint)));
  }

  @override
  Float64List getTransform() {
    calls.add((op: 'getTransform', args: null));
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
