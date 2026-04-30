// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'screens/map_screen.dart';
import 'screens/permission_denied_screen.dart';
import 'screens/permission_gate_screen.dart';

/// Phase 1 GoRouter — three routes, every transition uses `context.go(...)`
/// (full pile reset, no back navigation per CONTEXT.md decision).
///
/// Routes:
///   - `/`       → [PermissionGateScreen] (rationale + request CTA + lifecycle re-check)
///   - `/map`    → [MapScreen] (Phase 1 dark-grey placeholder; Phase 2 swaps body for FlutterMap)
///   - `/denied` → [PermissionDeniedScreen] (Open Settings; gate screen handles auto-resume)
///
/// `initialLocation` is `/` so cold-launch always lands on the gate screen,
/// which then short-circuits to `/map` via `context.go` if the permission was
/// granted in a prior session (handled inside the gate screen's `initState`).
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <GoRoute>[
    GoRoute(path: '/', name: 'permission-gate', builder: (BuildContext context, GoRouterState state) => const PermissionGateScreen()),
    GoRoute(path: '/map', name: 'map', builder: (BuildContext context, GoRouterState state) => const MapScreen()),
    GoRoute(path: '/denied', name: 'denied', builder: (BuildContext context, GoRouterState state) => const PermissionDeniedScreen()),
  ],
);
