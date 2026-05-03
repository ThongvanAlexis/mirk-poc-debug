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

/// FOG-13 (Plan 03.1-08 → Plan 03.1-08-FIX) — `_FogPainter.paint()` calls
/// `canvas.translate(-canvasTx, -canvasTy)` at the TOP of paint() (BEFORE
/// `canvas.clipPath(...)` and BEFORE `canvas.drawRect(...)`) so the entire
/// painter operates in the world (identity) frame: clip path lands in the
/// world frame at world coordinates; rect-cover paints at the world-frame
/// origin (full-viewport coverage on screen regardless of canvas-translation
/// magnitude).
///
/// **History of this invariant:**
///
///   * **Plan 03.1-05** introduced `computeFogClipPath(canvasOffset: ...)`:
///     pre-shifted the clip-path geometry by `-canvasOffset` so that under
///     the prevailing canvas transform the clip ended up at world coords.
///     But the rect-cover (`canvas.drawRect(Offset.zero & size, fogPaint)`)
///     was NOT compensated — under Walk #2's worst sustained
///     `(canvasTx, canvasTy) = (+757.35, +319.46)` the rect painted almost
///     entirely off-screen, leaving viewport-edge strips of un-fogged map
///     visible at high zoom (developer's verbatim *"Mirk shader is somehow
///     rotating and not covering the whole map when zooming in"*).
///
///   * **Plan 03.1-08 (original)** added `canvas.translate(-canvasOffset)`
///     AFTER the existing `canvas.clipPath(...)` block (and KEPT the
///     `-canvasOffset` shift inside `computeFogClipPath`). Goal: rect-cover
///     compensation. Side-effect: when both compensations were active, the
///     reveal hole offset from the blue dot during pan/zoom on build
///     `8a37bfd` (developer's *"the revealed area is also offsetting itself
///     during pan/zoom — same bug as before but worse"*) — Walk #1 obs 4
///     re-introduced.
///
///   * **Plan 03.1-08-FIX (this revision)** moves the `canvas.translate`
///     to the TOP of paint() (immediately after `canvas.save()` + the
///     single `canvas.getTransform()` snapshot, BEFORE `canvas.clipPath`).
///     Removes the `-canvasOffset` argument from the
///     `computeFogClipPath(...)` call site (the path is now in raw world
///     coordinates because the canvas is already pre-translated to the
///     world frame). Single-frame discipline; one mechanism instead of
///     two compositional ones. Closes both Walk #1 obs 4 (hole co-location)
///     AND Walk #2 sub-section C (rect-cover viewport coverage)
///     mechanically.
///
/// **Three layered invariants asserted here:**
///
///   1. **Call-order:** `getTransform → save → translate → clipPath →
///      drawRect → restore`. Pre-Plan-03.1-08-FIX the order was
///      `getTransform → save → clipPath → translate → drawRect → restore`
///      (translate AFTER clipPath). Reversing the order is the load-
///      bearing change.
///
///   2. **Translate args:** exactly ONE `translate(-canvasTx, -canvasTy)`
///      call per paint. Single-snapshot discipline at the matrix level
///      (mirrors FOG-07 single-MapCamera-snapshot and FOG-12
///      single-getTransform-call invariants). Args within
///      `kPocCanvasTransformEpsilon` of (-canvasTx, -canvasTy).
///
///   3. **Reveal-hole-position invariant (the user-facing assertion):**
///      the path passed to `clipPath` is INVARIANT under the mock
///      canvas's tx/ty (because `_FogPainter` calls `computeFogClipPath`
///      WITHOUT a `canvasOffset` argument — defaults to `Offset.zero`).
///      Combined with invariant (1), this means the device-coord position
///      of the reveal hole is the SAME for any canvasOffset (because the
///      prevailing matrix at clipPath-call time is `M_initial *
///      translate(-canvasOffset) = identity`). The hole stays under the
///      blue dot during pan/zoom — Walk #1 obs 4 mechanically prevented.
///
/// Pre-Plan-03.1-08-FIX HEAD FAILS this test: invariant (1) reports
/// `clipPath` BEFORE `translate`; invariant (3) reports clip-path bounds
/// shifting by `-canvasOffset` between identity and shifted paints.
/// Post-fix HEAD PASSES.
void main() {
  group('FOG-13 (Plan 03.1-08-FIX keystone)', () {
    testWidgets('paint call order: getTransform → save → translate → clipPath → drawRect → restore at extreme canvas-translation magnitudes', (tester) async {
      final painter = await _pumpAndFindFogPainter(tester);

      // Walk #2's worst sustained `(canvasTx, canvasTy) = (+757.35, +319.46)`
      // for ~50 seconds — see 03.1-FALSIFICATION-2.md sub-section C.
      final mockCanvas = _RecordingMockCanvas(canvasTx: 757.35, canvasTy: 319.46);
      painter.paint(mockCanvas, const Size(390, 844));

      // Index of FIRST occurrence of each op. The painter must call (in
      // this order):
      //   1. getTransform — read the matrix.
      //   2. save — open the clip+translate block.
      //   3. translate — Plan 03.1-08-FIX: matrix normalisation to world
      //      (identity) frame at the TOP of paint() so subsequent clipPath
      //      + drawRect operate in known coordinates.
      //   4. clipPath — clip to the fog reveal-hole geometry. Operates in
      //      world coords because canvas was just normalised.
      //   5. drawRect — fog cover, at world-frame origin (Offset.zero &
      //      size — full viewport coverage on screen). **NOT observed
      //      under the null-shader test seam** (Plan 03-05): the painter
      //      guards `if (liveShader != null)` before calling drawRect, so
      //      widget tests that pass `shader: null` (because dart:ui
      //      `FragmentShader` is `base` and cannot be subclassed from a
      //      test file) never see drawRect. This is the same test seam
      //      used by FOG-09 and FOG-12; the FOG-13 invariant is asserted
      //      indirectly through the translate-BEFORE-restore call-order
      //      assertion below — drawRect, when present in production,
      //      lands inside the clip+translate block.
      //   6. restore — close the block.
      final indexByOp = <String, int>{};
      for (var i = 0; i < mockCanvas.calls.length; i++) {
        indexByOp.putIfAbsent(mockCanvas.calls[i].op, () => i);
      }

      expect(indexByOp['getTransform'], isNotNull, reason: 'painter must call canvas.getTransform() to read the canvas-translation matrix.');
      expect(indexByOp['save'], isNotNull, reason: 'painter must wrap the translate+clip block in canvas.save()/restore().');
      expect(
        indexByOp['translate'],
        isNotNull,
        reason:
            'FOG-13 regression: painter did NOT call canvas.translate(-canvasTx, -canvasTy). Without this, canvas.drawRect(Offset.zero & size, '
            'fogPaint) paints in the canvas-translated frame, leaving viewport-edge strips of un-fogged map visible at high zoom (Walk #2 sub-section C).',
      );
      expect(indexByOp['clipPath'], isNotNull, reason: 'painter must clip to the fog reveal-hole geometry.');
      expect(indexByOp['restore'], isNotNull, reason: 'painter must close the translate+clip block via canvas.restore().');

      // Plan 03.1-08-FIX call-order invariant — translate BEFORE clipPath
      // (was AFTER pre-fix; the reversal closes the build-8a37bfd
      // double-compensation regression).
      expect(
        indexByOp['getTransform']! < indexByOp['save']!,
        isTrue,
        reason: 'getTransform must precede save (the matrix read happens before the clip+translate block opens).',
      );
      expect(indexByOp['save']! < indexByOp['translate']!, isTrue, reason: 'save must precede translate.');
      expect(
        indexByOp['translate']! < indexByOp['clipPath']!,
        isTrue,
        reason:
            'Plan 03.1-08-FIX: translate must come BEFORE clipPath. The canvas-translate at the top of paint() normalises the prevailing transform '
            'to identity; the subsequent clipPath then operates in the world frame using a path computed in raw world coords (no -canvasOffset shift '
            'inside computeFogClipPath). If translate landed AFTER clipPath, computeFogClipPath would have to pre-shift the path by -canvasOffset to '
            'compensate, AND the canvas-translate would still be needed for the rect-cover — that double-compensation re-introduced Walk #1 obs 4 '
            '(hole offset from blue dot during pan/zoom) on build 8a37bfd.',
      );
      expect(
        indexByOp['clipPath']! < indexByOp['restore']!,
        isTrue,
        reason:
            'clipPath must come BEFORE restore so that drawRect (when invoked in production with a non-null shader) lands inside the clip+translate '
            'block. If clipPath landed AFTER restore, the canvas transform + clip would be unwound before drawRect ran.',
      );

      // Exactly ONE translate call — single-snapshot discipline at the matrix
      // level (mirrors FOG-07 single-MapCamera-snapshot and FOG-12
      // single-getTransform-call invariants).
      final translateCalls = mockCanvas.calls.where((c) => c.op == 'translate').toList();
      expect(
        translateCalls,
        hasLength(1),
        reason:
            'single-snapshot invariant — the painter must call canvas.translate exactly once per paint. A second translate would un-do or compound '
            'the matrix normalisation and re-create the FOG-13 / FOG-12 symptom from a different direction.',
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
            'FOG-13 regression: canvas.translate dx must equal -canvasTx (-757.35) so the rect-cover paints in the world-aligned frame. '
            'Pre-Plan-03.1-08 there was no translate call at all; if a translate is present but with a different argument, the compensation is wrong.',
      );
      expect((dy - (-319.46)).abs(), lessThan(kPocCanvasTransformEpsilon), reason: 'FOG-13 regression: canvas.translate dy must equal -canvasTy (-319.46).');
    });

    testWidgets('reveal-hole-position invariant: clip-path geometry MUST be identical regardless of canvasOffset (Plan 03.1-08-FIX)', (tester) async {
      // Reveal-hole-position invariant — the user-visible regression-catch
      // the original Plan 03.1-08 SHOULD have asserted but did not. With
      // the FIX, the painter calls `computeFogClipPath` WITHOUT a
      // `canvasOffset` argument (defaults to Offset.zero), so the path is
      // computed in raw world coordinates and is INVARIANT under the
      // mock canvas's tx/ty. Combined with the translate-before-clipPath
      // call-order invariant (asserted in the first test), the device-
      // coord position of the reveal hole is identical regardless of
      // canvasOffset — the hole stays under the blue dot during pan/zoom.
      //
      // Pre-Plan-03.1-08-FIX (the broken `8a37bfd` build): the painter
      // passed `canvasOffset: canvasOffset` to computeFogClipPath, so the
      // path geometry shifted by -canvasOffset between paints. On top of
      // the canvas-translate AFTER clipPath, this double-compensated the
      // hole position and re-introduced Walk #1 obs 4 ("the revealed area
      // is also offsetting itself during pan/zoom"). This test mechanically
      // catches that regression.
      final painter = await _pumpAndFindFogPainter(tester);

      // Paint #1 — IDENTITY canvas transform. Capture clip-path bounds.
      final identityCanvas = _RecordingMockCanvas(canvasTx: 0, canvasTy: 0);
      painter.paint(identityCanvas, const Size(390, 844));
      final identityClipPaths = identityCanvas.calls.where((c) => c.op == 'clipPath').toList();
      expect(identityClipPaths, hasLength(1), reason: 'painter must call clipPath exactly once per paint.');
      final identityBounds = (identityClipPaths.single.args as ui.Path).getBounds();

      // Paint #2 — Walk #2's worst sustained `(canvasTx, canvasTy) =
      // (+757.35, +319.46)`.
      final shiftedCanvas = _RecordingMockCanvas(canvasTx: 757.35, canvasTy: 319.46);
      painter.paint(shiftedCanvas, const Size(390, 844));
      final shiftedClipPaths = shiftedCanvas.calls.where((c) => c.op == 'clipPath').toList();
      expect(shiftedClipPaths, hasLength(1), reason: 'painter must call clipPath exactly once per paint.');
      final shiftedBounds = (shiftedClipPaths.single.args as ui.Path).getBounds();

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
            'Plan 03.1-08-FIX reveal-hole-position invariant: clip-path geometry MUST NOT shift with canvasOffset. _FogPainter must call '
            'computeFogClipPath with the default Offset.zero — the path is computed in raw world coordinates and the canvas-translate at the '
            'top of paint() handles device-coord placement. If left bound shifts by -canvasOffset.dx, the painter is still passing canvasOffset '
            'to computeFogClipPath (the broken Plan 03.1-08 double-compensation that re-introduced build-8a37bfd Walk #1 obs 4).',
      );
      expect(
        (shiftedBounds.top - identityBounds.top).abs(),
        lessThan(subPixelTolerance),
        reason: 'Plan 03.1-08-FIX reveal-hole-position invariant: clip-path geometry top edge MUST NOT shift with canvasOffset.',
      );
      expect(
        (shiftedBounds.right - identityBounds.right).abs(),
        lessThan(subPixelTolerance),
        reason: 'Plan 03.1-08-FIX reveal-hole-position invariant: clip-path geometry right edge MUST NOT shift with canvasOffset.',
      );
      expect(
        (shiftedBounds.bottom - identityBounds.bottom).abs(),
        lessThan(subPixelTolerance),
        reason: 'Plan 03.1-08-FIX reveal-hole-position invariant: clip-path geometry bottom edge MUST NOT shift with canvasOffset.',
      );
    });

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
            'painter must always call translate, even at identity. A special-case branch (skip translate when canvasOffset == Offset.zero) would '
            'couple the call sequence to the input matrix; a simple always-translate keeps the invariant single-shape.',
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
/// the test can assert ordering (translate BEFORE clipPath BEFORE drawRect)
/// + argument values + call counts (single-snapshot at the matrix level).
///
/// The `op == 'clipPath'` records carry the `ui.Path` directly as `args`
/// so the reveal-hole-position-invariant test can call
/// `(args as ui.Path).getBounds()` and compare across paints.
class _RecordingMockCanvas extends Fake implements Canvas {
  _RecordingMockCanvas({required this.canvasTx, required this.canvasTy});

  final double canvasTx;
  final double canvasTy;

  /// Ordered list of every Canvas operation invoked by the painter, with
  /// the operation name + raw args. Tests assert on `calls.indexWhere(...)`
  /// to verify ordering invariants and on `calls.where(op==X).single.args`
  /// to verify argument values.
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
