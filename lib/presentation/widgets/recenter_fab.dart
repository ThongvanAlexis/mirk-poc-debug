// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../config/constants.dart';
import '../../l10n/app_localizations.dart';

/// Recenter FAB (LOC-04 + LOC-05). Tap → 500 ms easeInOut tween from current
/// camera to `(lastFix.latLng, kPocInitialZoom)` via per-frame
/// `mapController.move`. Disabled when `lastFix == null`.
///
/// Repeat-tap mid-animation disposes the in-flight controller, captures the
/// just-interpolated camera state, and starts a fresh tween — no flicker.
///
/// Hand-rolled (~25 LOC core) per RESEARCH §LOC-04 — under CONTEXT 30-LOC
/// threshold; no `flutter_map_animations` dependency.
class RecenterFab extends StatefulWidget {
  const RecenterFab({super.key, required this.mapController, required this.lastFix});

  /// MapController whose camera will be animated to [lastFix] on tap.
  final MapController mapController;

  /// Latest GPS fix, or null when no fix is available yet (FAB disabled).
  final Position? lastFix;

  @override
  State<RecenterFab> createState() => _RecenterFabState();
}

class _RecenterFabState extends State<RecenterFab> with TickerProviderStateMixin {
  AnimationController? _controller;

  void _onPressed() {
    final fix = widget.lastFix;
    // Belt-and-braces: build() also disables the button when fix is null.
    if (fix == null) return;
    // Repeat-tap: kill the in-flight tween BEFORE snapshotting, so the snapshot
    // captures the just-interpolated state instead of being overwritten by the
    // last frame of the prior tween.
    _controller?.dispose();
    final cam = widget.mapController.camera;
    final fromLat = cam.center.latitude;
    final fromLon = cam.center.longitude;
    final fromZoom = cam.zoom;
    final toLat = fix.latitude;
    final toLon = fix.longitude;
    const toZoom = kPocInitialZoom;
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kPocRecenterAnimationMs),
    );
    final t = CurvedAnimation(parent: c, curve: Curves.easeInOut);
    t.addListener(() {
      final v = t.value;
      widget.mapController.move(LatLng(fromLat + (toLat - fromLat) * v, fromLon + (toLon - fromLon) * v), fromZoom + (toZoom - fromZoom) * v);
    });
    _controller = c;
    c.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FloatingActionButton(
      tooltip: l10n.recenterTooltip,
      // LOC-05: null-onPressed greys the FAB automatically (Material default).
      onPressed: widget.lastFix == null ? null : _onPressed,
      child: const Icon(Icons.my_location),
    );
  }
}
