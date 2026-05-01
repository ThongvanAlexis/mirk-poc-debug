// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mirk_poc_debug/domain/map/map_screen_services.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/map_screen.dart';

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

MapScreenServices _services({Stream<Position> Function()? streamFactory}) {
  return MapScreenServices(pmtilesPath: '/dev/null/poc-wave0-placeholder.pmtile', positionStreamFactory: streamFactory ?? () => const Stream<Position>.empty());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapScreen GPS lifecycle (LOC-01)', () {
    testWidgets('initState subscribes via positionStreamFactory exactly once', (tester) async {
      var factoryCallCount = 0;
      final controller = StreamController<Position>.broadcast();
      addTearDown(controller.close);

      final services = _services(
        streamFactory: () {
          factoryCallCount++;
          return controller.stream;
        },
      );
      await tester.pumpWidget(_wrap(services));
      await tester.pump();

      expect(factoryCallCount, equals(1), reason: 'MapScreen.initState MUST call positionStreamFactory exactly once.');
    });

    testWidgets('dispose cancels the GPS subscription', (tester) async {
      final controller = StreamController<Position>.broadcast();
      addTearDown(controller.close);

      final services = _services(streamFactory: () => controller.stream);
      await tester.pumpWidget(_wrap(services));
      await tester.pump();
      expect(controller.hasListener, isTrue, reason: 'After initState, the test stream MUST have an active listener.');

      // Replace MapScreen with an unrelated widget so it unmounts.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      expect(controller.hasListener, isFalse, reason: 'MapScreen.dispose MUST cancel the GPS StreamSubscription (no leaks).');
    });

    testWidgets('a new fix triggers setState and renders the blue dot', (tester) async {
      final controller = StreamController<Position>.broadcast();
      addTearDown(controller.close);

      final services = _services(streamFactory: () => controller.stream);
      await tester.pumpWidget(_wrap(services));
      await tester.pump();

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
      final controller = StreamController<Position>.broadcast();
      addTearDown(controller.close);

      final services = _services(streamFactory: () => controller.stream);
      await tester.pumpWidget(_wrap(services));
      await tester.pump();

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
