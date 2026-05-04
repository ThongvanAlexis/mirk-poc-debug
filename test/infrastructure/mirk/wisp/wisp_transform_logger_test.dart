// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_transform_logger.dart';

/// WISP-05 — GREEN tests for [WispTransformLogger].
///
/// Plan 04-01 (Wave 0) shipped these tests RED against the stub whose
/// methods threw [UnimplementedError]. Plan 04-02 lands the impl and
/// flips them GREEN — same pattern as `FogTransformLogger` (FOG-10).
///
/// Test shape mirrors `test/infrastructure/mirk/fog_transform_logger_test.dart`
/// verbatim — setUpAll Logger.root.level = ALL; per-test
/// `Logger.root.onRecord.where(...)` subscription; `try/finally` sub.cancel.
/// Adapted to the 9-field WISP record (activeCount + meanAge + 4 lat/lon
/// bounds + 4 screenX/Y bounds + spawnRatePerSecond).
///
/// Determinism guarantees:
///  * `meanAge` fixture values are 8 distinct doubles whose sorted-median
///    (index `length ~/ 2 == 4`) is the 5th element exactly — bit-exact
///    `toStringAsFixed(6)` assertions hold.
///  * `epochSecond` is asserted only as `> 1.7e9` (guards against test
///    crossing a second boundary, same defence as FrameDeltaProbe Test #7).
///  * Test 3 (FIFO drop) uses a 60-s rollup interval so the periodic timer
///    never fires; `stop()` synchronously triggers `_emitRollup()` against
///    the buffer-capped sample list.
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
          logger.start();

          // Eight synthetic paint observations — meanAge values picked so
          // sorted-median (sorted[8 ~/ 2] = sorted[4]) lands on 0.5 exactly.
          // activeCount runs 10..17 (max=17, mean=13.5).
          // lat/lon/screen bounds held constant across all 8 paints so
          // sorted-median equals the constant — bit-exact assertions hold.
          for (var i = 0; i < 8; i++) {
            logger.recordPaint(
              activeCount: 10 + i,
              meanAge: 0.1 + i * 0.1,
              latBounds: (48.5390, 48.5410),
              lonBounds: (2.6550, 2.6570),
              screenXBounds: (100.0, 200.0),
              screenYBounds: (300.0, 400.0),
              spawnRatePerSecond: 5.0,
            );
          }

          // Wait at least 2 rollup intervals so the timer fires deterministically.
          await Future<void>.delayed(const Duration(milliseconds: 250));
          logger.stop();

          expect(captured, hasLength(greaterThanOrEqualTo(1)));
          final firstLine = captured.first.message;
          final decoded = json.decode(firstLine) as Map<String, Object?>;

          // The rollup MUST carry epochSecond + sampleCount + the 9 diagnostic
          // fields' min/median/max plus per-rollup activeCount aggregates.
          expect(
            decoded.keys,
            containsAll(<String>[
              'epochSecond',
              'sampleCount',
              'activeCountMax',
              'activeCountMean',
              'meanAgeMin',
              'meanAgeMedian',
              'meanAgeMax',
              'latMinMin',
              'latMinMedian',
              'latMinMax',
              'latMaxMin',
              'latMaxMedian',
              'latMaxMax',
              'lonMinMin',
              'lonMinMedian',
              'lonMinMax',
              'lonMaxMin',
              'lonMaxMedian',
              'lonMaxMax',
              'screenXMinMin',
              'screenXMinMedian',
              'screenXMinMax',
              'screenXMaxMin',
              'screenXMaxMedian',
              'screenXMaxMax',
              'screenYMinMin',
              'screenYMinMedian',
              'screenYMinMax',
              'screenYMaxMin',
              'screenYMaxMedian',
              'screenYMaxMax',
              'spawnRatePerSecondMin',
              'spawnRatePerSecondMedian',
              'spawnRatePerSecondMax',
            ]),
          );

          expect(decoded['sampleCount'], 8);
          expect(decoded['activeCountMax'], 17);
          expect(decoded['activeCountMean'], '13.500000');

          // meanAge sorted = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8].
          // length ~/ 2 = 4 → sorted[4] = 0.5 → "0.500000".
          expect(decoded['meanAgeMin'], '0.100000');
          expect(decoded['meanAgeMedian'], '0.500000');
          expect(decoded['meanAgeMax'], '0.800000');

          // Constant bounds across all 8 paints → min == median == max.
          expect(decoded['latMinMedian'], '48.539000');
          expect(decoded['latMaxMedian'], '48.541000');
          expect(decoded['lonMinMedian'], '2.655000');
          expect(decoded['lonMaxMedian'], '2.657000');
          expect(decoded['screenXMinMedian'], '100.000000');
          expect(decoded['screenXMaxMedian'], '200.000000');
          expect(decoded['screenYMinMedian'], '300.000000');
          expect(decoded['screenYMaxMedian'], '400.000000');
          expect(decoded['spawnRatePerSecondMedian'], '5.000000');

          // epochSecond > 1.7e9 — guards against a regression to a Stopwatch-derived
          // (small-magnitude) clock; same defence as FrameDeltaProbe Test #7.
          final epochSecond = decoded['epochSecond']! as int;
          expect(epochSecond, greaterThan(1700000000));

          // After emit, buffer is cleared. One more paint + stop() should
          // emit a second rollup with sampleCount == 1.
          final captured2BeforeIdx = captured.length;
          logger.start();
          logger.recordPaint(
            activeCount: 99,
            meanAge: 0.9,
            latBounds: (48.5390, 48.5410),
            lonBounds: (2.6550, 2.6570),
            screenXBounds: (100.0, 200.0),
            screenYBounds: (300.0, 400.0),
            spawnRatePerSecond: 0.0,
          );
          logger.stop();
          await Future<void>.delayed(Duration.zero);
          expect(captured.length, captured2BeforeIdx + 1);
          final secondDecoded = json.decode(captured.last.message) as Map<String, Object?>;
          expect(secondDecoded['sampleCount'], 1);
          expect(secondDecoded['activeCountMax'], 99);
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
        logger.start();
        // ≥ 2 timer ticks elapse with no recordPaint calls.
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
        // Long interval ensures the periodic timer never fires during this test;
        // stop() synchronously emits the FIFO-trimmed buffer.
        final logger = WispTransformLogger(rollupInterval: const Duration(seconds: 60));
        logger.start();

        // Inject 245 samples with monotonically increasing activeCount (0..244).
        // Buffer cap is 240 — oldest 5 (activeCount 0..4) are dropped FIFO.
        // Surviving samples have activeCount 5..244 → max == 244, sampleCount == 240.
        for (var i = 0; i < 245; i++) {
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
        logger.stop();
        // stop() emits via _log.info synchronously; pump the event loop once
        // to deliver the onRecord microtask.
        await Future<void>.delayed(Duration.zero);

        expect(captured, hasLength(1));
        final decoded = json.decode(captured.first.message) as Map<String, Object?>;
        expect(decoded['sampleCount'], 240);
        // activeCount 0..4 dropped; max in remaining buffer is 244.
        expect(decoded['activeCountMax'], 244);
      } finally {
        await sub.cancel();
      }
    });

    test('stop flushes pending samples even before a timer tick — WISP-05', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.wisp').listen(captured.add);
      try {
        // Long interval ensures the timer never fires during this test —
        // proves stop() emits the final rollup synchronously.
        final logger = WispTransformLogger(rollupInterval: const Duration(seconds: 10));
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
        logger.recordPaint(
          activeCount: 43,
          meanAge: 0.6,
          latBounds: (48.5397, 48.5398),
          lonBounds: (2.6553, 2.6554),
          screenXBounds: (1024.0, 1124.0),
          screenYBounds: (768.0, 868.0),
          spawnRatePerSecond: 7.5,
        );
        logger.recordPaint(
          activeCount: 44,
          meanAge: 0.7,
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
        expect(decoded['sampleCount'], 3);
        expect(decoded['activeCountMax'], 44);
        expect(decoded['screenXMinMedian'], '1024.000000');
        expect(decoded['spawnRatePerSecondMedian'], '7.500000');
      } finally {
        await sub.cancel();
      }
    });

    test('computeStats returns (first, middle, last) on a non-empty sorted list — WISP-05', () {
      // Direct call: matches FogTransformLogger.computeStats contract.
      final stats = WispTransformLogger.computeStats(<double>[1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(stats.$1, 1.0);
      // length ~/ 2 == 2 → index 2 → 3.0.
      expect(stats.$2, 3.0);
      expect(stats.$3, 5.0);
    });
  });
}
