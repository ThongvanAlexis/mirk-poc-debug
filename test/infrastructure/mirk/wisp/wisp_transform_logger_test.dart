// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_transform_logger.dart';

/// WISP-05 — RED test scaffold for [WispTransformLogger].
///
/// Plan 04-01 (Wave 0) ships these tests RED against the stub whose
/// methods throw [UnimplementedError]. Plan 04-02 flips them GREEN by
/// porting the per-second JSONL rollup behaviour modelled on
/// [FogTransformLogger] (FOG-10).
///
/// Test shape mirrors `test/infrastructure/mirk/fog_transform_logger_test.dart`
/// verbatim — setUpAll Logger.root.level = ALL; per-test
/// `Logger.root.onRecord.where(...)` subscription; addTearDown sub.cancel.
/// Adapted to the WISP record fields (activeCount, meanAge, latBounds,
/// lonBounds, screenXBounds, screenYBounds, spawnRatePerSecond).
void main() {
  setUpAll(() {
    Logger.root.level = Level.ALL;
  });

  group('WispTransformLogger (WISP-05)', () {
    test(
      'recordPaint buffers; emits one JSONL rollup per active second with min/median/max for 8 doubles + sampleCount + epochSecond + activeCount + spawnRatePerSecond',
      () async {
        final captured = <LogRecord>[];
        final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.wisp').listen(captured.add);
        try {
          // Test seam: 100 ms interval keeps the suite fast.
          final logger = WispTransformLogger(rollupInterval: const Duration(milliseconds: 100));
          // RED: start throws UnimplementedError.
          logger.start();

          // Three synthetic paint observations — predictable values so
          // min/median/max are deterministic.
          logger.recordPaint(
            activeCount: 10,
            meanAge: 0.1,
            latBounds: (48.5395, 48.5399),
            lonBounds: (2.6551, 2.6555),
            screenXBounds: (100.0, 200.0),
            screenYBounds: (300.0, 400.0),
            spawnRatePerSecond: 5.0,
          );
          logger.recordPaint(
            activeCount: 20,
            meanAge: 0.2,
            latBounds: (48.5390, 48.5400),
            lonBounds: (2.6550, 2.6560),
            screenXBounds: (110.0, 210.0),
            screenYBounds: (310.0, 410.0),
            spawnRatePerSecond: 5.0,
          );
          logger.recordPaint(
            activeCount: 30,
            meanAge: 0.3,
            latBounds: (48.5380, 48.5410),
            lonBounds: (2.6540, 2.6570),
            screenXBounds: (120.0, 220.0),
            screenYBounds: (320.0, 420.0),
            spawnRatePerSecond: 5.0,
          );

          // Wait at least 2 rollup intervals so the timer fires.
          await Future<void>.delayed(const Duration(milliseconds: 250));
          logger.stop();

          expect(captured, hasLength(greaterThanOrEqualTo(1)));
          final firstLine = captured.first.message;
          final decoded = json.decode(firstLine) as Map<String, Object?>;

          // The rollup MUST include epochSecond + sampleCount + the 8
          // diagnostic fields' min/median/max plus per-rollup activeCount
          // and spawnRatePerSecond fields.
          expect(decoded.keys, containsAll(<String>['epochSecond', 'sampleCount']));
          expect(decoded['sampleCount'], 3);
        } finally {
          await sub.cancel();
        }
      },
    );

    test('idle seconds emit no log line — WISP-05', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.wisp').listen(captured.add);
      try {
        final logger = WispTransformLogger(rollupInterval: const Duration(milliseconds: 100));
        // RED: throws UnimplementedError.
        logger.start();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        logger.stop();
        expect(captured, isEmpty);
      } finally {
        await sub.cancel();
      }
    });

    test('buffer caps at kPocWispTransformBufferMaxSamples — oldest dropped FIFO — WISP-05', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.wisp').listen(captured.add);
      try {
        final logger = WispTransformLogger(rollupInterval: const Duration(milliseconds: 100));
        // RED: throws UnimplementedError.
        logger.start();

        // Inject 300 samples — only the last 240 should remain.
        for (var i = 0; i < 300; i++) {
          logger.recordPaint(
            activeCount: i,
            meanAge: i.toDouble() * 0.001,
            latBounds: (48.5390 + i * 0.00001, 48.5410 + i * 0.00001),
            lonBounds: (2.6550 + i * 0.00001, 2.6570 + i * 0.00001),
            screenXBounds: (i.toDouble(), i.toDouble() + 100.0),
            screenYBounds: (i.toDouble() + 200.0, i.toDouble() + 300.0),
            spawnRatePerSecond: 0.0,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        logger.stop();

        expect(captured, isNotEmpty);
        final decoded = json.decode(captured.first.message) as Map<String, Object?>;
        expect(decoded['sampleCount'], 240);
      } finally {
        await sub.cancel();
      }
    });

    test('stop flushes pending samples even before a timer tick — WISP-05', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.wisp').listen(captured.add);
      try {
        // Long interval ensures the timer never fires during this test.
        final logger = WispTransformLogger(rollupInterval: const Duration(seconds: 10));
        // RED: throws UnimplementedError.
        logger.start();
        logger.recordPaint(
          activeCount: 42,
          meanAge: 0.5,
          latBounds: (48.5397, 48.5398),
          lonBounds: (2.6553, 2.6554),
          screenXBounds: (1024.0, 1124.0),
          screenYBounds: (768.0, 868.0),
          spawnRatePerSecond: 7.5,
        );
        logger.stop();
        // stop() emits via _log.info synchronously; onRecord delivery is
        // microtask-scheduled — pump the event loop once.
        await Future<void>.delayed(Duration.zero);
        expect(captured, hasLength(1));
        final decoded = json.decode(captured.first.message) as Map<String, Object?>;
        expect(decoded['sampleCount'], 1);
      } finally {
        await sub.cancel();
      }
    });
  });
}
