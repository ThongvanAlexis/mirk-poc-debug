// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/widgets/map_compass.dart';

/// Records `rotate` calls and lets the test push synthetic MapEventRotate
/// events into the controller's `mapEventStream` so MapCompass can observe
/// camera bearing changes without a real FlutterMap.
class _RecordingMapController implements MapController {
  _RecordingMapController({this.initialRotationDegrees = 0});

  final double initialRotationDegrees;

  final List<double> rotateCalls = <double>[];
  final StreamController<MapEvent> _events = StreamController<MapEvent>.broadcast();
  double _currentRotationDegrees = 0;

  /// Build a synthetic MapCamera with the given rotation. Required because
  /// MapEventRotate.camera.rotation is what production reads to update its
  /// own bearing snapshot.
  MapCamera _cameraWithRotation(double rotationDegrees) => MapCamera(
        crs: const Epsg3857(),
        center: const LatLng(48.5397, 2.6553),
        zoom: 13,
        rotation: rotationDegrees,
        nonRotatedSize: MapCamera.kImpossibleSize,
      );

  /// Push a synthetic MapEventRotate with the new bearing into the stream.
  /// Production widget filters on `is MapEventRotate` and reads
  /// `event.camera.rotation`.
  void emitRotateDegrees(double newRotationDegrees) {
    _currentRotationDegrees = newRotationDegrees;
    _events.add(MapEventRotate(
      id: null,
      source: MapEventSource.mapController,
      oldCamera: _cameraWithRotation(_currentRotationDegrees),
      camera: _cameraWithRotation(newRotationDegrees),
    ));
  }

  @override
  Stream<MapEvent> get mapEventStream => _events.stream;

  @override
  bool rotate(double degree, {String? id}) {
    rotateCalls.add(degree);
    _currentRotationDegrees = degree;
    return true;
  }

  @override
  bool move(LatLng center, double zoom, {Offset offset = Offset.zero, String? id}) =>
      throw UnimplementedError('Test fake: move not used by MapCompass');

  // MoveAndRotateResult is a non-exported typedef in flutter_map 7.0.2 — see
  // lib/src/misc/move_and_rotate_result.dart. Spelling it as the structural
  // record type satisfies the abstract MapController interface without
  // depending on a private import.
  @override
  ({bool moveSuccess, bool rotateSuccess}) rotateAroundPoint(double degree, {Point<double>? point, Offset? offset, String? id}) =>
      throw UnimplementedError('Test fake: rotateAroundPoint not used by MapCompass');

  @override
  ({bool moveSuccess, bool rotateSuccess}) moveAndRotate(LatLng center, double zoom, double degree, {String? id}) =>
      throw UnimplementedError('Test fake: moveAndRotate not used by MapCompass');

  @override
  bool fitCamera(CameraFit cameraFit) => throw UnimplementedError('Test fake: fitCamera not used by MapCompass');

  /// Returns a MapCamera with the most recent rotation applied — production
  /// reads this on initState to seed its bearing field.
  @override
  MapCamera get camera => _cameraWithRotation(_currentRotationDegrees == 0 ? initialRotationDegrees : _currentRotationDegrees);

  @override
  void dispose() {
    _events.close();
  }
}

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );

void main() {
  group('mapCompassShortestPathToNorth (helper unit tests — RESEARCH Open Question #2)', () {
    test('350° → +10° (forward shortest path through 360°/0°)', () {
      expect(mapCompassShortestPathToNorth(350), closeTo(10, 1e-9));
    });

    test('10° → -10° (backward shortest path through 0°)', () {
      expect(mapCompassShortestPathToNorth(10), closeTo(-10, 1e-9));
    });

    test('180° → 180° or -180° (degenerate; either direction is fine)', () {
      // Ambiguous case — implementation may pick either branch. Accept both.
      final delta = mapCompassShortestPathToNorth(180);
      expect(delta.abs(), closeTo(180, 1e-9));
    });

    test('0° → 0° (already at north)', () {
      expect(mapCompassShortestPathToNorth(0), closeTo(0, 1e-9));
    });

    test('270° → +90° (forward shortest path)', () {
      expect(mapCompassShortestPathToNorth(270), closeTo(90, 1e-9));
    });

    test('90° → -90° (backward shortest path)', () {
      expect(mapCompassShortestPathToNorth(90), closeTo(-90, 1e-9));
    });
  });

  group('MapCompass', () {
    testWidgets('snap-to-north on tap completes in 250 ms', (tester) async {
      final controller = _RecordingMapController(initialRotationDegrees: 90);

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      const totalMs = kPocCompassAnimationMs;
      const stepMs = 16;
      for (var elapsed = 0; elapsed <= totalMs; elapsed += stepMs) {
        await tester.pump(const Duration(milliseconds: stepMs));
      }
      await tester.pumpAndSettle();

      expect(controller.rotateCalls.length, greaterThanOrEqualTo(5),
          reason: 'A 250 ms animation MUST emit several intermediate rotates; >=5 confirms a real per-frame tween.');
      expect(controller.rotateCalls.last, closeTo(0, 1e-6),
          reason: 'Final rotate MUST land on north (0°).');

      controller.dispose();
    });

    testWidgets('rebuilds on MapEventRotate', (tester) async {
      final controller = _RecordingMapController();

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();

      // Initial transform: bearing 0 → angle = 0 → identity rotation.
      Transform _findGlyphTransform() => tester.widget<Transform>(
            find.descendant(of: find.byType(IconButton), matching: find.byType(Transform)).first,
          );
      final transformBefore = _findGlyphTransform();

      // Simulate the camera rotating to 90°. Production should setState and
      // re-render the Transform with a non-identity matrix.
      controller.emitRotateDegrees(90);
      await tester.pumpAndSettle();

      final transformAfter = _findGlyphTransform();
      expect(transformAfter.transform, isNot(equals(transformBefore.transform)),
          reason: 'MapEventRotate MUST trigger a setState that rebuilds the Transform with a new matrix.');

      controller.dispose();
    });

    testWidgets('shortest-path snap from 350° to 0°', (tester) async {
      final controller = _RecordingMapController(initialRotationDegrees: 350);

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      for (var elapsed = 0; elapsed <= kPocCompassAnimationMs; elapsed += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(controller.rotateCalls, isNotEmpty);
      // Forward shortest path: bearings stay >= 350° during the tween (climbing
      // toward 360°), or land exactly on 360°. Backward path would visit 180°.
      for (final degree in controller.rotateCalls) {
        expect(degree >= 350 - 1e-6 && degree <= 360 + 1e-6, isTrue,
            reason: 'Shortest-path snap from 350° MUST stay in [350°, 360°], never visit ~180°. Got: $degree°.');
      }
      expect(controller.rotateCalls.last, closeTo(360, 1e-6),
          reason: 'Final rotate MUST land at 360° (= 0° north on the unit circle).');

      controller.dispose();
    });

    testWidgets('no-op when already at north', (tester) async {
      final controller = _RecordingMapController(); // initialRotationDegrees: 0

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(controller.rotateCalls, isEmpty,
          reason: 'Tap with bearing already at 0° MUST be a no-op — no AnimationController spun up, no rotate emitted.');

      controller.dispose();
    });

    testWidgets('cancels in-flight tween on dispose', (tester) async {
      final controller = _RecordingMapController(initialRotationDegrees: 90);

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      // Pump a fraction of the tween so it's still in flight.
      await tester.pump(const Duration(milliseconds: 50));
      final callsBeforeUnmount = controller.rotateCalls.length;

      // Unmount: pump a different tree.
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      // Pump enough time that the prior 250 ms tween would have completed.
      for (var elapsed = 0; elapsed <= kPocCompassAnimationMs + 50; elapsed += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(controller.rotateCalls.length, equals(callsBeforeUnmount),
          reason: 'After unmount, no further rotate calls MUST be emitted — AnimationController + stream subscription disposed.');

      controller.dispose();
    });

    testWidgets('tooltip is localized', (tester) async {
      final controller = _RecordingMapController();

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, equals('Reset bearing to north'),
          reason: 'Tooltip MUST come from AppLocalizations.compassTooltip (en).');

      controller.dispose();
    });
  });
}
