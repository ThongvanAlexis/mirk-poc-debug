// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/constants.dart';

/// Copies the bundled PMTiles archive from `rootBundle` to
/// `<getApplicationSupportDirectory()>/maps/Fra_Melun.pmtile` exactly once
/// per install (idempotent on subsequent launches via size-parity check).
///
/// Why Application Support and not Documents: iOS Documents is iCloud-backed
/// by default; a 4 MB binary blob there eats the user's iCloud budget on
/// every install (Pitfall 4 — verified against Apple's path_provider docs).
/// Application Support is also visible to the user via Settings → General →
/// iPhone Storage but is not iCloud-replicated.
///
/// Idempotency: existence + size-parity (NOT SHA256 — deferred per RESEARCH
/// §ROB-02). A truncated previous copy (battery died mid-write) triggers a
/// fresh copy because `lengthSync()` won't match the bundled byte count.
class PmtilesAssetCopier {
  static final Logger _log = Logger('infrastructure.pmtiles');

  /// Test seam — when non-null, [ensureCopied] returns this future instead of
  /// touching the real filesystem. Mirrors the Phase 1 PermissionHandlerPlatform
  /// test pattern so widget tests of the gate screen can simulate copy success
  /// or failure without a real `rootBundle.load` round-trip.
  @visibleForTesting
  static Future<String> Function()? testEnsureCopiedOverride;

  /// Idempotent copy of `kPmtilesAssetPath` to
  /// `<supportDir>/<kPmtilesMapsSubdir>/<kPmtilesBasename>`. Returns the
  /// absolute filesystem path of the destination.
  ///
  /// First launch: writes bytes, logs `Copied <basename> (~<N>.<N> MB) in <ms> ms`
  /// at INFO level. Second launch with matching size: returns silently (no log).
  /// Size-mismatch: re-copies and logs as if first launch.
  ///
  /// Throws [FileSystemException] on any I/O failure so callers (the gate
  /// screen) can route to `/error` with the underlying message. Non-I/O errors
  /// are wrapped into [FileSystemException] so the caller's catch pattern
  /// remains a single type.
  static Future<String> ensureCopied() async {
    final override = testEnsureCopiedOverride;
    if (override != null) return override();

    try {
      final supportDir = await getApplicationSupportDirectory();
      final mapsDir = Directory(p.join(supportDir.path, kPmtilesMapsSubdir));
      if (!await mapsDir.exists()) {
        await mapsDir.create(recursive: true);
      }
      final dstFilename = p.join(mapsDir.path, kPmtilesBasename);
      final dst = File(dstFilename);

      final bundled = await rootBundle.load(kPmtilesAssetPath);
      final bundledBytes = bundled.lengthInBytes;

      if (await dst.exists() && dst.lengthSync() == bundledBytes) {
        // Idempotent skip — silent per CONTEXT mandate (no log on subsequent launches).
        return dstFilename;
      }

      final stopwatch = Stopwatch()..start();
      await dst.writeAsBytes(bundled.buffer.asUint8List(), flush: true);
      stopwatch.stop();
      final megabytes = (bundledBytes / (1024 * 1024)).toStringAsFixed(1);
      _log.info('Copied $kPmtilesBasename (~$megabytes MB) in ${stopwatch.elapsedMilliseconds} ms');
      return dstFilename;
    } on FileSystemException catch (e, st) {
      _log.severe('PMTiles copy failed: ${e.message}', e, st);
      rethrow;
    } catch (e, st) {
      // Wrap any non-FileSystemException I/O-ish failure so the caller's
      // catch-on-FileSystemException pattern still fires (gate screen routes
      // /error on any copy failure, regardless of the underlying type).
      _log.severe('PMTiles copy failed (wrapped): $e', e, st);
      throw FileSystemException(e.toString());
    }
  }
}
