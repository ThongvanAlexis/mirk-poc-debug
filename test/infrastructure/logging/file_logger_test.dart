// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// Transitive deps via path_provider — same suppression pattern as the
// permission_handler_platform_interface case in Plans 05/06. Production
// code carries no such suppression; only this test imports the platform
// interface to install a `PathProviderPlatform.instance` override.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mirk_poc_debug/infrastructure/logging/file_logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// In-test [PathProviderPlatform] override that points
/// `getApplicationDocumentsDirectory()` at a per-test temporary directory.
/// Avoids pulling in mocktail/mockito — flutter_test only, per RESEARCH.md
/// §Testing.
class _MockPathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _MockPathProviderPlatform(this._docsPath);

  final String _docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;

  @override
  Future<String?> getTemporaryPath() async => _docsPath;

  @override
  Future<String?> getApplicationSupportPath() async => _docsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_logger_test_');
    PathProviderPlatform.instance = _MockPathProviderPlatform(tempDir.path);
    await FileLogger.bootstrap();
  });

  tearDown(() async {
    await FileLogger.flush();
    // Best-effort cleanup — Windows may hold the file briefly.
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Test cleanup — periphery error per CLAUDE.md §Error handling.
    }
  });

  group('FileLogger', () {
    test('LOG-01: bootstrap creates a timestamped file under <docs>/logs/', () async {
      final activeFilename = FileLogger.activeFilename;
      expect(activeFilename, isNotNull);
      expect(File(activeFilename!).existsSync(), isTrue, reason: 'Active log file MUST exist on disk after bootstrap.');

      // Filename matches the UTC ISO-8601 basic format: yyyymmddTHHMMSSZ_logs.txt
      final basename = p.basename(activeFilename);
      expect(
        RegExp(r'^\d{8}T\d{6}Z_logs\.txt$').hasMatch(basename),
        isTrue,
        reason: 'Filename MUST match yyyymmddTHHMMSSZ_logs.txt (POC adaptation #1). Got: $basename',
      );

      // Path lives under <docs>/logs/.
      final expectedDir = p.join(tempDir.path, 'logs');
      expect(p.dirname(activeFilename), equals(expectedDir));
    });

    test('LOG-02: Logger.root.level == Level.ALL after bootstrap', () {
      expect(Logger.root.level, equals(Level.ALL), reason: 'POC adaptation #2 — always-verbose per LOG-02.');
    });

    test('LOG-02: emitted records have ms-precision ts field', () async {
      // Emit several records to maximise the chance that at least one lands on a
      // non-zero millisecond — DateTime.now() resolution is OS-dependent and on
      // some platforms the millisecond can read 0 if the call lands exactly on
      // the second boundary.
      for (var i = 0; i < 20; i++) {
        Logger('test').info('record $i');
        // Tiny delay to spread timestamps across milliseconds.
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await FileLogger.flush();

      final lines = File(FileLogger.activeFilename!).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
      expect(lines, isNotEmpty);

      var sawNonZeroMs = false;
      for (final line in lines) {
        final entry = jsonDecode(line) as Map<String, Object?>;
        final tsRaw = entry['ts'];
        expect(tsRaw, isA<String>(), reason: 'Each record MUST carry a ts field.');
        final ts = DateTime.parse(tsRaw! as String);
        if (ts.millisecond > 0) {
          sawNonZeroMs = true;
          break;
        }
      }
      expect(
        sawNonZeroMs,
        isTrue,
        reason: 'At least one record across 20 emissions MUST land on a non-zero millisecond — proves ms precision is preserved end-to-end.',
      );
    });

    test('idempotent bootstrap reopens a fresh file and stops writing to the prior one', () async {
      // First bootstrap is in setUp; capture its filename.
      final firstFilename = FileLogger.activeFilename;
      expect(firstFilename, isNotNull);
      Logger('test').info('record-A');
      await FileLogger.flush();

      // Filename format has 1 s resolution; sleep so the next bootstrap stamps
      // a different name. Alternative would be a clock seam — out of scope for
      // the POC; sleep is acceptable in a test.
      await Future<void>.delayed(const Duration(seconds: 2));
      await FileLogger.bootstrap();
      final secondFilename = FileLogger.activeFilename;
      expect(secondFilename, isNotNull);
      expect(secondFilename, isNot(equals(firstFilename)), reason: 'Second bootstrap MUST open a fresh file (different timestamp).');

      Logger('test').info('record-B');
      await FileLogger.flush();

      // Cross-file content assertion: closure of the prior _raf is observed
      // indirectly via "writes after bootstrap #2 do NOT land in file #1".
      final firstContents = File(firstFilename!).readAsStringSync();
      final secondContents = File(secondFilename!).readAsStringSync();
      expect(firstContents, contains('record-A'));
      expect(firstContents, isNot(contains('record-B')), reason: 'Prior _raf MUST be closed — record-B written after bootstrap #2 must NOT appear in file #1.');
      expect(secondContents, contains('record-B'));
      expect(secondContents, isNot(contains('record-A')), reason: 'New _raf is fresh — record-A from before bootstrap #2 must NOT appear in file #2.');
    });

    test('10 MB prune cap evicts oldest files at bootstrap', () async {
      // Fresh setup: clear non-active files from the bootstrap-created logs
      // dir and repopulate with > 10 MB of synthetic files BEFORE re-bootstrapping.
      await FileLogger.flush();
      final logsDir = Directory(p.join(tempDir.path, 'logs'));
      // Workaround for Windows file-lock semantics: we cannot delete logsDir
      // recursively while the active log RAF (opened by setUp's bootstrap)
      // still holds a handle to a file inside it (errno 32 — sharing
      // violation). Plan 04 SUMMARY's macOS/Linux tests didn't hit this
      // because POSIX permits unlinking open files. Iterate-and-skip-active
      // is the platform-agnostic equivalent: the next bootstrap call below
      // will close the active RAF and the prune algorithm operates on every
      // file in the dir uniformly. CLAUDE.md §Workarounds — comment present
      // because the loop's semantics aren't obvious without context.
      if (logsDir.existsSync()) {
        final activeFilename = FileLogger.activeFilename;
        for (final FileSystemEntity entity in logsDir.listSync()) {
          if (entity is! File) continue;
          if (activeFilename != null && p.equals(entity.path, activeFilename)) continue;
          entity.deleteSync();
        }
      } else {
        await logsDir.create(recursive: true);
      }

      // Create 12 files of 1 MB each = 12 MB total. Spread mtimes 1 s apart
      // so the prune algorithm can sort them reliably.
      const oneMegabyte = 1024 * 1024;
      final payload = String.fromCharCodes(List<int>.filled(oneMegabyte, 0x61)); // 1 MB of 'a'
      final synthetic = <File>[];
      for (var i = 0; i < 12; i++) {
        final f = File(p.join(logsDir.path, '2026010${i.toString().padLeft(2, '0')}T000000Z_logs.txt'));
        f.writeAsStringSync(payload);
        // Backdate mtime so the prune sort distinguishes them — older index = older mtime.
        final mtime = DateTime(2026).add(Duration(days: i));
        f.setLastModifiedSync(mtime);
        synthetic.add(f);
      }

      // Sanity: pre-bootstrap size > 10 MB.
      var preTotal = 0;
      for (final f in synthetic) {
        preTotal += await f.length();
      }
      expect(preTotal, greaterThan(10 * 1024 * 1024), reason: 'Test setup MUST start above the 10 MB cap.');

      await FileLogger.bootstrap();

      // Post-bootstrap: count surviving synthetic files + any new logs.
      final survivors = logsDir.listSync().whereType<File>().toList();
      var postTotal = 0;
      for (final f in survivors) {
        postTotal += await f.length();
      }
      expect(postTotal, lessThan(10 * 1024 * 1024), reason: 'Post-prune dir size MUST be under kMaxLogsDirBytes (10 MB).');

      // Oldest files are gone first — index 0 (oldest mtime) MUST be deleted.
      expect(synthetic[0].existsSync(), isFalse, reason: 'Oldest file MUST be pruned first.');
    });

    test('FileSystemException handling is structurally present in source (W-4 fix — static-source assertion)', () {
      // Static source assertion — a runtime FileSystemException-injection test
      // would require platform-fragile mechanisms (chmod / fill-disk /
      // unwritable mock path) that misbehave on Windows CI, and the parent
      // project lacks any DI seam on RandomAccessFile. The genuine
      // FileSystemException path is exercised manually during the LOG-05 iOS
      // sideload UAT walk where iOS jetsam-induced write errors actually
      // surface; this test guards against accidental regression.
      final sourcePath = p.join(Directory.current.path, 'lib', 'infrastructure', 'logging', 'file_logger.dart');
      final source = File(sourcePath).readAsStringSync();
      expect(
        source,
        contains('on FileSystemException catch'),
        reason: 'Catch clause MUST be scoped to FileSystemException — bare catch would swallow programming errors per CLAUDE.md.',
      );
      expect(
        source,
        contains('_raf = null'),
        reason: 'Post-exception null-out is the documented infinite-loop defense; removing it re-introduces the zone-error-handler loop.',
      );
      expect(source, contains('developer.log'), reason: 'Failure-fallback surfacing path — without it, FileSystemException is silently swallowed.');
    });
  });
}
