// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import 'app.dart';
import 'infrastructure/logging/file_logger.dart';
import 'infrastructure/logging/file_logger_lifecycle_observer.dart';

/// Bootstrap entry — LOG-03 ordering invariant:
///
///   1. [WidgetsFlutterBinding.ensureInitialized] — required before any
///      platform-channel call (path_provider, package_info, etc).
///   2. `await FileLogger.bootstrap()` — opens the active log file BEFORE
///      [runApp]. Any [Logger] call from this point onward is persisted, so
///      a crash during widget tree construction is captured to disk.
///   3. [WidgetsBinding.instance.addObserver] with [FileLoggerLifecycleObserver]
///      — flushes the active log on app pause / inactive transitions so
///      iOS jetsam-driven page-cache eviction never loses the tail records.
///   4. [FlutterError.onError] + [runZonedGuarded] — CLAUDE.md top-level
///      handler pair. Flutter framework errors and uncaught zone errors both
///      route to a [Logger] at SHOUT level; the file logger persists them on
///      the same channel as application logs.
///   5. [runApp] inside the guarded zone — once we're inside the zone, any
///      uncaught async error in the widget tree is captured.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FileLogger.bootstrap();
  WidgetsBinding.instance.addObserver(FileLoggerLifecycleObserver());

  // CLAUDE.md top-level error handler — Flutter framework errors propagate
  // here (build failures, layout exceptions, gesture handler crashes).
  FlutterError.onError = (FlutterErrorDetails details) {
    Logger('flutter.error').shout('FlutterError', details.exception, details.stack);
  };

  runZonedGuarded<void>(() => runApp(const MirkPocApp()), (Object error, StackTrace stack) {
    Logger('zone.error').shout('Uncaught zone error', error, stack);
  });
}
