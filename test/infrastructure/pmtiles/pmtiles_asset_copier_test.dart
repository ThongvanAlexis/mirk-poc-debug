// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// path_provider_platform_interface is a transitive dep of path_provider 2.1.5
// (declared in pubspec.lock but not pubspec.yaml). The platform-instance
// override is the documented test seam (mirrors Plan 01-04's FileLogger test
// pattern).
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/infrastructure/pmtiles/pmtiles_asset_copier.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// In-test [PathProviderPlatform] override pointing every directory accessor
/// at a per-test temp directory. Mirrors Plan 01-04's FileLogger test seam.
class _MockPathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _MockPathProviderPlatform(this._supportPath);

  final String _supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => _supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _supportPath;

  @override
  Future<String?> getTemporaryPath() async => _supportPath;
}

/// Synthetic 4-byte fake asset payload — actual PMTiles archives are MBs, but
/// the copier contract only cares about byte-equality between source and
/// destination so a 4-byte fixture exercises every code path.
final Uint8List _fakeAssetBytes = Uint8List.fromList(<int>[0x50, 0x4D, 0x54, 0x49]);

/// Installs a mock binary messenger handler on the `flutter/assets` channel so
/// `rootBundle.load(kPmtilesAssetPath)` returns [_fakeAssetBytes] without
/// requiring a real bundled asset.
void _installFakeAssetHandler(WidgetTester? tester) {
  final binding = TestDefaultBinaryMessengerBinding.instance;
  binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final key = utf8.decoder.convert(message!.buffer.asUint8List());
    if (key == kPmtilesAssetPath) {
      return ByteData.view(_fakeAssetBytes.buffer);
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<LogRecord> logRecords;
  late StreamSubscription<LogRecord> logSub;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pmtiles_copier_test_');
    PathProviderPlatform.instance = _MockPathProviderPlatform(tempDir.path);
    _installFakeAssetHandler(null);

    logRecords = <LogRecord>[];
    Logger.root.level = Level.ALL;
    logSub = Logger.root.onRecord.listen(logRecords.add);
  });

  tearDown(() async {
    await logSub.cancel();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Test cleanup — periphery error per CLAUDE.md §Error handling.
    }
  });

  group('PmtilesAssetCopier.ensureCopied', () {
    test('first launch copies asset bytes to <support>/maps/Fra_Melun.pmtile and returns absolute path', () async {
      final copiedPath = await PmtilesAssetCopier.ensureCopied();

      expect(p.isAbsolute(copiedPath), isTrue, reason: 'Returned path MUST be absolute.');
      expect(p.basename(copiedPath), equals(kPmtilesBasename));
      expect(p.dirname(copiedPath), equals(p.join(tempDir.path, kPmtilesMapsSubdir)));

      final copied = File(copiedPath);
      expect(copied.existsSync(), isTrue, reason: 'Copied file MUST exist on disk.');
      expect(copied.readAsBytesSync(), equals(_fakeAssetBytes), reason: 'Copied bytes MUST equal source asset bytes.');

      final infoLines = logRecords.where((r) => r.level == Level.INFO && r.loggerName == 'infrastructure.pmtiles');
      expect(
        infoLines.any((r) => r.message.contains('Copied') && r.message.contains(kPmtilesBasename)),
        isTrue,
        reason: 'First-launch copy MUST emit an INFO log line including "Copied" and the archive basename.',
      );
    });

    test('second launch with size-match returns same path WITHOUT writing or logging', () async {
      // First run primes the on-disk copy.
      final firstPath = await PmtilesAssetCopier.ensureCopied();
      logRecords.clear();

      // Capture mtime so we can prove the file was not rewritten.
      final mtimeBefore = File(firstPath).statSync().modified;
      // Force a 10ms delay so any rewrite would visibly bump mtime.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final secondPath = await PmtilesAssetCopier.ensureCopied();
      expect(secondPath, equals(firstPath), reason: 'Idempotent return contract: same path on both calls.');

      final mtimeAfter = File(secondPath).statSync().modified;
      expect(mtimeAfter, equals(mtimeBefore), reason: 'Size-match short-circuit MUST NOT rewrite the file.');

      expect(
        logRecords.any((r) => r.level == Level.INFO && r.loggerName == 'infrastructure.pmtiles'),
        isFalse,
        reason: 'Second-launch silence is the contract (CONTEXT specifics §3 / success criterion 1).',
      );
    });

    test('size-mismatch (truncated previous copy) re-copies and logs', () async {
      // First run primes the on-disk copy.
      final firstPath = await PmtilesAssetCopier.ensureCopied();

      // Truncate the file to simulate an interrupted prior copy.
      File(firstPath).writeAsBytesSync(<int>[0x00]);
      logRecords.clear();

      final secondPath = await PmtilesAssetCopier.ensureCopied();
      expect(secondPath, equals(firstPath));
      expect(File(secondPath).readAsBytesSync(), equals(_fakeAssetBytes), reason: 'Size-mismatch path MUST re-copy the full asset bytes.');

      final infoLines = logRecords.where((r) => r.level == Level.INFO && r.loggerName == 'infrastructure.pmtiles');
      expect(infoLines.any((r) => r.message.contains('Copied')), isTrue, reason: 'Re-copy MUST emit the same "Copied ..." log line as first launch.');
    });

    test('FileSystemException path: catches at SEVERE, rethrows', () async {
      // Pre-create the destination directory's parent as a FILE, so creating
      // the maps/ subdirectory raises FileSystemException on every platform.
      final blockedSupport = p.join(tempDir.path, 'blocked_support');
      File(blockedSupport).writeAsStringSync('not a directory');
      PathProviderPlatform.instance = _MockPathProviderPlatform(blockedSupport);

      await expectLater(
        PmtilesAssetCopier.ensureCopied(),
        throwsA(isA<FileSystemException>()),
        reason: 'On copy failure, the FileSystemException MUST propagate to the caller (PermissionGate handles it).',
      );

      final severeLines = logRecords.where((r) => r.level >= Level.SEVERE && r.loggerName == 'infrastructure.pmtiles');
      expect(severeLines, isNotEmpty, reason: 'FileSystemException path MUST log at SEVERE before rethrowing.');
    });
  });
}
