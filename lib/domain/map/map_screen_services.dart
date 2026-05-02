// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';

/// Constructor-injected services for the Phase 2+3 `MapScreen`.
///
/// Production wiring: built once in the router / `app.dart` after the PMTiles
/// copy completes (Plan 02-02). Test wiring: each widget test constructs fakes
/// (fake stream factory, on-disk synthetic file, captured logger, in-memory
/// disc repository, no-op probe, Completer-backed program loader).
///
/// DTO justification: this is a true value object — seven fields with distinct
/// origins (filesystem path produced by the copier, factory closure produced
/// by the geolocator service, optional logger override produced by tests,
/// reveal-disc repository owned by the screen lifetime, frame-delta probe
/// owned by the screen lifetime, fog-transform diagnostic logger owned by the
/// screen lifetime, optional fog-program loader override for tests). Lets
/// `MapScreen` accept ONE positional `services` arg instead of seven, and lets
/// tests pump `MapScreen.fromServices(fakeServices)` cleanly without hidden
/// globals.
@immutable
class MapScreenServices {
  const MapScreenServices({
    required this.pmtilesPath,
    required this.positionStreamFactory,
    required this.discRepository,
    required this.frameDeltaProbe,
    required this.fogTransformLogger,
    this.logger,
    this.fogProgramLoaderOverride,
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

  /// Fog-transform diagnostic logger (FOG-10, Phase 3.1 sibling to
  /// `frameDeltaProbe` + `sdfRebuildLogger`). `_FogPainter.paint()` calls
  /// `recordPaint(...)` once per paint with the per-frame Canvas-transform +
  /// camera-pixelOrigin + camera-center + applied-uOffset diagnostic tuple
  /// (see `lib/infrastructure/mirk/fog_transform_logger.dart`). Owned by the
  /// MapScreen lifetime — `start()` in initState, `stop()` in dispose, same
  /// shape as `frameDeltaProbe` and `sdfRebuildLogger`.
  final FogTransformLogger fogTransformLogger;

  /// Optional logger override. Defaults to `Logger('presentation.map')` in
  /// the screen when null. Tests can capture log output by injecting a
  /// custom logger (e.g. for asserting that the GPS lifecycle logs at the
  /// expected verbosity).
  final Logger? logger;

  /// Optional fog `FragmentProgram` loader override (FOG-04 test seam).
  ///
  /// Production wiring leaves this null and `MapScreen` falls back to
  /// `ui.FragmentProgram.fromAsset(kPocFogShaderAssetPath)`. Widget tests
  /// inject a `Completer<ui.FragmentProgram>().future` so the load future
  /// stays pending under test control (the real platform loader hangs
  /// indefinitely in headless `flutter test` — same constraint pinned by
  /// `ShaderSanityScreen.programLoaderOverride` in Plan 03-06).
  ///
  /// The widget tests' Completer is left unresolved on purpose: the
  /// production path tests assert the `_fogShader == null` state (FogLayer
  /// does not mount). Resolving the Completer would require a real
  /// `ui.FragmentProgram`, which `dart:ui 3.41` does not let us subclass.
  final Future<ui.FragmentProgram> Function()? fogProgramLoaderOverride;
}
