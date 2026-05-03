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

/// FOG-09 — `_FogPainter.paint()` forwards a non-zero, pan-delta-tracking
/// `pixelOrigin` argument to `shaderRenderer.render(...)` after a programmatic
/// `MapController.move(...)`.
///
/// The KEYSTONE behavioural transform-equality regression test that catches
/// the Plan 03-08 static-fog-during-pan failure mode mechanically — without
/// a sideload UAT walk. The Plan 03-05 structural FOG-04 test (sibling file
/// `fog_layer_test.dart`) is necessary but NOT sufficient: widget-tree
/// containment under `MobileLayerTransformer` does not imply Canvas-transform
/// sharing. This file's primary test asserts the BEHAVIOURAL consequence
/// (the fog `uPixelOrigin` uniform receives the camera's pixelOrigin verbatim,
/// no Dart-side modulo) that the structural test cannot.
///
/// Pre-fix HEAD (SHA 280dd04) FAILS this test (initial pixelOrigin == panned
/// pixelOrigin == (0,0) exact); post-fix HEAD passes it. The skipped sub-test
/// at the bottom is the vacuous-test guard — manually unskip it against
/// pre-fix HEAD SHA 280dd04 to verify the guard catches the regression.
///
/// Plan 03.1-04 update: the painter's call-site argument was renamed
/// `offset` → `pixelOrigin` and the `% 1.0` modulo moved into the fragment
/// shader (`fract(uPixelOrigin / uResolution)` per-fragment). Captured
/// magnitudes are now in raw world-pixel units (zoom 13 ~1e6) instead of
/// normalised UV [0, 1); the consecutive-pan delta is ~411 raw pixels at
/// zoom 13 — enormously above `kPocCanvasTransformEpsilon = 1e-6`.
///
/// Plan 03.1-10 update: FOG-17a CPU-side integer/fractional decomposition
/// adds a Dart-side `% kPocFogIntegerWrapPeriodPx` (1536) modulo to keep
/// shader input bounded under ~1537 raw px at high zoom. The forwarded
/// value is now a BOUNDED COMPOSITE `(intPx % kPocFogIntegerWrapPeriodPx)
/// + fracPx`, NOT raw camera.pixelOrigin verbatim. The mechanical
/// delta > epsilon assertion still passes — for typical sub-1536-raw-px
/// walks the bounded composite changes monotonically with the camera —
/// but the documentation tracks the active code semantics.
///
/// Plan 03.1-12 update: FOG-18 world-meter anchor ALSO forwards a NEW
/// uniform `metersPerPixel` (computed from lat × zoom) per paint. The
/// FOG-09 pixelOrigin-tracks-pan assertion is unaffected (still
/// non-zero delta on programmatic pan), but a NEW assertion below
/// covers the FOG-18 per-paint re-derivation: a synthetic zoom change
/// at a fixed lat must produce a non-zero delta in the forwarded
/// `metersPerPixel` (defends against a hardcoded-cached regression
/// where the painter caches metersPerPixel between paints).
void main() {
  group('FOG-09 (Plan 03.1-02 keystone)', () {
    testWidgets('FogLayer pixelOrigin uniform tracks camera pan (catches Plan 03-08 static-fog regression)', (tester) async {
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
      // Let the SDF cache's async `buildFromDiscs` future resolve via the
      // real event loop — `tester.pump()` alone advances microtasks but the
      // SDF builder uses `ui.decodeImageFromPixels(..., Completer.complete)`
      // which needs a real platform tick. Without `runAsync`, the painter's
      // `if (sdfImage == null) return;` guard short-circuits paint() and no
      // `RecordedFogRender` is appended to the renderer.
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      // Drive the painter directly via the public CustomPainter interface.
      // `_FogPainter` is private (Dart underscore convention), so we cast to
      // the public `CustomPainter` and invoke `paint(MockCanvas(), Size)` —
      // same idiom as Flutter SDK's own custom_paint_test.dart. Each call
      // appends one `RecordedFogRender` to `renderer.renders`.
      final initialPainter = _findFogPainter(tester);
      initialPainter.paint(_MockCanvas(), const Size(400, 800));
      expect(
        renderer.renders,
        isNotEmpty,
        reason: 'paint() must have run through the renderer at least once — if empty, the SDF future never resolved within the runAsync budget.',
      );
      final initialPixelOrigin = renderer.renders.last.worldMetersOrigin;

      // ~1.5 km NE of Melun town centre (still inside the Phase 2 Melun
      // bbox + cameraConstraint pad). At zoom 13 (256 × 2^13 = 2_097_152
      // world pixels), this delta produces a `camera.pixelOrigin` shift of
      // ~411 raw pixels on the X axis and ~205 on the Y axis. Both are
      // ENORMOUS compared to `kPocCanvasTransformEpsilon = 1e-6`, so the
      // assertion fires generously. Plan 03.1-04 moved the modulo wrap into
      // the fragment shader (`fract(uPixelOrigin / uResolution)`); the Dart
      // call site forwards full-precision values and there is no `% 1.0`
      // truncation to handle here.
      mapController.move(const LatLng(48.5500, 2.6700), 13);
      await tester.runAsync(() async {
        // Allow the post-move SDF rebuild (viewport hash changed) to settle.
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      // The painter instance is reconstructed in FogLayer.build on each
      // rebuild — re-find it AFTER the move/pump so we're invoking the
      // post-pan camera snapshot, NOT the cached pre-pan instance.
      final pannedPainter = _findFogPainter(tester);
      pannedPainter.paint(_MockCanvas(), const Size(400, 800));
      final pannedPixelOrigin = renderer.renders.last.worldMetersOrigin;

      expect(
        (pannedPixelOrigin.$1 - initialPixelOrigin.$1).abs(),
        greaterThan(kPocCanvasTransformEpsilon),
        reason:
            'Plan 03-08 regression: uWorldMetersOrigin.x did not change after a programmatic pan. '
            'The painter MUST forward a camera.pixelOrigin-derived value (after Plan 03.1-14 Fix B′ meter-space '
            'decomposition) to shaderRenderer.render(worldMetersOrigin:). '
            'Pre-FOG-17a: raw pixelOrigin (zoom 13 magnitude ~1e6). '
            'Plan 03.1-10..12: bounded pixel composite `(intPx % kPocFogIntegerWrapPeriodPx) + fracPx` (superseded). '
            'Plan 03.1-14 Fix B′ — FOG-19: bounded meter composite `(intMeters % kPocFogIntegerWrapPeriodMeters) + '
            'fracMeters`. The painter ALSO forwards metersPerPixel per paint (Plan 03.1-12 FOG-18); the FOG-09 '
            'assertion continues to test the camera-pan-track property — the meter-space bounded composite still '
            'moves with camera pan. A programmatic pan MUST produce a non-zero delta in the forwarded value. '
            'Pre-fix HEAD passed const (0.0, 0.0) and tripped this assertion.',
      );
      expect(
        (pannedPixelOrigin.$2 - initialPixelOrigin.$2).abs(),
        greaterThan(kPocCanvasTransformEpsilon),
        reason: 'Plan 03-08 regression: uWorldMetersOrigin.y did not change after a programmatic pan (Plan 03.1-14 Fix B′ — meter-space bounded composite).',
      );
    });

    testWidgets('FOG-18 (Plan 03.1-12) — synthetic zoom change at fixed lat produces non-zero delta in forwarded metersPerPixel', (tester) async {
      // Defends against a hardcoded-cached metersPerPixel regression
      // at the painter level: pump two paints at zoom 13 then zoom 15
      // (same lat); assert the recorded metersPerPixel values differ.
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
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      final painter1 = _findFogPainter(tester);
      painter1.paint(_MockCanvas(), const Size(400, 800));
      final mppZ13 = renderer.renders.last.metersPerPixel;

      // Synthetic zoom change at fixed lat (48.5397°). zoom 13 → 15
      // halves metersPerPixel twice (factor 4). Painter must
      // re-derive on the new camera snapshot.
      mapController.move(const LatLng(48.5397, 2.6553), 15);
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();
      final painter2 = _findFogPainter(tester);
      painter2.paint(_MockCanvas(), const Size(400, 800));
      final mppZ15 = renderer.renders.last.metersPerPixel;

      expect(
        (mppZ13 - mppZ15).abs(),
        greaterThan(kPocCanvasTransformEpsilon),
        reason:
            'FOG-18 per-paint re-derivation regression: synthetic zoom change (z=13 → z=15) at fixed lat '
            'must produce a non-zero delta in forwarded metersPerPixel. mppZ13=$mppZ13, mppZ15=$mppZ15. '
            'A zero delta indicates the painter is hardcoding/caching metersPerPixel rather than re-deriving '
            'from the live camera snapshot per paint.',
      );
    });

    testWidgets(
      'RED-guard (skip:true; manual run against pre-fix HEAD SHA 280dd04 — verifies guard catches Plan 03-08 failure mode): painter passes worldMetersOrigin: const (0.0, 0.0) exact',
      (tester) async {
        // Same setUp as the primary test — pump FlutterMap + FogLayer at Melun zoom 13.
        // Capture renderer.renders.first.pixelOrigin.
        // Assert: expect(initialPixelOrigin, equals((0.0, 0.0))).
        //
        // Manually unskip this sub-test, check out SHA 280dd04, run flutter test.
        // The assertion must PASS against pre-fix HEAD (the painter literally
        // passes a constant zero tuple). If the assertion FAILS against pre-fix
        // HEAD, someone changed the production code without updating the test,
        // and the FOG-09 keystone above is no longer protecting against the
        // original failure mode.
        //
        // Plan 03.1-04 note: the field is now `pixelOrigin` (renamed from
        // `offset`); SHA 280dd04 is still the relevant pre-fix HEAD because
        // the constant-zero failure mode (Plan 03-08) is what this guard catches.
        //
        // Skipped on green-main because this assertion would fail on the
        // post-fix HEAD by construction (pixelOrigin is now non-zero).
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
        await tester.pump();
        final painter = _findFogPainter(tester);
        painter.paint(_MockCanvas(), const Size(400, 800));
        final initialPixelOrigin = renderer.renders.first.worldMetersOrigin;
        expect(initialPixelOrigin, equals((0.0, 0.0)));
      },
      skip: true,
    );
  });
}

/// Re-locates the `_FogPainter` underneath the `FogLayer` widget on every
/// rebuild — `_FogPainter` is private, so the test casts to the public
/// `CustomPainter` interface and invokes `paint(canvas, size)` directly.
/// Same idiom as Flutter SDK's `custom_paint_test.dart`.
CustomPainter _findFogPainter(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(find.descendant(of: find.byType(FogLayer), matching: find.byType(CustomPaint)));
  final painter = customPaint.painter;
  if (painter == null) {
    fail('Expected FogLayer descendant CustomPaint to carry a non-null `painter`; got null.');
  }
  return painter;
}

/// Minimal `Canvas` fake — overrides only what `_FogPainter.paint()` calls.
/// The painter invokes `save()`, `clipPath(...)`, `getTransform()`,
/// `drawRect(...)`, and `restore()`. Everything else throws via the `Fake`
/// base — if the painter ever grows a new Canvas call, the test fails fast
/// rather than silently masking the regression.
///
/// `getTransform()` returns a 4×4 identity matrix (column-major Float64List
/// of length 16). Per RESEARCH §Pitfall D, the painter's local Canvas IS at
/// identity inside `MobileLayerTransformer` at rotation=0; the diagnostic
/// channel is the (uPixelOrigin.x, uPixelOrigin.y) tuple, NOT the Canvas matrix.
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
