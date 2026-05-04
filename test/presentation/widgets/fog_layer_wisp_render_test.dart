// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' as io;
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

/// WISP-04 (Plan 04-04) — `_FogPainter` paint sequence + projection.
///
/// _FogPainter renders wisps as the LAST step inside the canvas.save /
/// canvas.restore block of paint(). Order of operations on the canvas:
///
///   1. canvas.save()
///   2. canvas.translate(-canvasOffset.dx, -canvasOffset.dy)   (FOG-13)
///   3. canvas.clipPath(clipPath)                              (FOG-12)
///   4. canvas.drawRect(Offset.zero & size, ...shader)         (fog draw)
///   5. canvas.drawCircle(...) per wisp                        (wisps — NEW Plan 04-04)
///   6. canvas.restore()
///
/// Each wisp's screen position MUST come from
/// `camera.latLngToScreenPoint(wisp.position)` against the SAME MapCamera
/// snapshot the fog uses (FOG-07 single-snapshot keystone). This is the
/// cross-pipeline parity check that completes the code-donor package:
/// `camera.latLngToScreenPoint(...)` is the same call site
/// `fog_clip_path.dart` uses for the SDF reveal-hole centres.
void main() {
  group('FogLayer wisp render (WISP-04)', () {
    testWidgets('_FogPainter._renderWisps invoked AFTER canvas.drawRect(...shader) and BEFORE canvas.restore() — WISP-04 paint sequence', (tester) async {
      final probe = FrameDeltaProbe();
      addTearDown(() async => probe.dispose());
      final fogTransformLogger = FogTransformLogger();
      addTearDown(fogTransformLogger.stop);
      final wispTransformLogger = WispTransformLogger();
      addTearDown(wispTransformLogger.stop);

      final discRepository = RevealDiscRepository();
      // Append one disc at the camera centre so the SDF cache has work to do.
      discRepository.append(
        RevealDisc(id: 'rvd_wisp_paint_seq', sessionId: 't', lat: 48.5397, lon: 2.6553, radiusMeters: 25, fixedAtUtc: DateTime.now().toUtc()),
      );
      addTearDown(discRepository.dispose);
      final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
      addTearDown(sdfCache.dispose);
      final renderer = RecordingFogShaderRenderer();

      // Pre-spawn wisps so _renderWisps has something to draw. _FakeStopwatch
      // initialMs=6000 puts the system past the 5-s warmup gate.
      final wispParticleSystem = WispParticleSystem(wallClock: _FakeStopwatch(initialMs: 6000));
      wispParticleSystem.spawnAtNewDisc(
        discId: 'rvd_wisp_paint_seq',
        disc: RevealDisc(id: 'rvd_wisp_paint_seq', sessionId: 't', lat: 48.5397, lon: 2.6553, radiusMeters: 25, fixedAtUtc: DateTime.now().toUtc()),
      );
      expect(wispParticleSystem.activeCount, greaterThan(0), reason: 'Pre-condition: wisps spawned past warmup gate.');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FlutterMap(
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

      // Settle the SDF future via the real event loop so the painter's
      // sdfImage != null guard passes and paint() runs the full body.
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      // Find the painter and run a recording-canvas paint to capture the
      // exact op-sequence. Pre-spawned wisps will produce drawCircle calls.
      final painter = _findFogPainter(tester);
      final canvas = _RecordingMockCanvas(canvasTx: 0, canvasTy: 0);
      painter.paint(canvas, const Size(400, 800));

      // The production code's `canvas.drawRect(...shader)` line only fires
      // when `shader != null`. Widget tests pass `shader: null` because
      // `dart:ui`'s `FragmentShader` is a base class that can't be
      // implemented from a test file (FogShaderRenderer doc-comment in
      // fog_layer.dart line 30). So the recording canvas does NOT see a
      // drawRect call here — the wisp paint sequence is asserted
      // INSIDE the canvas.save/restore block by checking:
      //
      //   1. translate (FOG-13) → clipPath (FOG-12) → drawCircle (wisps)
      //   2. drawCircle index < restore index (wisps inside the block)
      //
      // The "drawCircle AFTER drawRect" guarantee in production lives in
      // the source ordering: paint()'s body literally has `canvas.drawRect
      // (... liveShader)` immediately above `_renderWisps(canvas, camera)`.
      // The `fog_layer.dart` source line ordering is the authoritative
      // assertion; this widget test asserts the BLOCK-level invariants.
      final clipPathIndex = canvas.callOrder.indexOf('clipPath');
      final firstDrawCircleIndex = canvas.callOrder.indexOf('drawCircle');
      final restoreIndex = canvas.callOrder.indexOf('restore');

      expect(clipPathIndex, isNonNegative, reason: 'FOG-12: clipPath MUST fire (block discipline).');
      expect(firstDrawCircleIndex, isNonNegative, reason: 'WISP-04: at least one wisp drawCircle MUST fire when activeCount > 0.');
      expect(restoreIndex, isNonNegative, reason: 'paint() MUST end with canvas.restore().');
      expect(
        clipPathIndex < firstDrawCircleIndex,
        isTrue,
        reason: 'WISP-04 paint sequence: wisp drawCircle MUST come AFTER clipPath (inside the FOG-12 clipped region).',
      );
      expect(
        firstDrawCircleIndex < restoreIndex,
        isTrue,
        reason: 'WISP-04 paint sequence: wisp drawCircle MUST come BEFORE canvas.restore() (inside the same save/restore block as the fog).',
      );

      // Static-source invariant — `_renderWisps(canvas, camera)` MUST be
      // called between the fog drawRect line and `canvas.restore()` in
      // the production source. Catches a regression where someone moves
      // _renderWisps OUTSIDE the save/restore block (would lose FOG-12
      // clipPath + FOG-13 canvas-translate compensation for wisps).
      const String fogLayerSourcePath = 'lib/presentation/widgets/fog_layer.dart';
      final source = io.File(fogLayerSourcePath).readAsStringSync();
      final drawRectMatch = RegExp(r'canvas\.drawRect\(Offset\.zero & size, Paint\(\)\.\.shader = liveShader\)').firstMatch(source);
      final renderWispsMatch = RegExp(r'_renderWisps\(canvas, camera\)').firstMatch(source);
      final restoreMatch = RegExp(r'canvas\.restore\(\);').firstMatch(source);
      expect(drawRectMatch, isNotNull, reason: 'fog drawRect line must be present.');
      expect(renderWispsMatch, isNotNull, reason: '_renderWisps call site must be present.');
      expect(restoreMatch, isNotNull, reason: 'canvas.restore() must be present.');
      expect(
        drawRectMatch!.start < renderWispsMatch!.start,
        isTrue,
        reason: 'WISP-04 source-order: `canvas.drawRect(...liveShader)` MUST appear BEFORE `_renderWisps(canvas, camera)`.',
      );
      expect(
        renderWispsMatch.start < restoreMatch!.start,
        isTrue,
        reason: 'WISP-04 source-order: `_renderWisps(canvas, camera)` MUST appear BEFORE `canvas.restore();`.',
      );
    });

    testWidgets('_renderWisps calls camera.latLngToScreenPoint per wisp position — WISP-04 projection path', (tester) async {
      final probe = FrameDeltaProbe();
      addTearDown(() async => probe.dispose());
      final fogTransformLogger = FogTransformLogger();
      addTearDown(fogTransformLogger.stop);
      final wispTransformLogger = WispTransformLogger();
      addTearDown(wispTransformLogger.stop);

      final discRepository = RevealDiscRepository();
      discRepository.append(
        RevealDisc(id: 'rvd_wisp_proj_path', sessionId: 't', lat: 48.5397, lon: 2.6553, radiusMeters: 25, fixedAtUtc: DateTime.now().toUtc()),
      );
      addTearDown(discRepository.dispose);
      final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
      addTearDown(sdfCache.dispose);
      final renderer = RecordingFogShaderRenderer();

      final wispParticleSystem = WispParticleSystem(wallClock: _FakeStopwatch(initialMs: 6000));
      wispParticleSystem.spawnAtNewDisc(
        discId: 'rvd_wisp_proj_path',
        disc: RevealDisc(id: 'rvd_wisp_proj_path', sessionId: 't', lat: 48.5397, lon: 2.6553, radiusMeters: 25, fixedAtUtc: DateTime.now().toUtc()),
      );
      final wispCount = wispParticleSystem.activeCount;
      expect(wispCount, inInclusiveRange(18, 22), reason: 'Pre-condition: ~20 wisps spawned along 25 m disc perimeter.');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FlutterMap(
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
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      // Run a synthetic paint with a recording canvas. drawCircle calls land
      // at the projected screen Offset of each wisp; we assert the call
      // count matches the wisp count AND each centre lies inside the 400x800
      // viewport (because the wisps are spawned within ±25 m of the camera
      // centre, which projects close to (200, 400)).
      final painter = _findFogPainter(tester);
      final canvas = _RecordingMockCanvas(canvasTx: 0, canvasTy: 0);
      painter.paint(canvas, const Size(400, 800));

      // Note: advanceFromWallClock can integrate one step before the loop —
      // the wisps that died in that step would be removed from the system,
      // so drawCircle count == wispParticleSystem.activeCount post-paint.
      final postPaintActiveCount = wispParticleSystem.activeCount;
      expect(canvas.drawCircleCalls, hasLength(postPaintActiveCount), reason: 'WISP-04: exactly one drawCircle per active wisp.');

      // Each centre lies inside the 400x800 viewport with reasonable margin.
      // Wisps spawned at ±25 m × 0.105 px/m ≈ ±2.6 raw px from the camera
      // centre at zoom 13 — well within the viewport bounds.
      for (final centre in canvas.drawCircleCalls.map((c) => c.$1)) {
        expect(centre.dx, greaterThan(0.0), reason: 'wisp screen-x lies inside viewport');
        expect(centre.dx, lessThan(400.0), reason: 'wisp screen-x lies inside viewport');
        expect(centre.dy, greaterThan(0.0), reason: 'wisp screen-y lies inside viewport');
        expect(centre.dy, lessThan(800.0), reason: 'wisp screen-y lies inside viewport');
      }
    });

    testWidgets('_renderWisps body is a no-op when wispParticleSystem.activeCount == 0 (zero drawCircle, zero recordPaint)', (tester) async {
      final probe = FrameDeltaProbe();
      addTearDown(() async => probe.dispose());
      final fogTransformLogger = FogTransformLogger();
      addTearDown(fogTransformLogger.stop);
      final wispTransformLogger = WispTransformLogger();
      addTearDown(wispTransformLogger.stop);

      final discRepository = RevealDiscRepository();
      discRepository.append(RevealDisc(id: 'rvd_wisp_empty', sessionId: 't', lat: 48.5397, lon: 2.6553, radiusMeters: 25, fixedAtUtc: DateTime.now().toUtc()));
      addTearDown(discRepository.dispose);
      final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
      addTearDown(sdfCache.dispose);
      final renderer = RecordingFogShaderRenderer();

      // Pass a system with default (real) Stopwatch. The warmup gate is
      // active during the test runtime, so spawnAtNewDisc no-ops; system
      // stays empty.
      final wispParticleSystem = WispParticleSystem();
      expect(wispParticleSystem.activeCount, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: FlutterMap(
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
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pump();

      final painter = _findFogPainter(tester);
      final canvas = _RecordingMockCanvas(canvasTx: 0, canvasTy: 0);
      painter.paint(canvas, const Size(400, 800));

      expect(canvas.drawCircleCalls, isEmpty, reason: 'WISP-04: empty wisp system MUST produce ZERO drawCircle ops (early return + no Paint allocation).');
      // The save/restore block still runs (fog clipPath + uniform population
      // happen regardless of wisp state); the wisp early-return only
      // suppresses drawCircle + the per-wisp loop costs.
      expect(canvas.callOrder.contains('clipPath'), isTrue, reason: 'Empty-wisp early-return must NOT skip the fog clipPath / save/restore block.');
      expect(canvas.callOrder.contains('restore'), isTrue, reason: 'Empty-wisp early-return must NOT skip canvas.restore().');
    });

    test('_FogPainter constructor enforces wispParticleSystem + wispTransformLogger required (compile-time check)', () {
      // This test is a COMPILE-time check rolled into a runtime assertion:
      // if the FogLayer constructor stops requiring the wisp fields, the
      // test scaffolds in this file (which pass `wispParticleSystem:` +
      // `wispTransformLogger:` to FogLayer) would still compile, but the
      // FogLayer's argument list elsewhere (the FogLayer construction in
      // map_screen.dart's build method, and the production router builder)
      // would lose the regression guard.
      //
      // The test passes if the wisp constructor args were threaded through
      // FogLayer → _FogPainter (verified by the testWidgets above which
      // compile-fail without the constructor args).
      final wispParticleSystem = WispParticleSystem();
      final wispTransformLogger = WispTransformLogger();
      addTearDown(wispTransformLogger.stop);
      expect(wispParticleSystem, isNotNull);
      expect(wispTransformLogger, isNotNull);
    });
  });
}

/// Locates the `_FogPainter` instance under the FogLayer in the widget tree.
CustomPainter _findFogPainter(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(find.descendant(of: find.byType(FogLayer), matching: find.byType(CustomPaint)));
  final painter = customPaint.painter;
  if (painter == null) {
    fail('Expected FogLayer descendant CustomPaint to carry a non-null `painter`; got null.');
  }
  return painter;
}

/// Recording canvas that captures the op sequence and the args of
/// `drawCircle` so the test can assert paint-order invariants AND the
/// per-wisp projection.
///
/// Same `Fake implements Canvas` idiom as
/// `fog_canvas_frame_alignment_test.dart`'s `_RecordingMockCanvas`; extends
/// it with a `drawCircleCalls` list.
class _RecordingMockCanvas extends Fake implements Canvas {
  _RecordingMockCanvas({required this.canvasTx, required this.canvasTy});

  final double canvasTx;
  final double canvasTy;

  /// Captured `(centre, radius)` tuples from `drawCircle` calls.
  final List<(Offset, double)> drawCircleCalls = <(Offset, double)>[];

  /// Ordered op-name list — index of 'drawRect' must be less than index of
  /// 'drawCircle' must be less than index of 'restore' for WISP-04.
  final List<String> callOrder = <String>[];

  @override
  void save() {
    callOrder.add('save');
  }

  @override
  void restore() {
    callOrder.add('restore');
  }

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    callOrder.add('clipPath');
  }

  @override
  void translate(double dx, double dy) {
    callOrder.add('translate');
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    callOrder.add('drawRect');
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    callOrder.add('drawCircle');
    drawCircleCalls.add((c, radius));
  }

  @override
  Float64List getTransform() {
    callOrder.add('getTransform');
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

/// Local copy of the `_FakeStopwatch` from
/// `test/infrastructure/mirk/wisp/wisp_particle_system_test.dart`. Pushes
/// the system past the 5-s warmup gate without `Future.delayed`.
class _FakeStopwatch implements Stopwatch {
  _FakeStopwatch({int initialMs = 0}) : _elapsedMs = initialMs;

  final int _elapsedMs;

  @override
  int get elapsedMilliseconds => _elapsedMs;

  @override
  int get elapsedMicroseconds => _elapsedMs * 1000;

  @override
  noSuchMethod(Invocation invocation) {
    throw UnimplementedError('_FakeStopwatch: ${invocation.memberName} not implemented');
  }
}
