// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

/// 1-second JSONL rollup of SDF rebuild stats (FOG-03).
///
/// Buffers per-rebuild samples (elapsed time, disc count, intersecting disc
/// count) and flushes one JSONL line per active second to
/// `Logger('infrastructure.mirk.sdf')`. Idle seconds emit nothing.
///
/// Wave 0 stub — Plan 03-03 ships the implementation.
class SdfRebuildLogger {
  /// Records a rebuild sample. Stub throws.
  void recordRebuild({required double elapsedMs, required int discCount, required int intersectingDiscCount}) {
    throw UnimplementedError('SdfRebuildLogger.recordRebuild — Plan 03-03');
  }

  /// Starts the per-second rollup timer. Plan 03-03 makes this idempotent.
  void start() {}

  /// Stops the per-second rollup timer and flushes any pending samples.
  void stop() {}
}
