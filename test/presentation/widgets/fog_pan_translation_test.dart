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
/// `offset` argument to `shaderRenderer.render(...)` after a programmatic
/// `MapController.move(...)`.
///
/// The KEYSTONE behavioural transform-equality regression test that catches
/// the Plan 03-08 static-fog-during-pan failure mode mechanically — without
/// a sideload UAT walk. The Plan 03-05 structural FOG-04 test (sibling file
/// `fog_layer_test.dart`) is necessary but NOT sufficient: widget-tree
/// containment under `MobileLayerTransformer` does not imply Canvas-transform
/// sharing. This file's primary test asserts the BEHAVIOURAL consequence
/// (the fog offset uniform tracks the camera's pixelOrigin) that the
/// structural test cannot.
///
/// Pre-fix HEAD (SHA 280dd04) FAILS this test (initial offset == panned
/// offset == (0,0) exact); post-fix HEAD passes it. The skipped sub-test
/// at the bottom is the vacuous-test guard — manually unskip it against
/// pre-fix HEAD to verify the guard catches the regression.
void main() {
  group('FOG-09 (Plan 03.1-02 keystone)', () {
    testWidgets('FogLayer offset uniform tracks camera pan (catches Plan 03-08 static-fog regression)', (tester) async {
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
      final initialOffset = renderer.renders.last.offset;

      // ~1.5 km NE of Melun town centre (still inside the Phase 2 Melun
      // bbox + cameraConstraint pad). At zoom 13 (256 × 2^13 = 2_097_152
      // world pixels), this delta yields normalised-UV offsets of roughly
      // ~0.196 (X) / ~0.098 (Y) — comfortably away from the modulo-1.0
      // wrap boundary (where abs-diff would falsely report ~1.0 across a
      // real ~0 delta, e.g. 0.99999 → 0.00001). If a future test uses a
      // pan close to a wrap boundary, switch to `min(abs(d), 1.0 - abs(d))`
      // for boundary safety.
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
      final pannedOffset = renderer.renders.last.offset;

      expect(
        (pannedOffset.$1 - initialOffset.$1).abs(),
        greaterThan(kPocCanvasTransformEpsilon),
        reason:
            'Plan 03-08 regression: uOffset.x did not change after a programmatic pan. '
            'The painter MUST derive uOffset from camera.pixelOrigin / size and forward '
            'the result to shaderRenderer.render(offset:). Pre-fix HEAD passed offset: '
            'const (0.0, 0.0) and tripped this assertion.',
      );
      expect(
        (pannedOffset.$2 - initialOffset.$2).abs(),
        greaterThan(kPocCanvasTransformEpsilon),
        reason: 'Plan 03-08 regression: uOffset.y did not change after a programmatic pan.',
      );
    });

    testWidgets(
      'RED-guard (skip:true; manual run against pre-fix HEAD SHA 280dd04 — verifies guard catches Plan 03-08 failure mode): painter passes offset: const (0.0, 0.0) exact',
      (tester) async {
        // Same setUp as the primary test — pump FlutterMap + FogLayer at Melun zoom 13.
        // Capture renderer.renders.first.offset.
        // Assert: expect(initialOffset, equals((0.0, 0.0))).
        //
        // Manually unskip this sub-test, check out SHA 280dd04, run flutter test.
        // The assertion must PASS against pre-fix HEAD (the painter literally
        // passes a constant zero tuple). If the assertion FAILS against pre-fix
        // HEAD, someone changed the production code without updating the test,
        // and the FOG-09 keystone above is no longer protecting against the
        // original failure mode.
        //
        // Skipped on green-main because this assertion would fail on the
        // post-fix HEAD by construction (offset is now non-zero).
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
        final initialOffset = renderer.renders.first.offset;
        expect(initialOffset, equals((0.0, 0.0)));
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
/// channel is the (uOffsetX, uOffsetY) tuple, NOT the Canvas matrix.
class _MockCanvas extends Fake implements Canvas {
  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {}

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
