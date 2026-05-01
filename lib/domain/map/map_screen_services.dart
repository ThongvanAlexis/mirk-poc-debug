// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';

/// Constructor-injected services for the Phase 2+3 `MapScreen`.
///
/// Production wiring: built once in the router / `app.dart` after the PMTiles
/// copy completes (Plan 02-02). Test wiring: each widget test constructs fakes
/// (fake stream factory, on-disk synthetic file, captured logger, in-memory
/// disc repository, no-op probe).
///
/// DTO justification: this is a true value object — five fields with distinct
/// origins (filesystem path produced by the copier, factory closure produced
/// by the geolocator service, optional logger override produced by tests,
/// reveal-disc repository owned by the screen lifetime, frame-delta probe
/// owned by the screen lifetime). Lets `MapScreen` accept ONE positional
/// `services` arg instead of five, and lets tests pump
/// `MapScreen.fromServices(fakeServices)` cleanly without hidden globals.
@immutable
class MapScreenServices {
  const MapScreenServices({
    required this.pmtilesPath,
    required this.positionStreamFactory,
    required this.discRepository,
    required this.frameDeltaProbe,
    this.logger,
  });

  /// Absolute filesystem path to the PMTiles archive — guaranteed to exist by
  /// the time `MapScreen` is built (the PermissionGateScreen copy hook landed
  /// in Plan 02-02 awaits `PmtilesAssetCopier.ensureCopied()` before
  /// navigating to `/map`).
  final String pmtilesPath;

  /// Factory closure returning a fresh `Stream<Position>` per subscription.
  /// Tests substitute a `StreamController.stream` so they can emit synthetic
  /// fixes; production binds to `GeolocatorService.stream`.
  final Stream<Position> Function() positionStreamFactory;

  /// In-memory reveal-disc repository (FOG-01). MapScreen appends a new
  /// 25 m disc on every GPS fix; FogLayer subscribes via `addListener` and
  /// rebuilds when new discs land. Tests pass a freshly-constructed
  /// repository to assert append behaviour.
  final RevealDiscRepository discRepository;

  /// Frame-delta self-debug probe (FOG-08). FogLayer + FrameDeltaProbeOverlay
  /// share this single instance — the layer pushes samples, the overlay
  /// reads rollups. Owned by the MapScreen lifetime (constructed in the
  /// router builder, disposed when the screen unmounts).
  final FrameDeltaProbe frameDeltaProbe;

  /// Optional logger override. Defaults to `Logger('presentation.map')` in
  /// the screen when null. Tests can capture log output by injecting a
  /// custom logger (e.g. for asserting that the GPS lifecycle logs at the
  /// expected verbosity).
  final Logger? logger;
}
