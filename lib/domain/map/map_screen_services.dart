// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';

/// Constructor-injected services for the Phase 2 `MapScreen`.
///
/// Production wiring: built once in the router / `app.dart` after the PMTiles
/// copy completes (Plan 02-02). Test wiring: each widget test constructs fakes
/// (fake stream factory, on-disk synthetic file, captured logger).
///
/// DTO justification: this is a true value object — three fields with distinct
/// origins (filesystem path produced by the copier, factory closure produced by
/// the geolocator service, optional logger override produced by tests). Lets
/// `MapScreen` accept ONE positional `services` arg instead of three positional
/// args, and lets tests pump `MapScreen.fromServices(fakeServices)` cleanly
/// without hidden globals.
@immutable
class MapScreenServices {
  const MapScreenServices({required this.pmtilesPath, required this.positionStreamFactory, this.logger});

  /// Absolute filesystem path to the PMTiles archive — guaranteed to exist by
  /// the time `MapScreen` is built (the PermissionGateScreen copy hook landed
  /// in Plan 02-02 awaits `PmtilesAssetCopier.ensureCopied()` before
  /// navigating to `/map`).
  final String pmtilesPath;

  /// Factory closure returning a fresh `Stream<Position>` per subscription.
  /// Tests substitute a `StreamController.stream` so they can emit synthetic
  /// fixes; production binds to `GeolocatorService.stream`.
  final Stream<Position> Function() positionStreamFactory;

  /// Optional logger override. Defaults to `Logger('presentation.map')` in
  /// the screen when null. Tests can capture log output by injecting a
  /// custom logger (e.g. for asserting that the GPS lifecycle logs at the
  /// expected verbosity).
  final Logger? logger;
}
