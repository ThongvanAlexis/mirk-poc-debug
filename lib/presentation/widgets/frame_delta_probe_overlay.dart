// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/widgets.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';

/// Top-right HUD overlay — three lines (med / p95 / max) with green/yellow/red
/// colour coding against Criterion A thresholds. Refreshes at 1 Hz from the
/// [FrameDeltaProbe.rollups] stream.
///
/// Sits at top:104, right:8 (kPocFrameDeltaProbeOverlayTopPx /
/// kPocFrameDeltaProbeOverlayRightPx) — directly below the FpsCounterOverlay
/// (top:8) and MapCompass (top:56).
///
/// Wave 0 stub — Plan 03-06 ships the implementation. The current build
/// returns `SizedBox.shrink()` so the overlay can be mounted in a `Stack`
/// without affecting layout.
class FrameDeltaProbeOverlay extends StatefulWidget {
  const FrameDeltaProbeOverlay({super.key, required this.probe});

  /// Probe whose [FrameDeltaProbe.rollups] stream this overlay subscribes to.
  final FrameDeltaProbe probe;

  @override
  State<FrameDeltaProbeOverlay> createState() => _FrameDeltaProbeOverlayState();
}

class _FrameDeltaProbeOverlayState extends State<FrameDeltaProbeOverlay> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
