// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

/// Per-second probe rollup payload — emitted at 1 Hz on the
/// [FrameDeltaProbe.rollups] stream and persisted as one JSONL line via
/// `Logger('infrastructure.mirk.frame_delta')`.
class FrameDeltaRollup {
  const FrameDeltaRollup({required this.epochSecond, required this.sampleCount, required this.medianMicros, required this.p95Micros, required this.maxMicros});

  /// Wall-clock epoch second of this rollup window.
  final int epochSecond;

  /// Number of raw samples that fed into this rollup (≤
  /// `kPocFrameDeltaBufferMaxSamples`).
  final int sampleCount;

  /// Median camera-snapshot → fog-uniform-population delta in microseconds.
  final int medianMicros;

  /// p95 of the same delta in microseconds.
  final int p95Micros;

  /// Max of the same delta in microseconds.
  final int maxMicros;
}

/// Frame-delta self-debug probe (FOG-08).
///
/// Records the wall-clock delta between the moment FogLayer reads
/// `MapCamera.of(context)` (camera snapshot) and the moment the per-frame
/// FogShaderUniforms.setAll completes (uniform population). Emits per-second
/// rollups via [rollups] for the on-screen overlay (FrameDeltaProbeOverlay)
/// and via `Logger('infrastructure.mirk.frame_delta')` for post-walk
/// evidence in 03-FALSIFICATION.md.
///
/// Wave 0 stub — Plan 03-04 ships the implementation.
class FrameDeltaProbe {
  /// 1 Hz stream of [FrameDeltaRollup] objects. Stub returns an empty stream;
  /// the live stream is opened in Plan 03-04's [start].
  Stream<FrameDeltaRollup> get rollups => const Stream<FrameDeltaRollup>.empty();

  /// Records the moment FogLayer.build() reads `MapCamera.of(context)`.
  /// Returns the elapsed-microseconds reading for the caller to thread
  /// through to [recordFogUniformPopulation]. Stub throws.
  int recordCameraSnapshot() {
    throw UnimplementedError('FrameDeltaProbe.recordCameraSnapshot — Plan 03-04');
  }

  /// Records the moment FogShaderUniforms.setAll completes, computes the
  /// delta against [cameraSnapshotMicros], and pushes it into the ring
  /// buffer. Stub throws.
  void recordFogUniformPopulation(int cameraSnapshotMicros) {
    throw UnimplementedError('FrameDeltaProbe.recordFogUniformPopulation — Plan 03-04');
  }

  /// Starts the per-second rollup timer. Stub throws.
  void start() {
    throw UnimplementedError('FrameDeltaProbe.start — Plan 03-04');
  }

  /// Stops the rollup timer. Plan 03-04 will close the [rollups] stream.
  void stop() {}

  /// Disposes the probe. Plan 03-04 will tear down the rollup stream
  /// controller and any pending Timer.
  void dispose() {}
}
