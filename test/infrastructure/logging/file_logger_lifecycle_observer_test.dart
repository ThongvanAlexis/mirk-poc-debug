// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirk_poc_debug/infrastructure/logging/file_logger_lifecycle_observer.dart';

void main() {
  group('FileLoggerLifecycleObserver', () {
    late int flushCallCount;
    late FileLoggerLifecycleObserver observer;

    setUp(() {
      flushCallCount = 0;
      observer = FileLoggerLifecycleObserver.withFlush(() async {
        flushCallCount++;
      });
    });

    test('flushes on paused', () async {
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      // unawaited Future inside the observer — let microtask drain.
      await Future<void>.delayed(Duration.zero);
      expect(flushCallCount, 1);
    });

    test('flushes on inactive', () async {
      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await Future<void>.delayed(Duration.zero);
      expect(flushCallCount, 1);
    });

    test('flushes on hidden', () async {
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await Future<void>.delayed(Duration.zero);
      expect(flushCallCount, 1);
    });

    test('flushes on detached', () async {
      observer.didChangeAppLifecycleState(AppLifecycleState.detached);
      await Future<void>.delayed(Duration.zero);
      expect(flushCallCount, 1);
    });

    test('does NOT flush on resumed', () async {
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(flushCallCount, 0, reason: 'Resumed transition MUST NOT trigger a flush — the buffer was just drained on the prior transition out of resumed.');
    });
  });
}
