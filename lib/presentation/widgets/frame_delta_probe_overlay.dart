// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';

/// Top-right HUD overlay (FOG-08 user-facing) — three lines (median /
/// p95 / max) with green/yellow/red colour coding against the
/// Criterion A thresholds. Refresh cadence: 1 Hz, driven by probe
/// rollup emission. No internal timer.
///
/// Sits at top:[kPocFrameDeltaProbeOverlayTopPx], right:
/// [kPocFrameDeltaProbeOverlayRightPx] when stacked by MapScreen
/// (Plan 03-07) — directly below FpsCounterOverlay (top:8) and
/// MapCompass (top:56).
///
/// The walker glances at this overlay during the walk to see
/// Criterion A pass/fail in real time. The same numbers are also
/// persisted to the session log
/// (`Logger('infrastructure.mirk.frame_delta')`) for post-walk
/// analysis (Plan 03-08).
class FrameDeltaProbeOverlay extends StatefulWidget {
  const FrameDeltaProbeOverlay({super.key, required this.probe});

  /// Probe whose [FrameDeltaProbe.rollups] stream this overlay subscribes to.
  final FrameDeltaProbe probe;

  @override
  State<FrameDeltaProbeOverlay> createState() => _FrameDeltaProbeOverlayState();
}

class _FrameDeltaProbeOverlayState extends State<FrameDeltaProbeOverlay> {
  /// Placeholder shown for each metric before the first rollup arrives. A
  /// non-digit dash deliberately differs from "0.0" so the user can tell
  /// "no samples yet" from "samples are zero".
  static const String _placeholderValue = '–';

  StreamSubscription<FrameDeltaRollup>? _subscription;
  FrameDeltaRollup? _latestRollup;

  @override
  void initState() {
    super.initState();
    _subscription = widget.probe.rollups.listen((rollup) {
      if (!mounted) return;
      setState(() => _latestRollup = rollup);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Maps a microsecond value to its colour band against the green/yellow
  /// thresholds. `> yellowMaxMicros` falls through to red.
  Color _colorFor(int micros, int greenMaxMicros, int yellowMaxMicros) {
    if (micros <= greenMaxMicros) return Colors.greenAccent;
    if (micros <= yellowMaxMicros) return Colors.amberAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rollup = _latestRollup;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          _line(
            label: l10n.frameDeltaProbeMedianLabel,
            valueMicros: rollup?.medianMicros,
            greenMaxMicros: kPocFrameDeltaMedianGreenMicros,
            yellowMaxMicros: kPocFrameDeltaMedianYellowMicros,
          ),
          _line(
            label: l10n.frameDeltaProbeP95Label,
            valueMicros: rollup?.p95Micros,
            greenMaxMicros: kPocFrameDeltaP95GreenMicros,
            yellowMaxMicros: kPocFrameDeltaP95YellowMicros,
          ),
          _line(
            label: l10n.frameDeltaProbeMaxLabel,
            valueMicros: rollup?.maxMicros,
            greenMaxMicros: kPocFrameDeltaMaxGreenMicros,
            yellowMaxMicros: kPocFrameDeltaMaxYellowMicros,
          ),
        ],
      ),
    );
  }

  /// One row: `<label> <Nms> ms`. `valueMicros == null` renders the
  /// placeholder dash with neutral white; otherwise the value drives the
  /// colour via [_colorFor]. Tabular figures keep digit width stable so
  /// the column doesn't shift when values cross digit boundaries.
  Widget _line({required String label, required int? valueMicros, required int greenMaxMicros, required int yellowMaxMicros}) {
    final color = valueMicros == null ? Colors.white70 : _colorFor(valueMicros, greenMaxMicros, yellowMaxMicros);
    final ms = valueMicros == null ? _placeholderValue : (valueMicros / 1000.0).toStringAsFixed(1);
    return Text(
      '$label $ms ms',
      style: TextStyle(color: color, fontSize: 12, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
    );
  }
}
