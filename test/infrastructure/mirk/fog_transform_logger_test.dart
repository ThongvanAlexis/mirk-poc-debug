// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';
import 'dart:math' show Point;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';

/// FOG-10 — FogTransformLogger 1-second JSONL rollup of per-paint
/// Canvas-transform vs camera-pixelOrigin vs applied-uOffset diagnostics.
///
/// Plan 03.1-01 ships the per-second rollup + JSONL emission via
/// `Logger('infrastructure.mirk.fog_transform')`. Tests use a shorter
/// [rollupInterval] test seam to keep the suite fast — the production default
/// is 1 s ([kPocFogTransformLogRollupSeconds]).
///
/// All four tests follow the [SdfRebuildLogger] test shape verbatim
/// (setUpAll Logger.root.level = ALL; Logger.root.onRecord.where filter
/// subscription; addTearDown sub.cancel()) — adapted for the 8-field
/// fog-transform sample shape.
void main() {
  // Logger.root must be at ALL for INFO-level rollup emissions to surface
  // through Logger.root.onRecord; default Level.WARNING swallows INFO lines.
  setUpAll(() {
    Logger.root.level = Level.ALL;
  });

  group('FogTransformLogger (FOG-10)', () {
    test('recordPaint buffers samples; emits one JSONL rollup per active second with min/median/max for 8 diagnostic fields', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.fog_transform').listen(captured.add);
      try {
        // Test seam: 100 ms interval keeps the suite fast; production default 1 s.
        final logger = FogTransformLogger(rollupInterval: const Duration(milliseconds: 100));
        logger.start();
        // Three synthetic paint observations with predictable pixelOriginX values 100/200/300
        // so min=100.0, median=sorted[3~/2]=sorted[1]=200.0, max=300.0.
        logger.recordPaint(
          canvasTransform: _matrixWithTranslation(tx: 0.0, ty: 0.0),
          cameraPixelOrigin: const Point<double>(100.0, 50.0),
          cameraCenter: const LatLng(48.5397, 2.6553),
          appliedUOffset: (0.1, 0.2),
          metersPerPixel: 12.66,
        );
        logger.recordPaint(
          canvasTransform: _matrixWithTranslation(tx: 0.0, ty: 0.0),
          cameraPixelOrigin: const Point<double>(200.0, 60.0),
          cameraCenter: const LatLng(48.5397, 2.6553),
          appliedUOffset: (0.2, 0.3),
          metersPerPixel: 6.33,
        );
        logger.recordPaint(
          canvasTransform: _matrixWithTranslation(tx: 0.0, ty: 0.0),
          cameraPixelOrigin: const Point<double>(300.0, 70.0),
          cameraCenter: const LatLng(48.5397, 2.6553),
          appliedUOffset: (0.3, 0.4),
          metersPerPixel: 3.16,
        );
        // Wait at least 2 rollup intervals so the timer fires deterministically.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        logger.stop();
        expect(captured, hasLength(greaterThanOrEqualTo(1)));
        final firstLine = captured.first.message;
        final decoded = json.decode(firstLine) as Map<String, Object?>;
        // 29 keys: epochSecond + sampleCount + 9 fields × (Min,Median,Max).
        // FOG-18 (Plan 03.1-12 + Walk #5 diagnostic-verification): metersPerPixel
        // field added to the rollup at Plan 03.1-13 Task 1.
        expect(
          decoded.keys,
          containsAll(<String>[
            'epochSecond',
            'sampleCount',
            'canvasTxMin',
            'canvasTxMedian',
            'canvasTxMax',
            'canvasTyMin',
            'canvasTyMedian',
            'canvasTyMax',
            'pixelOriginXMin',
            'pixelOriginXMedian',
            'pixelOriginXMax',
            'pixelOriginYMin',
            'pixelOriginYMedian',
            'pixelOriginYMax',
            'centerLatMin',
            'centerLatMedian',
            'centerLatMax',
            'centerLonMin',
            'centerLonMedian',
            'centerLonMax',
            'uOffsetXMin',
            'uOffsetXMedian',
            'uOffsetXMax',
            'uOffsetYMin',
            'uOffsetYMedian',
            'uOffsetYMax',
            'metersPerPixelMin',
            'metersPerPixelMedian',
            'metersPerPixelMax',
          ]),
        );
        expect(decoded['sampleCount'], 3);
        expect(decoded['pixelOriginXMin'], '100.000000');
        expect(decoded['pixelOriginXMedian'], '200.000000');
        expect(decoded['pixelOriginXMax'], '300.000000');
        // FOG-18 metersPerPixel signature: sorted ascending [3.16, 6.33, 12.66] → min=3.16, median=6.33, max=12.66.
        expect(decoded['metersPerPixelMin'], '3.160000');
        expect(decoded['metersPerPixelMedian'], '6.330000');
        expect(decoded['metersPerPixelMax'], '12.660000');
      } finally {
        await sub.cancel();
      }
    });

    test('idle seconds emit no log line', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.fog_transform').listen(captured.add);
      try {
        final logger = FogTransformLogger(rollupInterval: const Duration(milliseconds: 100));
        logger.start();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        logger.stop();
        expect(captured, isEmpty);
      } finally {
        await sub.cancel();
      }
    });

    test('buffer caps at kPocFogTransformBufferMaxSamples (240) — oldest dropped FIFO', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.fog_transform').listen(captured.add);
      try {
        final logger = FogTransformLogger(rollupInterval: const Duration(milliseconds: 100));
        logger.start();
        // Inject 300 samples with monotonically increasing pixelOriginX.
        // Only the last 240 should remain (samples 60..299 — min=60.0).
        for (var i = 0; i < 300; i++) {
          logger.recordPaint(
            canvasTransform: _matrixWithTranslation(tx: 0.0, ty: 0.0),
            cameraPixelOrigin: Point<double>(i.toDouble(), i.toDouble()),
            cameraCenter: const LatLng(48.5397, 2.6553),
            appliedUOffset: (i.toDouble() % 1.0, i.toDouble() % 1.0),
            metersPerPixel: 12.66,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        logger.stop();
        expect(captured, isNotEmpty);
        final decoded = json.decode(captured.first.message) as Map<String, Object?>;
        expect(decoded['sampleCount'], 240);
        // Oldest 60 (i = 0..59) dropped; remaining samples 60..299. Min = 60.0.
        expect(decoded['pixelOriginXMin'], '60.000000');
        expect(decoded['pixelOriginXMax'], '299.000000');
      } finally {
        await sub.cancel();
      }
    });

    test('stop flushes pending samples even before a timer tick', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.fog_transform').listen(captured.add);
      try {
        // Long interval ensures the timer never fires during this test —
        // proves stop() emits the final rollup synchronously.
        final logger = FogTransformLogger(rollupInterval: const Duration(seconds: 10));
        logger.start();
        logger.recordPaint(
          canvasTransform: _matrixWithTranslation(tx: 12.5, ty: 7.25),
          cameraPixelOrigin: const Point<double>(1024.0, 768.0),
          cameraCenter: const LatLng(48.5397, 2.6553),
          appliedUOffset: (0.5, 0.25),
          metersPerPixel: 3.16,
        );
        logger.stop();
        // stop() emits via _log.info synchronously; onRecord delivery is
        // microtask-scheduled — pump the event loop once.
        await Future<void>.delayed(Duration.zero);
        expect(captured, hasLength(1));
        final decoded = json.decode(captured.first.message) as Map<String, Object?>;
        expect(decoded['sampleCount'], 1);
        expect(decoded['pixelOriginXMedian'], '1024.000000');
        expect(decoded['canvasTxMedian'], '12.500000');
        expect(decoded['uOffsetXMedian'], '0.500000');
      } finally {
        await sub.cancel();
      }
    });
  });
}

/// Returns a 16-element column-major Float64List representing the 4×4
/// identity matrix — synthetic stand-in for a `Canvas.getTransform()` reading
/// at painter-local identity (RESEARCH §Pitfall D — `MobileLayerTransformer`
/// applies the camera transform via `Transform` widget at rotation=0, so the
/// inner painter's local Canvas is at identity).
Float64List _identityMatrix() => Float64List(16)
  ..[0] = 1.0
  ..[5] = 1.0
  ..[10] = 1.0
  ..[15] = 1.0;

/// Returns an identity 4×4 column-major matrix with translation `(tx, ty)`
/// loaded into the standard column-major translation slots `[12]` and `[13]`
/// — matches the layout `Canvas.getTransform()` returns on Flutter 3.41.
Float64List _matrixWithTranslation({required double tx, required double ty}) {
  final m = _identityMatrix();
  m[12] = tx;
  m[13] = ty;
  return m;
}
