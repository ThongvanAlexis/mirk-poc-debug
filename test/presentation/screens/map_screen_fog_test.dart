// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/map/map_screen_services.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/map_screen.dart';
import 'package:mirk_poc_debug/presentation/widgets/frame_delta_probe_overlay.dart';

import '../../_helpers/swallow_vector_map_tiles_cancellation.dart';

/// MapScreen × Phase 3 integration — GPS-fix → discRepository.append (FOG-01)
/// + FrameDeltaProbeOverlay mounted at the documented Stack position (FOG-08).
///
/// FogLayer-mount-after-shader-resolves is NOT tested here:
///   * `dart:ui`'s `FragmentShader` is a `base` class (cannot be subclassed
///     from a test file).
///   * `FragmentProgram.fromAsset()` resolves through the platform shader
///     compiler that is unavailable in `flutter test` headless runners.
///   * Same constraint exercised + documented in
///     `test/presentation/screens/shader_sanity_screen_test.dart` (Plan 03-06).
///   * Verified end-to-end via the pre-walk `/sanity` smoke screen + the
///     sideload UAT walk in Plan 03-08.
///
/// Teardown discipline pinned by Plan 03-07 deviation note: probe.dispose()
/// + emitter.close() are awaited IN BODY (after the screen unmounts) rather
/// than through `addTearDown`. The StreamController.close() future appears
/// to occasionally not resolve under flutter_test's tearDown scheduler when
/// the probe's broadcast controller has had a now-cancelled overlay
/// listener — awaiting close() inside the body is deterministic and avoids
/// the 10-min timeout we hit in CI.

/// Builds a Position with fixed values — only lat/lon vary in these tests.
Position _position({required double lat, required double lon}) => Position(
  latitude: lat,
  longitude: lon,
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

/// Non-existent PMTiles path. The GPS-subscription + frame-delta-probe wiring
/// in MapScreen.initState run BEFORE the PMTiles future settles — these tests
/// never need a real archive and skipping it avoids vector_map_tiles holding a
/// temp directory open across test bodies (Windows file-lock teardown error).
const String _nonExistentPmtilesPath = '/non/existent/test.pmtile';

/// Builds a never-completing fog-program loader. The real
/// `ui.FragmentProgram.fromAsset` hangs in headless `flutter test` (no
/// shader compiler) — same constraint pinned by `ShaderSanityScreen.programLoaderOverride`.
Future<ui.FragmentProgram> _pendingFogProgram() => Completer<ui.FragmentProgram>().future;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapScreen × Phase 3 (FOG-01 disc append + FOG-08 overlay mount)', () {
    testWidgets('FOG-01: every GPS fix appends one disc with kPocRevealDiscRadiusMeters', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      final repo = RevealDiscRepository();
      final probe = FrameDeltaProbe();
      final emitter = StreamController<Position>.broadcast();

      final services = MapScreenServices(
        pmtilesPath: _nonExistentPmtilesPath,
        positionStreamFactory: () => emitter.stream,
        discRepository: repo,
        frameDeltaProbe: probe,
        fogTransformLogger: FogTransformLogger(),
        fogProgramLoaderOverride: _pendingFogProgram,
      );
      await tester.pumpWidget(_wrap(services));
      // No need to wait for the FlutterMap — the GPS subscribe path is set up
      // in initState before the PMTiles future settles.
      await tester.pump();

      expect(repo.snapshot(), isEmpty, reason: 'pre-fix: repository starts empty');

      emitter.add(_position(lat: 48.5397, lon: 2.6553));
      await tester.pump();
      expect(repo.snapshot(), hasLength(1), reason: 'first fix → first disc appended');
      final firstDisc = repo.snapshot().first;
      expect(firstDisc.lat, 48.5397);
      expect(firstDisc.lon, 2.6553);
      expect(firstDisc.radiusMeters, kPocRevealDiscRadiusMeters);
      expect(firstDisc.fixedAtUtc.isUtc, isTrue, reason: 'fixedAtUtc MUST be UTC (DateTime.now().toUtc())');

      emitter.add(_position(lat: 48.5400, lon: 2.6555));
      await tester.pump();
      expect(repo.snapshot(), hasLength(2), reason: 'second fix → second disc appended');
      expect(repo.snapshot().last.id, isNot(repo.snapshot().first.id), reason: 'each disc has a unique ID');

      // In-body teardown — see top-of-file deviation note for rationale.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      await emitter.close();
      await probe.dispose();
    });

    testWidgets('FOG-08: FrameDeltaProbeOverlay mounted at top:kPocFrameDeltaProbeOverlayTopPx right:kPocFrameDeltaProbeOverlayRightPx', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      final probe = FrameDeltaProbe();
      final emitter = StreamController<Position>.broadcast();

      final services = MapScreenServices(
        pmtilesPath: _nonExistentPmtilesPath,
        positionStreamFactory: () => emitter.stream,
        discRepository: RevealDiscRepository(),
        frameDeltaProbe: probe,
        fogTransformLogger: FogTransformLogger(),
        fogProgramLoaderOverride: _pendingFogProgram,
      );
      await tester.pumpWidget(_wrap(services));
      await tester.pump();

      final overlay = find.byType(FrameDeltaProbeOverlay);
      expect(overlay, findsOneWidget, reason: 'FOG-08: exactly one FrameDeltaProbeOverlay MUST be in the tree');

      final positioned = find.ancestor(
        of: overlay,
        matching: find.byWidgetPredicate((w) => w is Positioned && w.top == kPocFrameDeltaProbeOverlayTopPx && w.right == kPocFrameDeltaProbeOverlayRightPx),
      );
      expect(
        positioned,
        findsOneWidget,
        reason:
            'overlay MUST sit at top:$kPocFrameDeltaProbeOverlayTopPx right:$kPocFrameDeltaProbeOverlayRightPx '
            '(directly below the FpsCounterOverlay+MapCompass cluster)',
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      await emitter.close();
      await probe.dispose();
    });

    testWidgets('FOG-01: a fix arriving AFTER dispose does NOT throw and does NOT append', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      final repo = RevealDiscRepository();
      final probe = FrameDeltaProbe();
      final emitter = StreamController<Position>.broadcast();

      final services = MapScreenServices(
        pmtilesPath: _nonExistentPmtilesPath,
        positionStreamFactory: () => emitter.stream,
        discRepository: repo,
        frameDeltaProbe: probe,
        fogTransformLogger: FogTransformLogger(),
        fogProgramLoaderOverride: _pendingFogProgram,
      );
      await tester.pumpWidget(_wrap(services));
      await tester.pump();

      // Unmount.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // Late fix — the subscription was cancelled in dispose. No-op.
      emitter.add(_position(lat: 48.5500, lon: 2.6700));
      await tester.pump();
      expect(repo.snapshot(), isEmpty, reason: 'fix-after-dispose MUST be a no-op (subscription cancelled)');

      await emitter.close();
      await probe.dispose();
    });
  });
}
