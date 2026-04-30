// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';

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
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

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
