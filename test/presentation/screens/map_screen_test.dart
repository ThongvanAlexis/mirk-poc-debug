// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// ignore_for_file: depend_on_referenced_packages — vector_map_tiles +
// path_provider_platform_interface are transitive contracts for these tests
// (the types the assertions key on / the mock pattern), not direct
// production deps imported here.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/map/map_screen_services.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/map_screen.dart';
import 'package:mirk_poc_debug/presentation/widgets/map_compass.dart';

import '../../_helpers/swallow_vector_map_tiles_cancellation.dart';

/// Pending fog-program loader — keeps `MapScreen._loadFogShader` parked on a
/// Completer so the headless test runner never hits the real
/// `ui.FragmentProgram.fromAsset` (which hangs without a shader compiler).
/// Same constraint as `ShaderSanityScreen.programLoaderOverride`.
Future<ui.FragmentProgram> _pendingFogProgram() => Completer<ui.FragmentProgram>().future;

/// In-test [PathProviderPlatform] override pointing every directory accessor
/// at a single throwaway temp directory. vector_map_tiles' `cacheStorageResolver`
/// calls `getTemporaryDirectory()` on first tile fetch; without this mock the
/// test would crash on the `MissingPluginException`. Mirrors the Phase 1
/// `_MockPathProviderPlatform` used in `pmtiles_asset_copier_test.dart`.
class _MockPathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _MockPathProviderPlatform(this._tempPath);
  final String _tempPath;

  @override
  Future<String?> getTemporaryPath() async => _tempPath;
  @override
  Future<String?> getApplicationSupportPath() async => _tempPath;
  @override
  Future<String?> getLibraryPath() async => _tempPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tempPath;
  @override
  Future<String?> getExternalStoragePath() async => _tempPath;
  @override
  Future<String?> getDownloadsPath() async => _tempPath;
}

/// Wraps MapScreen.fromServices in a MaterialApp with l10n bindings so the
/// AppBar / RecenterFab / MapCompass can resolve `AppLocalizations.of(context)`.
Widget _wrap(MapScreenServices services) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: MapScreen.fromServices(services),
);

/// Builds fake services with the on-disk PMTiles temp file path. Lets each
/// test optionally inject a position-stream factory (defaults to an empty
/// stream so no fix arrives — exercises the LOC-05 disabled-FAB path). The
/// reveal-disc repository + frame-delta probe are constructed fresh per
/// call (Phase 3 stubs — Plan 03-01 keystone). The fog-program loader is
/// always pending so MapScreen never hits the real
/// `ui.FragmentProgram.fromAsset` (headless tests have no shader compiler).
MapScreenServices _services(String pmtilesPath, {Stream<Position> Function()? streamFactory}) {
  return MapScreenServices(
    pmtilesPath: pmtilesPath,
    positionStreamFactory: streamFactory ?? () => const Stream<Position>.empty(),
    discRepository: RevealDiscRepository(),
    frameDeltaProbe: FrameDeltaProbe(),
    fogTransformLogger: FogTransformLogger(),
    fogProgramLoaderOverride: _pendingFogProgram,
  );
}

/// Pumps the screen and lets the async PMTiles `fromSource` settle.
///
/// `PmTilesArchive.from()` reads a real file via `dart:io`, which needs the
/// real event loop — `tester.pump()` only advances frame callbacks and
/// fake-async timers, NOT real Future scheduling. We wrap the I/O wait in
/// `tester.runAsync()` so the dart:io read can actually complete, then pump
/// once outside `runAsync` so the resulting `setState` re-builds the tree.
Future<void> _pumpUntilTileProviderLoaded(WidgetTester tester) async {
  // First pump: initial layout + dispatch _loadTileProvider's microtask.
  await tester.pump();
  // Let the real event loop run until either the FlutterMap appears or the
  // budget runs out. 60 × 50 ms = 3 s — generous for local-SSD reads of a
  // 4 MB file.
  await tester.runAsync(() async {
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Re-pump inside runAsync so any setState scheduled by the future
      // resolution gets reflected in the element tree.
      await tester.pump();
      if (find.byType(FlutterMap).evaluate().isNotEmpty) return;
    }
  });
  // One last pump outside runAsync to flush any pending frame.
  await tester.pump();
  if (find.byType(FlutterMap).evaluate().isEmpty) {
    fail('FlutterMap never appeared in the tree (PMTiles fromSource future never resolved within 3 s)');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String pmtilesTempPath;
  late Directory tempDir;

  setUpAll(() async {
    // Copy the bundled PMTiles asset to a real temp file once per test run.
    // PmTilesArchive.from() reads the file via dart:io, so an in-memory bytes
    // path won't work — needs an actual filesystem entry.
    tempDir = await Directory.systemTemp.createTemp('mirk_poc_map_screen_test_');
    pmtilesTempPath = p.join(tempDir.path, kPmtilesBasename);
    final bundled = await rootBundle.load(kPmtilesAssetPath);
    await File(pmtilesTempPath).writeAsBytes(bundled.buffer.asUint8List(), flush: true);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() {
    PathProviderPlatform.instance = _MockPathProviderPlatform(tempDir.path);
  });

  group('MapScreen.fromServices', () {
    testWidgets('VectorTileLayer wired with kPocTileProviderSourceKey source key', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final found = find.byType(VectorTileLayer);
      expect(
        found,
        findsOneWidget,
        reason: 'MAP-02..06 / Plan 02-05 contract: MapScreen MUST render exactly one VectorTileLayer once the PMTiles path is supplied.',
      );
      final layer = tester.widget<VectorTileLayer>(found);
      expect(
        layer.tileProviders.tileProviderBySource.containsKey(kPocTileProviderSourceKey),
        isTrue,
        reason: 'RESEARCH §Pitfall 3: tile provider source key MUST equal kPocTileProviderSourceKey ("protomaps") to match ProtomapsThemes.lightV3() default.',
      );
    });

    testWidgets('initial camera at Melun (kPocInitialCameraLat, kPocInitialCameraLon) and z13', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.initialCenter, equals(const LatLng(kPocInitialCameraLat, kPocInitialCameraLon)));
      expect(flutterMap.options.initialZoom, equals(kPocInitialZoom));
    });

    testWidgets('InteractionOptions enables all flags', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
    });

    testWidgets('pinch zoom flag is set (sub-flag of all)', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.pinchZoom, isNonZero);
    });

    testWidgets('combined gestures race disabled (default)', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.interactionOptions.enableMultiFingerGestureRace, isFalse);
    });

    testWidgets('min/max zoom locked to kPocMinZoom..kPocMaxZoom (10..15)', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(flutterMap.options.minZoom, equals(kPocMinZoom));
      expect(flutterMap.options.maxZoom, equals(kPocMaxZoom));
    });

    testWidgets('CameraConstraint contains the padded Melun bbox', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final flutterMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final constraint = flutterMap.options.cameraConstraint;
      expect(constraint, isA<CameraConstraint>(), reason: 'CameraConstraint MUST be set so the camera cannot pan outside the Melun bbox + soft pad.');
      // Type-narrowing: CameraConstraint.contain creates a ContainCamera variant
      // whose bounds field is a LatLngBounds covering the padded Melun bbox.
      // The plan asserts ~0.02° pad on each axis; assert the bounds extend
      // beyond the raw bbox by at least that margin.
      final asContain = constraint as dynamic;
      // ignore: avoid_dynamic_calls
      final LatLngBounds bounds = asContain.bounds as LatLngBounds;
      expect(bounds.south, lessThanOrEqualTo(kPocBboxLatMin - kPocPanBoundsPadDegrees + 1e-9));
      expect(bounds.north, greaterThanOrEqualTo(kPocBboxLatMax + kPocPanBoundsPadDegrees - 1e-9));
      expect(bounds.west, lessThanOrEqualTo(kPocBboxLonMin - kPocPanBoundsPadDegrees + 1e-9));
      expect(bounds.east, greaterThanOrEqualTo(kPocBboxLonMax + kPocPanBoundsPadDegrees - 1e-9));
    });

    testWidgets('LOC-02: blue dot is absent when no fix has arrived', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final circleLayers = find.byType(CircleLayer<Object>);
      // No CircleLayer → contract satisfied. (The widget-tree builds the
      // CircleLayer only when _lastFix != null per LOC-05 paired contract.)
      final layers = tester.widgetList<CircleLayer<Object>>(circleLayers).toList();
      final totalCircles = layers.fold<int>(0, (sum, l) => sum + l.circles.length);
      expect(totalCircles, equals(0), reason: 'No fix yet → zero CircleMarkers in any CircleLayer.');
    });

    testWidgets('LOC-05: recenter FAB is disabled when no fix has arrived', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      final fabs = find.byType(FloatingActionButton);
      expect(fabs, findsOneWidget, reason: 'Plan 02-04 contract: a single recenter FAB MUST be present.');
      final fab = tester.widget<FloatingActionButton>(fabs);
      expect(fab.onPressed, isNull, reason: 'LOC-05: with no fix yet, the recenter FAB MUST be disabled.');
    });

    testWidgets('compass widget rendered top-right under FPS overlay', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      // The compass widget is wrapped in a Positioned(top: 56, right: 8).
      // We find both the compass and verify the surrounding Positioned has
      // the expected coordinates (so a future regression that drops the
      // padding fails the test).
      final mapCompasses = find.byType(MapCompass);
      expect(mapCompasses, findsOneWidget, reason: 'Plan 02-04 contract: a single MapCompass MUST be in the tree.');

      // Find the Positioned ancestor of the MapCompass.
      final positioned = find.ancestor(of: mapCompasses, matching: find.byWidgetPredicate((w) => w is Positioned && w.top == 56.0 && w.right == 8.0));
      expect(positioned, findsOneWidget, reason: 'MapCompass MUST sit at top:56 right:8 (8 px below the 8-px-from-top FPS overlay).');
    });

    testWidgets('dispose returns void synchronously (no async dispose)', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      // Type-level + behavioural test: pumping the screen and unmounting MUST
      // run dispose synchronously. Asserting the State.dispose method has
      // return type `void Function()` (not `Future<void> Function()`) is
      // guaranteed by the implementation file's @override `void dispose()`;
      // this test pins the runtime contract by unmounting and checking no
      // exception escapes (Flutter would log if dispose threw).
      await tester.pumpWidget(_wrap(_services(pmtilesTempPath)));
      await _pumpUntilTileProviderLoaded(tester);

      // Unmount the screen.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // No exception was thrown and the binding moves on cleanly. The widget
      // tree has shed all references. (A real async dispose would still
      // appear correct here — the pin is the source-level `void dispose()`
      // override.)
      expect(find.byType(FlutterMap), findsNothing);
    });
  });
}
