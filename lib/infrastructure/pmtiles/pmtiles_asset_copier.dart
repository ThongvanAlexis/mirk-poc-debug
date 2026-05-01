// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

/// Copies the bundled PMTiles archive from `rootBundle` to
/// `<getApplicationSupportDirectory()>/maps/` exactly once per install.
///
/// Real implementation lands in Plan 02-02 (MAP-01). This Wave 0 stub exists
/// so `permission_gate_screen.dart` (Plan 02-02 edit) and the Wave 0 tests
/// can import the symbol without the analyzer blowing up at parse time.
class PmtilesAssetCopier {
  /// Idempotent. Returns the absolute filesystem path to the copied archive.
  ///
  /// Throws `FileSystemException` on copy failure. Stub always throws
  /// `UnimplementedError` so any code path reaching it during Wave 0 tests
  /// surfaces a clear runtime failure (not a silent fallback).
  static Future<String> ensureCopied() async {
    throw UnimplementedError('PmtilesAssetCopier.ensureCopied is implemented in Plan 02-02 (MAP-01)');
  }
}
