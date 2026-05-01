// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/map/map_screen_services.dart';
import 'package:mirk_poc_debug/infrastructure/location/geolocator_service.dart';

import 'screens/error_screen.dart';
import 'screens/map_screen.dart';
import 'screens/permission_denied_screen.dart';
import 'screens/permission_gate_screen.dart';

/// Phase 1+2 GoRouter — four routes, every transition uses `context.go(...)`
/// (full pile reset, no back navigation per CONTEXT.md decision).
///
/// Routes:
///   - `/`       → [PermissionGateScreen] (rationale + request CTA + lifecycle re-check)
///   - `/map`    → [MapScreen.fromServices] with production wiring (PMTiles
///                 path resolved via `getApplicationSupportDirectory()` +
///                 `GeolocatorService.stream` factory)
///   - `/denied` → [PermissionDeniedScreen] (Open Settings; gate screen handles auto-resume)
///   - `/error`  → [ErrorScreen] (Phase 2; reached via `context.go('/error', extra: <String detail>)`)
///
/// `initialLocation` is `/` so cold-launch always lands on the gate screen,
/// which then short-circuits to `/map` via `context.go` if the permission was
/// granted in a prior session (handled inside the gate screen's `initState`).
///
/// Route order tracks the logical user flow (gate → map / denied / error).
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <GoRoute>[
    GoRoute(path: '/', name: 'permission-gate', builder: (BuildContext context, GoRouterState state) => const PermissionGateScreen()),
    GoRoute(path: '/map', name: 'map', builder: _buildMapRoute),
    GoRoute(path: '/denied', name: 'denied', builder: (BuildContext context, GoRouterState state) => const PermissionDeniedScreen()),
    GoRoute(
      path: '/error',
      name: 'error',
      builder: (BuildContext context, GoRouterState state) {
        // GoRouter's `extra` is `Object?` — narrow to String, fall back to a
        // visible sentinel rather than crashing if a caller forgets to pass it.
        final extra = state.extra;
        final detail = extra is String ? extra : '<no detail>';
        return ErrorScreen(detail: detail);
      },
    ),
  ],
);

/// `/map` route builder. Wraps the MapScreen in a FutureBuilder that resolves
/// the absolute PMTiles path via `getApplicationSupportDirectory()`. The
/// PMTiles file ITSELF is already on disk (the gate screen's
/// `_ensureMapDataAndNavigate` from Plan 02-02 awaited the copy before
/// navigating here) — this FutureBuilder only resolves the absolute path,
/// which lands in <1 ms in practice. The user perceives no flash.
Widget _buildMapRoute(BuildContext context, GoRouterState state) {
  return FutureBuilder<String>(
    future: _resolvePmtilesPath(),
    builder: (BuildContext context, AsyncSnapshot<String> snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final pathOrNull = snap.data;
      if (snap.hasError || pathOrNull == null) {
        return const Scaffold(body: Center(child: Text('Map data unavailable')));
      }
      return MapScreen.fromServices(MapScreenServices(pmtilesPath: pathOrNull, positionStreamFactory: GeolocatorService.stream));
    },
  );
}

/// Resolves the absolute PMTiles destination path. The file is already on
/// disk by the time this is invoked (gate screen guarantee — Plan 02-02);
/// we only need the absolute path so VectorTileLayer can open the archive.
Future<String> _resolvePmtilesPath() async {
  final supportDir = await getApplicationSupportDirectory();
  return p.join(supportDir.path, kPmtilesMapsSubdir, kPmtilesBasename);
}
