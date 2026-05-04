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
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_transform_logger.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';

import '../../_helpers/recording_fog_shader_renderer.dart';

/// FOG-19 (Plan 03.1-14 Task B) — uZoomScale uniform forwarded as
/// `pow(2, camera.zoom - kPocFogReferenceZoom)`. Anchors fog noise
/// samples to lat/lng during zoom transitions (Q1b residual fix per
/// Walk #5 developer verbatim "numbers sliding / incorrect scaling").
///
/// MIRL visual-identity preservation: at camera.zoom ==
/// kPocFogReferenceZoom (= 13.0), zoomScale = 1.0 — shader noise
/// sampling is bit-identical to pre-FOG-19 formulation.
///
/// ## What's asserted
///
/// 1. STATIC source: `_FogPainter.paint()` source contains
///    `import 'dart:math'`, references `kPocFogReferenceZoom`, computes
///    `math.pow(2`, and forwards `zoomScale:` to `shaderRenderer.render(...)`.
/// 2. BEHAVIOURAL: at zoom == kPocFogReferenceZoom (=13.0), the forwarded
///    `zoomScale` is `1.0` (within 1e-9). At zoom 14, `zoomScale ≈ 2.0`.
///    At zoom 15 (== kPocMaxZoom), `zoomScale ≈ 4.0`.
void main() {
  group('FOG-19 (Plan 03.1-14 Task B) — uZoomScale uniform forwarded by _FogPainter.paint()', () {
    test('STATIC source: _FogPainter.paint() imports dart:math and references kPocFogReferenceZoom', () {
      final source = File('lib/presentation/widgets/fog_layer.dart').readAsStringSync();
      expect(
        source,
        contains("import 'dart:math'"),
        reason: 'FOG-19 (Plan 03.1-14 Task B): _FogPainter.paint() must import dart:math to compute math.pow(2, ...).',
      );
      expect(
        source,
        contains('kPocFogReferenceZoom'),
        reason: 'FOG-19: _FogPainter.paint() must reference kPocFogReferenceZoom to compute the uZoomScale forwarding factor.',
      );
      expect(source, contains('math.pow(2'), reason: 'FOG-19 forwards `pow(2, camera.zoom - kPocFogReferenceZoom)`.');
      expect(source, contains('zoomScale:'), reason: 'FOG-19 forwards zoomScale: as a named arg to shaderRenderer.render(...).');
    });

    testWidgets('BEHAVIOURAL: at zoom == kPocFogReferenceZoom, forwarded zoomScale is 1.0', (tester) async {
      final renderer = await _captureZoomScaleAtZoom(tester, kPocFogReferenceZoom);
      expect(
        renderer.renders.last.zoomScale,
        closeTo(1.0, 1e-9),
        reason:
            'FOG-19 visual-identity-preservation: at camera.zoom == kPocFogReferenceZoom (=13.0), '
            'uZoomScale must be 1.0 — the shader noise sampling is bit-identical to the pre-fix '
            'formulation (MIRL visual-identity rule per CLAUDE.md `# MIRL solution` updated 2026-05-04).',
      );
    });

    testWidgets('BEHAVIOURAL: at zoom 14 (one above reference), forwarded zoomScale is 2.0', (tester) async {
      final renderer = await _captureZoomScaleAtZoom(tester, 14.0);
      expect(
        renderer.renders.last.zoomScale,
        closeTo(2.0, 1e-9),
        reason:
            'FOG-19: at camera.zoom = 14 (one above kPocFogReferenceZoom = 13), uZoomScale = pow(2, 1) = 2.0. '
            'If this assertion fails, the forwarding formula is incorrect.',
      );
    });

    testWidgets('BEHAVIOURAL: at zoom 15 (two above reference), forwarded zoomScale is 4.0', (tester) async {
      final renderer = await _captureZoomScaleAtZoom(tester, 15.0);
      expect(
        renderer.renders.last.zoomScale,
        closeTo(4.0, 1e-9),
        reason:
            'FOG-19: at camera.zoom = 15 (two above kPocFogReferenceZoom = 13), '
            'uZoomScale = pow(2, 2) = 4.0. If this assertion fails, the forwarding formula is incorrect.',
      );
    });
  });
}

/// Mounts a FogLayer with `RecordingFogShaderRenderer`, drives the
/// camera to [zoom] at Melun, settles the SDF future, paints once, and
/// returns the renderer for inspection.
Future<RecordingFogShaderRenderer> _captureZoomScaleAtZoom(WidgetTester tester, double zoom) async {
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
            options: MapOptions(initialCenter: const LatLng(48.5397, 2.6553), initialZoom: zoom),
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
  await tester.runAsync(() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pump();

  final painter = _findFogPainter(tester);
  painter.paint(_MockCanvas(), const Size(400, 800));
  expect(renderer.renders, isNotEmpty, reason: 'paint() must run through the renderer at least once.');
  return renderer;
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
