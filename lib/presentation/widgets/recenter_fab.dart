// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';

/// Recenter FAB — animates the camera to `lastFix` at zoom 15 over 500 ms
/// (LOC-04). Disabled when `lastFix == null` (LOC-05).
///
/// Real implementation lands in Plan 02-04. This Wave 0 stub renders a
/// permanently-disabled `FloatingActionButton` so `map_screen_test.dart` can
/// include it in the widget tree; the LOC-04/LOC-05 behavioural tests fail
/// (RED) against the stub until Plan 02-04 lands.
class RecenterFab extends StatefulWidget {
  const RecenterFab({super.key, required this.mapController, required this.lastFix});

  /// MapController whose camera will be animated to [lastFix] on tap.
  final MapController mapController;

  /// Latest GPS fix, or null when no fix is available yet (FAB disabled).
  final Position? lastFix;

  @override
  State<RecenterFab> createState() => _RecenterFabState();
}

class _RecenterFabState extends State<RecenterFab> {
  @override
  Widget build(BuildContext context) {
    // Stub: always disabled (`onPressed: null`). Real state machine handles
    // animation lifecycle + repeat-tap cancellation in Plan 02-04.
    return const FloatingActionButton(onPressed: null, child: Icon(Icons.my_location));
  }
}
