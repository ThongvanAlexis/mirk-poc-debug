// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Always-visible compass icon (top-right, under FpsCounterOverlay).
///
/// Tap → snap-to-north tween (250 ms easeInOut). Subscribes to
/// `mapController.mapEventStream` to track rotation events so its visual
/// orientation tracks the camera bearing in real time.
///
/// Real implementation lands in Plan 02-04. Wave 0 stub renders
/// `SizedBox.shrink()` so its absence doesn't break widget trees that include
/// it as a child of a `Positioned`.
class MapCompass extends StatefulWidget {
  const MapCompass({super.key, required this.mapController});

  /// MapController whose `mapEventStream` is subscribed to for bearing sync,
  /// and whose `rotate(0)` is invoked on tap.
  final MapController mapController;

  @override
  State<MapCompass> createState() => _MapCompassState();
}

class _MapCompassState extends State<MapCompass> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
