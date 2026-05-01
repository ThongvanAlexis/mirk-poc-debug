// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../config/constants.dart';
import '../../l10n/app_localizations.dart';

/// Shortest-path delta in degrees from [currentBearingDegrees] to north (0°).
///
/// Returns a value in `[-180, 180]`. Bearing 350° → +10° (forward through
/// 360°/0°); bearing 10° → -10° (backward through 0°). Top-level function
/// (rather than a private static) so unit tests can pin RESEARCH Open
/// Question #2 without depending on the widget's private API surface.
double mapCompassShortestPathToNorth(double currentBearingDegrees) {
  // (target - current + 540) % 360 - 180 wraps any signed delta into [-180, 180].
  // target = 0, so this collapses to (-current + 540) % 360 - 180.
  return ((-currentBearingDegrees + 540) % 360) - 180;
}

/// Always-visible compass icon (CONTEXT §Map camera bounds & gestures).
///
/// Subscribes to `mapController.mapEventStream` filtered to `MapEventRotate`,
/// reads the new bearing from `event.camera.rotation`, and `setState`s so the
/// glyph (Transform.rotate) stays pointing at world-north as the camera
/// rotates.
///
/// On tap: 250 ms `Curves.easeInOut` tween calls `mapController.rotate` per
/// frame ending at 0° (or 360° via shortest-path). RESEARCH Open Question #2
/// is pinned in [mapCompassShortestPathToNorth].
class MapCompass extends StatefulWidget {
  const MapCompass({super.key, required this.mapController});

  /// MapController whose `mapEventStream` is subscribed to for bearing sync,
  /// and whose `rotate(0)` is invoked on tap.
  final MapController mapController;

  @override
  State<MapCompass> createState() => _MapCompassState();
}

class _MapCompassState extends State<MapCompass> with TickerProviderStateMixin {
  StreamSubscription<MapEvent>? _eventSubscription;
  AnimationController? _controller;
  double _bearingDegrees = 0;

  @override
  void initState() {
    super.initState();
    // Seed bearing from the controller's current camera so a screen mounted
    // with a non-zero initial bearing renders correctly on the first frame.
    // The real flutter_map MapControllerImpl throws "FlutterMap widget
    // rendered at least once" when `.camera` is read before the FlutterMap
    // has produced its first frame, which can happen if the parent mounts
    // this widget on the same frame the FlutterMap enters the tree. Tolerate
    // that by falling back to bearing 0 — the very next MapEventRotate will
    // overwrite it via setState anyway.
    try {
      _bearingDegrees = widget.mapController.camera.rotation;
    } on Object {
      _bearingDegrees = 0;
    }
    _eventSubscription = widget.mapController.mapEventStream.listen((MapEvent event) {
      if (event is! MapEventRotate) return;
      if (!mounted) return;
      setState(() => _bearingDegrees = event.camera.rotation);
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _onPressed() {
    final from = _bearingDegrees;
    final delta = mapCompassShortestPathToNorth(from);
    if (delta == 0) return; // already at north — no-op (no tween)
    _controller?.dispose();
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kPocCompassAnimationMs),
    );
    final t = CurvedAnimation(parent: c, curve: Curves.easeInOut);
    t.addListener(() {
      final v = t.value;
      widget.mapController.rotate(from + delta * v);
    });
    _controller = c;
    c.forward();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final radians = _bearingDegrees * math.pi / 180.0;
    return IconButton(
      tooltip: l10n.compassTooltip,
      onPressed: _onPressed,
      // Glyph rotates opposite to camera so the needle keeps pointing at
      // world-north as the map rotates underneath.
      icon: Transform.rotate(angle: -radians, child: const Icon(Icons.explore)),
    );
  }
}
