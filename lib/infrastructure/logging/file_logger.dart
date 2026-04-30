// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/constants.dart';

/// JSON-Lines file sink for the project logger.
///
/// One file per app launch under `<app_docs>/logs/yyyymmddTHHMMSSZ_logs.txt`
/// (UTC ISO-8601 basic — POC adaptation #1; differs from the parent's
/// local-time `yyyymmdd_hhmm.ss_logs.txt` so an iOS sideload in any
/// timezone produces an unambiguous wall-clock filename). At bootstrap,
/// oldest files are pruned until directory size < [kMaxLogsDirBytes].
/// Root log level is hardcoded to [Level.ALL] (POC adaptation #2 — LOG-02
/// always-verbose; replaces parent's `--dart-define=DEBUG` + SharedPreferences
/// gate which is dropped wholesale per POC adaptation #3).
///
/// Durability — each record performs `writeStringSync` + `flushSync` (real
/// `fsync(2)` per Dart docs) on a [RandomAccessFile] opened in
/// `FileMode.writeOnlyAppend`. The previous implementation used [IOSink] +
/// async `Stream.listen`, which suffered from two production-fatal defects:
///
///   1. `Stream.listen` does NOT await `async` callbacks, so two records
///      arriving back-to-back could re-enter the body before the first
///      `await sink.flush()` resolved → `StateError: StreamSink is bound`
///      → catch nulled the sink → ~99% of records dropped silently for the
///      rest of the session.
///   2. `IOSink.flush()` only flushes user-space → kernel page cache; iOS
///      jetsam (foreground RAM pressure during the 5.2 GB pmtiles install)
///      discards the page cache and records never reach flash.
///
/// Synchronous per-record `flushSync` eliminates both. Per-call overhead is
/// sub-millisecond on modern flash; acceptable for a single-user diagnostic
/// app. The eventual non-blocking architecture (ring buffer + flusher
/// isolate) is documented as a future evolution path.
class FileLogger {
  static RandomAccessFile? _raf;
  static String? _activeFilename;
  static StreamSubscription<LogRecord>? _subscription;

  /// Active log file absolute path, or null before [bootstrap] (or after [clearAll]).
  static String? get activeFilename => _activeFilename;

  /// Initialises the logger: opens today's file, prunes oldest files, sets
  /// [Logger.root] level, subscribes to the `LogRecord` stream.
  ///
  /// MUST be awaited before [runApp]. Idempotent: calling twice closes the
  /// previous handle and re-opens cleanly (covers dev hot-reload and tests
  /// that re-bootstrap between cases).
  static Future<void> bootstrap() async {
    // 1) POC adaptation #2 — always-verbose per LOG-02. Parent's
    //    --dart-define=DEBUG + SharedPreferences gate is dropped (POC
    //    adaptation #3).
    Logger.root.level = Level.ALL; // POC: always-verbose per LOG-02

    // 2) Resolve logs dir under <app_docs>/logs.
    final docsDir = await getApplicationDocumentsDirectory();
    final logsDir = Directory(p.join(docsDir.path, 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    // 3) Prune oldest files until directory size < kMaxLogsDirBytes.
    await _pruneToSizeLimit(logsDir);

    // 4) Compute today's filename and open it in writeOnlyAppend mode.
    final now = DateTime.now();
    final timestamp = _formatFilenameTimestamp(now);
    _activeFilename = p.join(logsDir.path, '${timestamp}_logs.txt');
    final file = File(_activeFilename!);

    // Idempotency: close previous handle + unsubscribe if bootstrap was
    // called twice (hot-reload / tests). Order: close → cancel.
    await _closeRafQuietly();
    await _subscription?.cancel();

    _raf = file.openSync(mode: FileMode.writeOnlyAppend);
    _subscription = Logger.root.onRecord.listen(_onRecord);

    // First record after bootstrap: capture the absolute path of the active
    // log file. iOS sandbox container UUIDs can shift between launches —
    // this lets us cross-check, at read-time, that the path we are reading
    // from matches the path that was written to at bootstrap-time. Routed
    // through the standard pipeline so it lives in the JSONL file itself.
    Logger('infrastructure.logging.file_logger').info('FileLogger bootstrap — activeFilename=$_activeFilename');
  }

  /// Cheap no-op safeguard for callers that historically forced a flush
  /// before handing the file path to another process (share-sheet, external
  /// editor) or before lifecycle suspension. Now that every record is
  /// `flushSync`'d at write-time, there is no buffered data to drain — but
  /// retaining this entry-point keeps the share-sheet + lifecycle observer
  /// call-sites unchanged. Returns immediately.
  static Future<void> flush() async {
    // Intentionally empty — durability is enforced per-record in [_onRecord].
  }

  /// Lists all `*_logs.txt` files in the logs directory, sorted newest-first
  /// by filesystem modification time.
  ///
  /// Phase 01 relied on the yyyymmdd_hhmm.ss filename embedding + alphabetical
  /// sort to produce chronological order. That invariant is fragile: a future
  /// change to [_formatFilenameTimestamp] would silently break ordering
  /// without any compile-time signal. Use [FileStat.modified] directly so the
  /// sort stays correct regardless of the filename format.
  static Future<List<File>> listLogFiles() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final logsDir = Directory(p.join(docsDir.path, 'logs'));
    if (!await logsDir.exists()) return <File>[];
    final entries = <(File, DateTime)>[];
    await for (final entity in logsDir.list()) {
      if (entity is File && entity.path.endsWith('_logs.txt')) {
        final stat = await entity.stat();
        entries.add((entity, stat.modified));
      }
    }
    entries.sort((a, b) => b.$2.compareTo(a.$2)); // newest first
    return entries.map((e) => e.$1).toList();
  }

  /// Synchronous record handler — encodes [rec] as JSON and performs a
  /// blocking `writeStringSync` + `flushSync` on the active [RandomAccessFile].
  ///
  /// Synchronous on purpose: `Stream.listen` does NOT await `async`
  /// callbacks, so an `async` body races itself on back-to-back records.
  /// `flushSync` is documented as the real `fsync(2)` (durable to disk),
  /// not just a userspace drain.
  static void _onRecord(LogRecord rec) {
    final raf = _raf;
    if (raf == null) return;

    final entry = <String, Object?>{
      'ts': rec.time.toIso8601String(),
      'level': rec.level.name,
      'logger': rec.loggerName,
      'msg': rec.message,
      if (rec.error != null) 'error': rec.error.toString(),
      if (rec.stackTrace != null) 'stack': rec.stackTrace.toString(),
    };
    final line = '${jsonEncode(entry)}\n';

    // Catch only [FileSystemException] — the sync API does not raise
    // [StateError]. On an I/O failure we surface the message via
    // `dart:developer` `log()` (which on iOS reaches the Xcode console)
    // and null the handle so subsequent records are silently dropped
    // instead of re-entering the zone error handler — which would itself
    // call Logger.shout → _onRecord → infinite loop.
    try {
      raf.writeStringSync(line);
      raf.flushSync();
    } on FileSystemException catch (e) {
      developer.log('FileLogger record write failed; nulling handle: $e', name: 'FileLogger');
      _raf = null;
    }
  }

  /// Closes [_raf] and clears the field, swallowing any [FileSystemException]
  /// (close errors are not actionable from caller code — best effort).
  static Future<void> _closeRafQuietly() async {
    final raf = _raf;
    _raf = null;
    if (raf == null) return;
    try {
      await raf.close();
    } on FileSystemException {
      // Best effort — file is being torn down regardless.
    }
  }

  /// Prunes oldest log files until the directory total stays under
  /// [kMaxLogsDirBytes].
  ///
  /// INVARIANT: assumes a single app instance is writing to the logs
  /// directory. Two concurrent bootstraps (e.g. two Flutter desktop windows
  /// open simultaneously) could mis-count bytes and over-delete. This is
  /// acceptable because the POC is a single-window mobile/desktop app by
  /// design — not a service.
  static Future<void> _pruneToSizeLimit(Directory logsDir) async {
    final files = <File>[];
    await for (final entity in logsDir.list()) {
      if (entity is File && entity.path.endsWith('_logs.txt')) {
        files.add(entity);
      }
    }
    // Sort oldest-first by mtime so we prune the right files regardless of the
    // filename format (symmetric with listLogFiles using FileStat.modified).
    final byMtime = <(File, int)>[];
    for (final f in files) {
      final s = await f.stat();
      byMtime.add((f, s.modified.millisecondsSinceEpoch));
    }
    byMtime.sort((a, b) => a.$2.compareTo(b.$2));

    int totalBytes = 0;
    final sizes = <int>[];
    for (final entry in byMtime) {
      final s = await entry.$1.length();
      sizes.add(s);
      totalBytes += s;
    }

    var i = 0;
    while (totalBytes > kMaxLogsDirBytes && i < byMtime.length) {
      try {
        await byMtime[i].$1.delete();
        totalBytes -= sizes[i];
      } on FileSystemException {
        // Skip unlinkable file, keep going. Rare edge case (Windows lock).
      }
      i++;
    }
  }

  // ISO-8601 calendar-component widths used by the yyyymmddTHHMMSSZ filename
  // format. The numbers 4 and 2 are universally understood for year vs
  // month/day/hour/minute/second widths — extracted here anyway so every
  // caller references a named constant per CLAUDE.md §Magic numbers.
  static const int _yearWidth = 4;
  static const int _calendarComponentWidth = 2;

  /// POC adaptation #1 — UTC ISO-8601 basic format. Parent's local-time
  /// `yyyymmdd_hhmm.ss` is replaced by `yyyymmddTHHMMSSZ` so the iOS sideload
  /// device's wall-clock filename is unambiguous regardless of the user's
  /// timezone (Phase 1 is iOS-primary; the device may be travelling).
  static String _formatFilenameTimestamp(DateTime dt) {
    final u = dt.toUtc();
    String pad(int n, int w) => n.toString().padLeft(w, '0');
    return '${pad(u.year, _yearWidth)}${pad(u.month, _calendarComponentWidth)}${pad(u.day, _calendarComponentWidth)}'
        'T${pad(u.hour, _calendarComponentWidth)}${pad(u.minute, _calendarComponentWidth)}${pad(u.second, _calendarComponentWidth)}Z';
  }

  /// Test-only accessor for [_formatFilenameTimestamp]. Exists so the
  /// filename-format unit test can pin the UTC ISO-8601 basic shape
  /// without re-implementing the format function or coupling the
  /// production code to test internals.
  @visibleForTesting
  static String formatFilenameTimestampForTest(DateTime dt) => _formatFilenameTimestamp(dt);
}
