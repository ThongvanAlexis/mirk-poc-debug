// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';

import '../../domain/map/map_screen_services.dart';
import '../widgets/fps_counter_overlay.dart';
import '../widgets/poc_app_bar.dart';

/// Phase 1 placeholder for the map screen (route '/map').
///
/// Body is a dark-grey [ColoredBox] by design — Phase 2 swaps the body's
/// first Stack child for `FlutterMap(...)` while keeping the AppBar +
/// [FpsCounterOverlay] untouched. Per CONTEXT.md `Placeholder /map screen`
/// decision: this minimises Phase 2's diff (one widget swap, zero structural
/// rewiring) and lets the LOG-04 + PERF-01 contracts already land in Phase 1
/// (share-logs reachable from /map; FPS counter visible top-right).
///
/// Two constructors:
///   - default `MapScreen()` — used by the router, no injected services.
///   - `MapScreen.fromServices(services)` — used by Phase 2 widget tests so
///     they can inject a fake [MapScreenServices] (fake pmtilesPath, fake
///     position stream factory). Wave 0 stub — the body still renders the
///     dark-grey placeholder; Plan 02-05 will swap in `FlutterMap(...)` and
///     start consuming `services` at that point.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key}) : services = null;

  /// Wave 0 test entry point. Plan 02-05 will start consuming `services`
  /// (`pmtilesPath` for the VectorTileLayer, `positionStreamFactory` for the
  /// GPS subscription, optional `logger` for diagnostic output).
  const MapScreen.fromServices(this.services, {super.key});

  /// Constructor-injected services. Null when the screen is built from the
  /// default route; non-null only in tests / future Plan 02-05 wiring.
  final MapScreenServices? services;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildPocAppBar(context),
      body: Stack(
        children: <Widget>[
          // Phase 2 replaces this ColoredBox with FlutterMap(...) — the
          // surrounding Scaffold + AppBar + Stack + FpsCounterOverlay stay.
          ColoredBox(color: Colors.grey[850]!, child: const SizedBox.expand()),
          const Positioned(top: 8, right: 8, child: FpsCounterOverlay()),
        ],
      ),
    );
  }
}
