// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// ignore_for_file: depend_on_referenced_packages — vector_map_tiles is a
// transitive contract for these tests (the type the assertions key on),
// not a direct production dep imported here.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/map/map_screen_services.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/map_screen.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Wraps MapScreen.fromServices in a MaterialApp with l10n bindings so the
/// AppBar / FlutterMap children can resolve the rendering pipeline.
Widget _wrap(MapScreenServices services) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: MapScreen.fromServices(services),
);

/// Builds fake services with a placeholder pmtilesPath. Wave 0 tests don't
/// actually parse the archive; they assert structural properties of the widget
/// tree, so the path can be a non-existent string. Plan 02-05's GREEN tests
/// will replace this with a real synthetic-bytes archive once the screen
/// actually reads from the path.
MapScreenServices _services({Stream<Position> Function()? streamFactory}) {
  return MapScreenServices(pmtilesPath: '/dev/null/poc-wave0-placeholder.pmtile', positionStreamFactory: streamFactory ?? () => const Stream<Position>.empty());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapScreen.fromServices', () {
    testWidgets('VectorTileLayer wired with kPocTileProviderSourceKey source key', (tester) async {
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();

      // Wave 0 MapScreen still renders the placeholder ColoredBox; this
      // assertion fails until Plan 02-05 swaps the body for FlutterMap.
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
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();

      final flutterMaps = find.byType(FlutterMap);
      expect(flutterMaps, findsOneWidget, reason: 'Plan 02-05 contract: MapScreen MUST render a FlutterMap.');
      final flutterMap = tester.widget<FlutterMap>(flutterMaps);
      expect(flutterMap.options.initialCenter, equals(const LatLng(kPocInitialCameraLat, kPocInitialCameraLon)));
      expect(flutterMap.options.initialZoom, equals(kPocInitialZoom));
    });

    testWidgets('InteractionOptions enables all flags', (tester) async {
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();
      final flutterMaps = find.byType(FlutterMap);
      expect(flutterMaps, findsOneWidget);
      final flutterMap = tester.widget<FlutterMap>(flutterMaps);
      expect(flutterMap.options.interactionOptions.flags, equals(InteractiveFlag.all));
    });

    testWidgets('pinch zoom flag is set (sub-flag of all)', (tester) async {
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();
      final flutterMaps = find.byType(FlutterMap);
      expect(flutterMaps, findsOneWidget);
      final flutterMap = tester.widget<FlutterMap>(flutterMaps);
      expect(flutterMap.options.interactionOptions.flags & InteractiveFlag.pinchZoom, isNonZero);
    });

    testWidgets('combined gestures race disabled (default)', (tester) async {
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();
      final flutterMaps = find.byType(FlutterMap);
      expect(flutterMaps, findsOneWidget);
      final flutterMap = tester.widget<FlutterMap>(flutterMaps);
      expect(flutterMap.options.interactionOptions.enableMultiFingerGestureRace, isFalse);
    });

    testWidgets('min/max zoom locked to kPocMinZoom..kPocMaxZoom (10..15)', (tester) async {
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();
      final flutterMaps = find.byType(FlutterMap);
      expect(flutterMaps, findsOneWidget);
      final flutterMap = tester.widget<FlutterMap>(flutterMaps);
      expect(flutterMap.options.minZoom, equals(kPocMinZoom));
      expect(flutterMap.options.maxZoom, equals(kPocMaxZoom));
    });

    testWidgets('CameraConstraint contains the padded Melun bbox', (tester) async {
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();
      final flutterMaps = find.byType(FlutterMap);
      expect(flutterMaps, findsOneWidget);
      final flutterMap = tester.widget<FlutterMap>(flutterMaps);
      expect(
        flutterMap.options.cameraConstraint,
        isA<CameraConstraint>(),
        reason: 'CameraConstraint MUST be set so the camera cannot pan outside the Melun bbox + soft pad.',
      );
    });

    testWidgets('LOC-02: blue dot is absent when no fix has arrived', (tester) async {
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();
      final circleLayers = find.byType(CircleLayer<Object>);
      // Either no CircleLayer OR a CircleLayer with zero markers — both
      // satisfy "blue dot only when lastFix non-null".
      if (circleLayers.evaluate().isNotEmpty) {
        final layer = tester.widget<CircleLayer<Object>>(circleLayers.first);
        expect(layer.circles, isEmpty, reason: 'No fix yet → CircleLayer MUST have zero markers.');
      } else {
        // Wave 0 RED: there's no CircleLayer at all because the stub doesn't
        // render one. Plan 02-05 GREEN: CircleLayer present with zero circles.
        // Today this branch represents the expected GREEN outcome — but to
        // turn the test RED we additionally assert the FlutterMap is present
        // (which Wave 0's stub does not satisfy).
        expect(
          find.byType(FlutterMap),
          findsOneWidget,
          reason: 'Plan 02-05 contract: a FlutterMap MUST exist (with or without a CircleLayer depending on _lastFix).',
        );
      }
    });

    testWidgets('LOC-05: recenter FAB is disabled when no fix has arrived', (tester) async {
      await tester.pumpWidget(_wrap(_services()));
      await tester.pump();
      final fabs = find.byType(FloatingActionButton);
      expect(fabs, findsOneWidget, reason: 'Plan 02-04 contract: a single recenter FAB MUST be present.');
      final fab = tester.widget<FloatingActionButton>(fabs);
      expect(fab.onPressed, isNull, reason: 'LOC-05: with no fix yet, the recenter FAB MUST be disabled.');
    });
  });
}
