// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// ignore_for_file: depend_on_referenced_packages — path_provider_platform_interface
// is a transitive contract for the mock pattern, not a direct production dep.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/map/map_screen_services.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_transform_logger.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/map_screen.dart';

import '../../_helpers/swallow_vector_map_tiles_cancellation.dart';

/// Pending fog-program loader — see comment in `map_screen_test.dart`.
Future<ui.FragmentProgram> _pendingFogProgram() => Completer<ui.FragmentProgram>().future;

/// Mirrors the path-provider mock from `map_screen_test.dart` — vector_map_tiles
/// calls `getTemporaryDirectory()` lazily for its tile cache; the mock points
/// every accessor at a per-run temp directory.
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

/// Builds a Position with fixed values — only lat/lon vary in these tests.
Position _pos(double lat, double lon) => Position(
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

MapScreenServices _services(String pmtilesPath, {Stream<Position> Function()? streamFactory}) {
  return MapScreenServices(
    pmtilesPath: pmtilesPath,
    positionStreamFactory: streamFactory ?? () => const Stream<Position>.empty(),
    discRepository: RevealDiscRepository(),
    frameDeltaProbe: FrameDeltaProbe(),
    fogTransformLogger: FogTransformLogger(),
    // Plan 04-04 — wisp wiring on test fixtures (see `map_screen_test.dart`).
    wispParticleSystem: WispParticleSystem(),
    wispTransformLogger: WispTransformLogger(),
    fogProgramLoaderOverride: _pendingFogProgram,
  );
}

/// Pumps until the FlutterMap is mounted (PMTiles `fromSource` future
/// resolved + setState applied). See `map_screen_test.dart` for rationale.
Future<void> _pumpUntilTileProviderLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      if (find.byType(FlutterMap).evaluate().isNotEmpty) return;
    }
  });
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
    tempDir = await Directory.systemTemp.createTemp('mirk_poc_map_screen_gps_test_');
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

  group('MapScreen GPS lifecycle (LOC-01)', () {
    testWidgets('initState subscribes via positionStreamFactory exactly once', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      var factoryCallCount = 0;
      final controller = StreamController<Position>.broadcast();
      addTearDown(controller.close);

      final services = _services(
        pmtilesTempPath,
        streamFactory: () {
          factoryCallCount++;
          return controller.stream;
        },
      );
      await tester.pumpWidget(_wrap(services));
      await _pumpUntilTileProviderLoaded(tester);

      expect(factoryCallCount, equals(1), reason: 'MapScreen.initState MUST call positionStreamFactory exactly once.');
    });

    testWidgets('dispose cancels the GPS subscription', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      final controller = StreamController<Position>.broadcast();
      addTearDown(controller.close);

      final services = _services(pmtilesTempPath, streamFactory: () => controller.stream);
      await tester.pumpWidget(_wrap(services));
      await _pumpUntilTileProviderLoaded(tester);
      expect(controller.hasListener, isTrue, reason: 'After initState, the test stream MUST have an active listener.');

      // Replace MapScreen with an unrelated widget so it unmounts.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      expect(controller.hasListener, isFalse, reason: 'MapScreen.dispose MUST cancel the GPS StreamSubscription (no leaks).');
    });

    testWidgets('a new fix triggers setState and renders the blue dot', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      final controller = StreamController<Position>.broadcast();
      addTearDown(controller.close);

      final services = _services(pmtilesTempPath, streamFactory: () => controller.stream);
      await tester.pumpWidget(_wrap(services));
      await _pumpUntilTileProviderLoaded(tester);

      // Pre-fix: zero CircleMarkers.
      var circleLayers = tester.widgetList<CircleLayer<Object>>(find.byType(CircleLayer<Object>)).toList();
      final preCount = circleLayers.fold<int>(0, (sum, l) => sum + l.circles.length);
      expect(preCount, equals(0), reason: 'Pre-fix: zero CircleMarkers expected.');

      controller.add(_pos(48.5400, 2.6555));
      await tester.pump();
      await tester.pump();

      circleLayers = tester.widgetList<CircleLayer<Object>>(find.byType(CircleLayer<Object>)).toList();
      final postCount = circleLayers.fold<int>(0, (sum, l) => sum + l.circles.length);
      expect(postCount, equals(1), reason: 'After first fix: exactly one CircleMarker (the blue dot).');
    });

    testWidgets('mounted guard: emitting a fix after dispose does NOT throw', (tester) async {
      installVectorMapTilesCancellationFilterForBody();
      final controller = StreamController<Position>.broadcast();
      addTearDown(controller.close);

      final services = _services(pmtilesTempPath, streamFactory: () => controller.stream);
      await tester.pumpWidget(_wrap(services));
      await _pumpUntilTileProviderLoaded(tester);

      // Unmount the screen.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // Emit a fix AFTER unmount. CLAUDE.md mandate: stream listener MUST be
      // a no-op once dispose has run (subscription cancelled in dispose).
      // This must not throw — any exception fails the test.
      controller.add(_pos(48.5500, 2.6700));
      await tester.pump();
      // Implicit: no async error escaped this zone.
    });
  });
}
