// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:mirk_poc_debug/domain/map/map_screen_services.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_transform_logger.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/map_screen.dart';

import '../_helpers/swallow_vector_map_tiles_cancellation.dart';

/// Success Criterion #2 — RED → GREEN test for WISP-03 warm-up gate +
/// no-synthetic-(0, 0) anti-pattern guard.
///
/// Two invariants:
///
///   1. No wisps appear during the first [kMirkPocWispWarmUpSeconds]
///      of MapScreen lifetime (warm-up). The "every previously-revealed
///      disc explodes on app open" failure mode is suppressed by the
///      `WispParticleSystem`'s wall-clock-since-construction gate.
///   2. No wisps appear at synthetic (0, 0) coordinates if a GPS fix
///      has not yet arrived. The Phase 2 GPS subsystem MUST NOT emit
///      a default-zero Position; the `WispParticleSystem` MUST NOT spawn
///      anything triggered by a (lat = 0, lon = 0) disc that materialised
///      from an uninitialised stream.
///
/// Plan 04-04 (Task 2) flips this from skip to active — `MapScreenServices`
/// now carries the `wispParticleSystem` field and `MapScreen.initState`
/// wires the spawn into `_subscribeToPositions`.

/// Pending fog-program loader so headless `flutter test` never hits the
/// real `ui.FragmentProgram.fromAsset` (no shader compiler in test).
Future<ui.FragmentProgram> _pendingFogProgram() => Completer<ui.FragmentProgram>().future;

/// Builds a Position with fixed values — only lat/lon vary in these tests.
Position _zeroPosition() => Position(
  latitude: 0,
  longitude: 0,
  timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Widget _wrap(MapScreenServices services) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: MapScreen.fromServices(services),
);

/// Path the PMTiles loader will try (and fail). The GPS-subscription +
/// frame-delta-probe wiring in `MapScreen.initState` runs BEFORE the
/// PMTiles future settles — these tests never need a real archive.
const String _nonExistentPmtilesPath = '/non/existent/test.pmtile';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wisp no-fix-warmup (Success Criterion #2)', () {
    testWidgets('No wisps appear during first 5 s of MapScreen lifetime (warm-up) — WISP-03 / SC #2', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      // Default Stopwatch — warm-up gate stays active throughout this
      // short test runtime (well under 5 s of real wall clock).
      final wispParticleSystem = WispParticleSystem();
      final wispTransformLogger = WispTransformLogger();
      final emitter = StreamController<Position>.broadcast();
      final probe = FrameDeltaProbe();

      final services = MapScreenServices(
        pmtilesPath: _nonExistentPmtilesPath,
        positionStreamFactory: () => emitter.stream,
        discRepository: RevealDiscRepository(),
        frameDeltaProbe: probe,
        fogTransformLogger: FogTransformLogger(),
        wispParticleSystem: wispParticleSystem,
        wispTransformLogger: wispTransformLogger,
        fogProgramLoaderOverride: _pendingFogProgram,
      );
      await tester.pumpWidget(_wrap(services));
      await tester.pump();

      // Emit a real fix at Melun centre — the spawn callsite MUST run,
      // but the WispParticleSystem.spawnAtNewDisc warm-up gate MUST
      // suppress all spawns because <5 s of real wall-clock has elapsed
      // since the system constructed.
      emitter.add(
        Position(
          latitude: 48.5397,
          longitude: 2.6553,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          accuracy: 1,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
      await tester.pump();

      expect(
        wispParticleSystem.activeCount,
        0,
        reason: 'WISP-03 / SC #2: warm-up gate MUST suppress all spawns during the first 5 s of MapScreen lifetime, even when a real fix arrives.',
      );

      // Cleanup.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      await emitter.close();
      await probe.dispose();
    });

    testWidgets('No wisps appear at synthetic (0, 0) coordinates if a fix has not yet arrived — SC #2 anti-pattern guard', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      final wispParticleSystem = WispParticleSystem();
      final wispTransformLogger = WispTransformLogger();
      final repo = RevealDiscRepository();
      final emitter = StreamController<Position>.broadcast();
      final probe = FrameDeltaProbe();

      final services = MapScreenServices(
        pmtilesPath: _nonExistentPmtilesPath,
        // Stream that NEVER emits — Phase 2 GPS contract: no fix yet → no
        // synthetic (0, 0) Position injected.
        positionStreamFactory: () => emitter.stream,
        discRepository: repo,
        frameDeltaProbe: probe,
        fogTransformLogger: FogTransformLogger(),
        wispParticleSystem: wispParticleSystem,
        wispTransformLogger: wispTransformLogger,
        fogProgramLoaderOverride: _pendingFogProgram,
      );
      await tester.pumpWidget(_wrap(services));
      await tester.pump();

      expect(repo.snapshot(), isEmpty, reason: 'SC #2: with NO fix, the disc repository MUST stay empty — no synthetic (0, 0) disc should materialise.');
      expect(
        wispParticleSystem.activeCount,
        0,
        reason: 'SC #2: with NO fix and an empty disc repository, no wisps should spawn anywhere — least of all at (lat=0, lon=0).',
      );

      // Sanity check: even if someone DOES emit a (0, 0) fix later (e.g.
      // a buggy stream), the warm-up gate still suppresses spawns. We
      // assert this in-line rather than as a separate test because
      // (a) the Phase 2 GPS subsystem is contractually disallowed from
      // emitting (0, 0) and (b) the warm-up gate is the second-line
      // defense already covered by the test above.
      emitter.add(_zeroPosition());
      await tester.pump();
      expect(
        wispParticleSystem.activeCount,
        0,
        reason: 'SC #2 anti-pattern guard: a (0, 0) fix during warmup STILL produces zero wisps (warm-up gate is the firewall).',
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      await emitter.close();
      await probe.dispose();
    });
  });
}
