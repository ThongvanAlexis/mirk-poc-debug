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
import 'package:mirk_poc_debug/presentation/widgets/map_compass.dart';

/// Records `rotate` calls and lets the test push synthetic MapEventRotate
/// events into the controller's `mapEventStream` so MapCompass can observe
/// camera bearing changes without a real FlutterMap.
class _RecordingMapController implements MapController {
  final List<double> rotateCalls = <double>[];
  final StreamController<MapEvent> _events = StreamController<MapEvent>.broadcast();
  double currentBearing = 0;

  void emitRotate(double newBearing) {
    currentBearing = newBearing;
    // We emit a sentinel-typed event consumers can pattern-match on; the real
    // production widget filters on `is MapEventRotate` so any subtype works.
    _events.add(_FakeMapEventRotate(newBearing));
  }

  @override
  Stream<MapEvent> get mapEventStream => _events.stream;

  @override
  bool rotate(double degree, {String? id}) {
    rotateCalls.add(degree);
    currentBearing = degree;
    return true;
  }

  @override
  bool move(LatLng center, double zoom, {Offset offset = Offset.zero, String? id}) => throw UnimplementedError('Test fake: move not used by MapCompass');

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

  @override
  MapCamera get camera => throw UnimplementedError('Test fake: camera getter not exercised in these tests');

  @override
  void dispose() {
    _events.close();
  }
}

/// Minimal fake — production code only narrows on `is MapEventRotate`, never
/// reads `.camera`, `.source`, etc. Wave 0 contract is enough.
class _FakeMapEventRotate implements MapEventRotate {
  _FakeMapEventRotate(this.targetBearing);
  final double targetBearing;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeMapEventRotate exposes only targetBearing; ${invocation.memberName} not implemented.');
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('MapCompass', () {
    testWidgets('snap-to-north on tap completes in kPocCompassAnimationMs and ends at 0°', (tester) async {
      final controller = _RecordingMapController()..currentBearing = 90;

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();

      // Tap the compass widget. Plan 02-04 will give it a hit-targetable size.
      await tester.tap(find.byType(MapCompass), warnIfMissed: false);
      for (var elapsed = 0; elapsed <= kPocCompassAnimationMs; elapsed += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(controller.rotateCalls, isNotEmpty, reason: 'Tap MUST drive at least one MapController.rotate during the snap animation.');
      expect(controller.rotateCalls.last, closeTo(0, 1e-6), reason: 'Final rotate MUST land on north (0°).');
      // Trajectory sanity: bearing should monotonically decrease toward 0°
      // from 90° (no overshoot through 180°).
      for (var i = 1; i < controller.rotateCalls.length; i++) {
        expect(
          controller.rotateCalls[i],
          lessThanOrEqualTo(controller.rotateCalls[i - 1]),
          reason: 'Snap from 90° MUST decrease monotonically — overshoot through 180° is forbidden.',
        );
      }

      controller.dispose();
    });

    testWidgets('rebuilds on MapEventRotate (camera bearing changes drive widget rotation)', (tester) async {
      final controller = _RecordingMapController();

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();

      // Record the initial Transform.rotate angle (or absence thereof).
      final transformsBefore = tester.widgetList<Transform>(find.descendant(of: find.byType(MapCompass), matching: find.byType(Transform))).toList();

      // Simulate the camera rotating to 45°.
      controller.emitRotate(45 * pi / 180);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();

      final transformsAfter = tester.widgetList<Transform>(find.descendant(of: find.byType(MapCompass), matching: find.byType(Transform))).toList();
      // Either MapCompass starts producing a Transform after the event, or its
      // existing Transform's matrix changes. We just assert "something rebuilt".
      expect(
        transformsAfter.length != transformsBefore.length || transformsAfter.toString() != transformsBefore.toString(),
        isTrue,
        reason: 'MapEventRotate MUST trigger a rebuild that changes the rendered transform (visual bearing tracks camera).',
      );

      controller.dispose();
    });

    testWidgets('shortest-path snap from 350° goes forward through 360°/0°, not back through 0° via -350°', (tester) async {
      final controller = _RecordingMapController()..currentBearing = 350 * pi / 180;

      await tester.pumpWidget(_wrap(MapCompass(mapController: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MapCompass), warnIfMissed: false);
      for (var elapsed = 0; elapsed <= kPocCompassAnimationMs; elapsed += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      // The trajectory MUST move forward (350° → 360° = 0°), not backward
      // through 0°. Sample inspection: every bearing (mod 2π) should approach
      // 0 from the upper half of the circle, never crossing into 180°+ region
      // on the negative path.
      final samples = controller.rotateCalls;
      expect(samples, isNotEmpty);
      for (final degRad in samples) {
        final mod = degRad % (2 * pi);
        // Forward shortest path stays in [350°/360°≈0..0°] which after mod
        // collapses to either >=350° (still ramping forward) or 0° (landed).
        // Failing test: backward path would visit 180°.
        expect(
          mod >= 340 * pi / 180 || mod <= 1e-3,
          isTrue,
          reason: 'Shortest-path snap from 350° MUST stay near the high end of the circle, never visit ~180°. Got: ${mod * 180 / pi}°.',
        );
      }

      controller.dispose();
    });
  });
}
