// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Always-on FPS counter overlay (PERF-01).
///
/// Renders `<fps> fps / <refreshRate> Hz` so ProMotion devices distinguish
/// "30 fps on a 120 Hz target" from "30 fps on a 60 Hz target" — Pitfall E
/// mandate (RESEARCH.md): NEVER hardcode 60 or 120 refresh rate. The widget
/// reads the current display refresh rate ONCE in [State.initState] from
/// [WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate].
///
/// Frame timing is captured via [SchedulerBinding.addPersistentFrameCallback]
/// which records the timestamp of every produced frame. A 250 ms periodic
/// timer recomputes the rolling 1-second average and triggers [setState].
/// The widget is const-constructible and self-managing — parent screens
/// just stack it on top of their body.
class FpsCounterOverlay extends StatefulWidget {
  const FpsCounterOverlay({super.key});

  @override
  State<FpsCounterOverlay> createState() => _FpsCounterOverlayState();
}

class _FpsCounterOverlayState extends State<FpsCounterOverlay> {
  static const Duration _windowDuration = Duration(seconds: 1);
  static const Duration _recomputeInterval = Duration(milliseconds: 250);
  static const double _defaultRefreshRateHz = 60.0;
  static const int _bufferWindowSeconds = 2;
  static const double _microsPerSecond = 1e6;

  final List<Duration> _frameDeltas = <Duration>[];
  Duration? _lastFrameTimestamp;
  Timer? _recomputeTimer;
  double _displayedFps = 0;
  double _refreshRate = _defaultRefreshRateHz;

  @override
  void initState() {
    super.initState();
    _refreshRate = WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate;
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
    _recomputeTimer = Timer.periodic(_recomputeInterval, (_) => _recompute());
  }

  /// Accumulates frame deltas. Called by Flutter's scheduler on every produced
  /// frame — including frames after this widget is disposed (Flutter SDK
  /// does NOT expose `removePersistentFrameCallback`). The growing list is
  /// bounded to ~2 s of frames so memory stays flat.
  void _onFrame(Duration timestamp) {
    final last = _lastFrameTimestamp;
    _lastFrameTimestamp = timestamp;
    if (last == null) return;
    _frameDeltas.add(timestamp - last);
    final maxKept = (_refreshRate * _bufferWindowSeconds).ceil();
    while (_frameDeltas.length > maxKept) {
      _frameDeltas.removeAt(0);
    }
  }

  /// Recomputes the rolling 1-second FPS average from the most recent frames.
  /// Skips when widget is disposed (`!mounted`) or when no frames have been
  /// produced yet (cold start).
  void _recompute() {
    if (!mounted) return;
    if (_frameDeltas.isEmpty) return;
    final windowMicros = _windowDuration.inMicroseconds;
    int totalMicros = 0;
    int frameCount = 0;
    for (var i = _frameDeltas.length - 1; i >= 0; i--) {
      final d = _frameDeltas[i];
      if (totalMicros + d.inMicroseconds > windowMicros) break;
      totalMicros += d.inMicroseconds;
      frameCount++;
    }
    if (totalMicros == 0 || frameCount == 0) return;
    setState(() {
      _displayedFps = frameCount * _microsPerSecond / totalMicros;
    });
  }

  @override
  void dispose() {
    _recomputeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
      child: Text(
        '${_displayedFps.toStringAsFixed(0)} fps / ${_refreshRate.toStringAsFixed(0)} Hz',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontFeatures: <FontFeature>[FontFeature.tabularFigures()]),
      ),
    );
  }
}
