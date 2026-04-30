// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'file_logger.dart';

/// Forces [FileLogger] to flush whenever the app transitions OUT of
/// `resumed` (paused / inactive / hidden / detached) — the moments at
/// which iOS / Android may suspend or kill the process and the in-memory
/// buffer would otherwise vanish. Resumed → no flush needed because the
/// buffer was just drained.
///
/// Why a dedicated class instead of an inline anonymous observer in
/// `main.dart`: the observer needs a structural unit test (simulate
/// `didChangeAppLifecycleState(paused)`, assert flush fired) without
/// pulling in a real Flutter binding lifetime. Injecting [_flushCallback]
/// lets the test assert flush count via a mock callback.
class FileLoggerLifecycleObserver with WidgetsBindingObserver {
  /// Default constructor — wires the observer to [FileLogger.flush]. Used
  /// from `main.dart` bootstrap.
  FileLoggerLifecycleObserver() : _flushCallback = FileLogger.flush;

  /// Test-only constructor accepting a custom flush callback so tests can
  /// count flush invocations without standing up the real sink.
  @visibleForTesting
  FileLoggerLifecycleObserver.withFlush(Future<void> Function() flushCallback) : _flushCallback = flushCallback;

  final Future<void> Function() _flushCallback;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // `resumed` → buffer was just drained on the previous transition out
    // of resumed; flushing again would be a no-op syscall. Every other
    // state is a potential suspend / kill boundary where the buffer
    // could be lost — flush.
    if (state == AppLifecycleState.resumed) return;
    // Fire-and-forget — `didChangeAppLifecycleState` is sync. The flush
    // itself is best-effort: if the OS kills the process before fsync
    // returns, we still wrote everything we had at this instant which
    // is the best we can do from userspace.
    unawaited(_flushCallback());
  }
}
