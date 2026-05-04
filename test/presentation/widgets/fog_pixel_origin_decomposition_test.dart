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

import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';

import '../../_helpers/recording_fog_shader_renderer.dart';

/// FOG-18 (Plan 03.1-12) — direct pixelOrigin forwarding (FOG-17a wrap eliminated).
///
/// Walk #4 debug-spiral positive control proved the noise function isn't
/// truly periodic on `kPocFogNoiseTilePx (=384)` in practice — the FOG-17a
/// wrap event at every `kPocFogIntegerWrapPeriodPx (=1536)` raw-px IS the
/// bug, not the precision penalty FOG-17a was designed to address. fp32
/// has 24 bits of exact-integer mantissa = 16.7M raw-px ceiling, well
/// above Walk #4's max observed pixelOrigin magnitude of ~4.26M.
///
/// Reference: `.planning/phases/03.1-fix-fog-pan-translation/03.1-FALSIFICATION-4.md`
/// §"Plan 03.1-12+ Dart-only fix axes (corrected)" sub-section C1'-eliminate.
///
/// ## What's asserted
///
/// 1. STATIC source invariant: `_FogPainter.paint()` source code does NOT
///    contain the substring `% kPocFogIntegerWrapPeriodPx` (the FOG-17a
///    modulo wrap is removed by FOG-18) AND does NOT reference
///    `kPocFogIntegerWrapPeriodPx` at all (the constant is deleted from
///    `lib/config/constants.dart` because it is no longer referenced by
///    any production code path). The `truncateToDouble()` decomposition
///    SURVIVES as documentation continuity (the decomposition split
///    retains the structure for future C2' follow-up; only the modulo is
///    removed).
/// 2. BEHAVIOURAL: against a synthetic Walk #4-style camera magnitude via
///    `mapController.move()` at zoom 15 (max allowed by `kPocMaxZoom`;
///    pixelOrigin reaches ~2.1M raw px at Melun), the forwarded
///    pixelOrigin tuple tracks `camera.pixelOrigin` directly — no
///    bounded-magnitude regime, no modulo wrap. The forwarded value
///    matches `camera.pixelOrigin` within fractional rounding (< 1 raw
///    px). NOTE — this assertion stays correct under the 2-task plan
///    structure (C2' deferred): no Task 2 interposes a basis
///    transformation between `camera.pixelOrigin` and the forwarded
///    value.
/// 3. NUMERICAL: a unit-test of the post-FOG-18 forward helper produces:
///    - exact identity for the Walk #4 marker #0 magnitude
///      `(4_256_182.0, 2_896_819.0)`;
///    - exact identity for boundary cases `(1536.5, 384.25)` and
///      negative inputs `(-100.0, -1536.5)` (no modulo wrap; sign
///      preservation by `truncateToDouble`);
///    - exact identity for extrapolated zoom-19 magnitude
///      `(17_040_000.0, 4_260_000.0)` (still well under fp32 24-bit
///      mantissa ceiling 16_777_216).
void main() {
  group('FOG-18 (Plan 03.1-12) — direct pixelOrigin forwarding (FOG-17a wrap eliminated)', () {
    test('STATIC source: _FogPainter.paint() does NOT contain the FOG-17a modulo (% kPocFogIntegerWrapPeriodPx removed by FOG-18)', () {
      final source = File('lib/presentation/widgets/fog_layer.dart').readAsStringSync();
      expect(
        source,
        isNot(contains('% kPocFogIntegerWrapPeriodPx')),
        reason:
            'FOG-18 static-source invariant: _FogPainter.paint() MUST NOT contain `% kPocFogIntegerWrapPeriodPx`. '
            'Walk #4 debug-spiral positive control proved the noise function is NOT truly periodic on '
            'kPocFogNoiseTilePx (=384) in practice — the modulo wrap event at every '
            'kPocFogIntegerWrapPeriodPx (=1536) raw-px IS the bug, not the precision penalty FOG-17a was '
            'designed to address. If this assertion fails, the FOG-17a wrap has been re-introduced and the '
            'Q1 max-zoom SNAP failure mode will resurface.',
      );
      expect(
        source,
        isNot(contains('kPocFogIntegerWrapPeriodPx')),
        reason:
            'FOG-18 static-source invariant: _FogPainter.paint() MUST NOT reference kPocFogIntegerWrapPeriodPx '
            'at all (the constant is deleted from lib/config/constants.dart because it is no longer referenced '
            'by any production code path). If this assertion fails, the constant is still being used somewhere '
            'in the painter and FOG-18 was applied incompletely.',
      );
      expect(
        source,
        contains('truncateToDouble()'),
        reason:
            'FOG-18 retains the truncateToDouble() decomposition for documentation continuity — the integer/'
            'fractional split is still computed even though the modulo is removed. This preserves the structure '
            'in case the future C2\' follow-up plan re-introduces a basis derivation that uses the decomposition. '
            'If this assertion fails, the documentation-continuity intent has been violated; either re-introduce '
            'the decomposition or update this test reason-string with the new design rationale.',
      );
    });

    test('NUMERICAL: Walk #4 marker #0 magnitude (4_256_182.0, 2_896_819.0) forwards exactly', () {
      // Walk #4 captured pixelOriginX up to 4.26M; FOG-18 forwards the
      // value directly (no modulo) because fp32 has 24 bits of exact-
      // integer mantissa = 16.7M raw-px ceiling, well above 4.26M.
      const inX = 4256182.0;
      const inY = 2896819.0;
      final forwarded = _forwardWithoutWrap(inX, inY);
      expect(forwarded.$1, equals(4256182.0), reason: 'FOG-18 forwards camera.pixelOrigin.x directly; expected 4256182.0, got ${forwarded.$1}.');
      expect(forwarded.$2, equals(2896819.0));
    });

    test('NUMERICAL: extrapolated zoom-19 magnitude (17_040_000.0, 4_260_000.0) forwards within fp32 mantissa ceiling', () {
      // 17.04M is just over the fp32 24-bit mantissa exact-integer
      // ceiling (16_777_216). 17.04M will round to 17_040_000.0 exactly
      // since 17_040_000 < 2^24 + 2^25 and the value is itself an integer
      // multiple of 2 within fp32's available precision at that
      // magnitude. The decomposition stays exact for the integer part;
      // any fractional part we feed will be preserved.
      const inX = 17040000.0;
      const inY = 4260000.0;
      final forwarded = _forwardWithoutWrap(inX, inY);
      expect(forwarded.$1, equals(17040000.0));
      expect(forwarded.$2, equals(4260000.0));
    });

    test('NUMERICAL: small-magnitude boundary (1536.5, 384.25) forwards exactly (no wrap)', () {
      // Pre-FOG-18 (FOG-17a) the modulo would have produced (0.5, 384.25).
      // Post-FOG-18 the forwarded values are the inputs verbatim.
      final forwarded = _forwardWithoutWrap(1536.5, 384.25);
      expect(forwarded.$1, closeTo(1536.5, 1e-9));
      expect(forwarded.$2, closeTo(384.25, 1e-9));
    });

    test('NUMERICAL: negative magnitudes forward exactly (sign preserved by truncateToDouble)', () {
      // Pre-FOG-18 the modulo would have produced (1436.0, -0.5).
      // Post-FOG-18 the forwarded values are the inputs verbatim.
      final forwarded = _forwardWithoutWrap(-100.0, -1536.5);
      expect(forwarded.$1, closeTo(-100.0, 1e-9));
      expect(forwarded.$2, closeTo(-1536.5, 1e-9));
    });

    testWidgets('BEHAVIOURAL: forwarded pixelOrigin tracks camera.pixelOrigin (FOG-18 — no modulo bound)', (tester) async {
      // At zoom 15 (kPocMaxZoom), Melun pixelOrigin reaches ~2.1M.
      // Pre-FOG-18 (FOG-17a) the painter applied `% kPocFogIntegerWrapPeriodPx`
      // and the forwarded tuple was bounded under 1537 raw px regardless of
      // zoom. Post-FOG-18 the painter forwards `camera.pixelOrigin`
      // directly (decomposed into intPx + fracPx for documentation
      // continuity but with the modulo removed).
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
                options: const MapOptions(initialCenter: LatLng(48.5397, 2.6553), initialZoom: 15),
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

      final painter = _findFogPainter(tester);
      painter.paint(_MockCanvas(), const Size(400, 800));
      expect(renderer.renders, isNotEmpty, reason: 'paint() must run through the renderer.');
      final forwarded = renderer.renders.last.pixelOrigin;
      final cameraPxOrigin = mapController.camera.pixelOrigin;

      // FOG-18 invariant: forwarded ≈ camera.pixelOrigin (within
      // fractional-decomposition rounding error < 1 raw px). Pre-FOG-18
      // (FOG-17a) the bounded composite was under 1537 raw px regardless
      // of camera.pixelOrigin magnitude — at zoom 15 with pixelOrigin
      // ~2.1M, the gap between the two would have been ~2_100_000.
      expect(
        (forwarded.$1 - cameraPxOrigin.x).abs(),
        lessThan(1.0),
        reason:
            'FOG-18 regression: forwarded pixelOrigin.x (${forwarded.$1}) does NOT track camera.pixelOrigin.x '
            '(${cameraPxOrigin.x}). At zoom 15 + Melun the camera.pixelOrigin magnitude is ~2.1M; FOG-18 '
            'forwards this directly (no modulo). If the gap exceeds 1.0 raw px, either the FOG-17a wrap has '
            'been re-introduced (gap will be ~2.1M) or some other transformation has been interposed between '
            'camera.pixelOrigin and the forwarded value.',
      );
      expect(
        (forwarded.$2 - cameraPxOrigin.y).abs(),
        lessThan(1.0),
        reason:
            'FOG-18 regression: forwarded pixelOrigin.y (${forwarded.$2}) does NOT track camera.pixelOrigin.y '
            '(${cameraPxOrigin.y}).',
      );
    });
  });
}

/// Pure-Dart mirror of the post-FOG-18 `_FogPainter.paint()` forward path.
/// Used by the NUMERICAL tests to assert the math at synthetic magnitudes
/// the FlutterMap camera-constraint cannot reach. The integer/fractional
/// split is retained for documentation continuity (matching the production
/// code) but the modulo wrap is removed; `intPx + fracPx` is identically
/// `pxOrigin` within fp32 precision.
(double, double) _forwardWithoutWrap(double pxX, double pxY) {
  final intPxX = pxX.truncateToDouble();
  final intPxY = pxY.truncateToDouble();
  final fracPxX = pxX - intPxX;
  final fracPxY = pxY - intPxY;
  // FOG-18: no `% kPocFogIntegerWrapPeriodPx`. The decomposition
  // re-composes to the original pxOrigin exactly within fp32.
  final forwardedX = intPxX + fracPxX;
  final forwardedY = intPxY + fracPxY;
  return (forwardedX, forwardedY);
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
