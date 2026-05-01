// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// geolocator_platform_interface is a transitive dep of geolocator 14.0.2
// (declared in pubspec.lock but not pubspec.yaml). The platform-instance
// override is the documented test seam — same pattern as the
// PermissionHandlerPlatform.instance override used in Phase 1 Plan 01-06.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/infrastructure/location/geolocator_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Test-only [GeolocatorPlatform] override. Captures the [LocationSettings]
/// passed to `getPositionStream` so the LOC-01 test can assert their values
/// without touching real platform channels. Also counts calls to
/// `getLastKnownPosition` for the LOC-03 runtime cross-check.
class _CapturingGeolocatorPlatform extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  LocationSettings? capturedSettings;
  int callCount = 0;
  int lastKnownPositionCallCount = 0;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    callCount++;
    capturedSettings = locationSettings;
    return const Stream<Position>.empty();
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async {
    lastKnownPositionCallCount++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CapturingGeolocatorPlatform mock;

  setUp(() {
    mock = _CapturingGeolocatorPlatform();
    GeolocatorPlatform.instance = mock;
  });

  group('GeolocatorService.stream', () {
    test('LOC-01: invokes getPositionStream with accuracy=best and distanceFilter=kPocGpsDistanceFilterMeters', () async {
      // Subscribe so the underlying getPositionStream is actually called.
      final subscription = GeolocatorService.stream().listen((_) {});
      // Allow microtasks to drain so the platform call lands.
      await Future<void>.delayed(Duration.zero);

      expect(mock.callCount, equals(1), reason: 'GeolocatorService.stream() must invoke GeolocatorPlatform.getPositionStream exactly once.');

      final settings = mock.capturedSettings;
      expect(settings, isNotNull, reason: 'LOC-01 requires explicit LocationSettings; null defaults are forbidden.');
      expect(settings!.accuracy, equals(LocationAccuracy.best), reason: 'LOC-01 mandates LocationAccuracy.best.');
      expect(settings.distanceFilter, equals(kPocGpsDistanceFilterMeters), reason: 'LOC-01 mandates distanceFilter == kPocGpsDistanceFilterMeters (5).');

      await subscription.cancel();
    });

    test('LOC-01: logs the subscription event at INFO level under Logger("domain.location")', () async {
      // Capture log records emitted during the call. Logger.root is the only
      // dispatch target in the POC (see Phase 1 FileLogger bootstrap); attaching
      // a transient listener here doesn't conflict with the FileLogger because
      // FileLogger.bootstrap is not invoked from this unit test.
      final records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);

      final subscription = GeolocatorService.stream().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      // Only INFO records from domain.location are interesting for this assertion.
      final infoRecords = records.where((r) => r.level == Level.INFO && r.loggerName == 'domain.location').toList();

      expect(infoRecords, hasLength(1), reason: 'GeolocatorService.stream() must emit exactly one INFO log per subscribe.');
      expect(
        infoRecords.single.message,
        equals('Subscribing to Geolocator.getPositionStream(accuracy=best, distanceFilter=$kPocGpsDistanceFilterMeters)'),
        reason: 'LOC-01 mandates a specific log line so log audits can confirm the pinned settings at runtime.',
      );

      await subscription.cancel();
      await sub.cancel();
    });

    test('LOC-03: never calls Geolocator.getLastKnownPosition (runtime belt-and-braces)', () async {
      // The static-source CI gate at tool/test/check_no_last_known_position_test.dart
      // is the primary enforcement. This runtime assertion documents the contract
      // at the unit-test level — defence in depth.
      final subscription = GeolocatorService.stream().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(
        mock.lastKnownPositionCallCount,
        equals(0),
        reason: 'LOC-03 forbids Geolocator.getLastKnownPosition (unreliable on iOS).',
      );

      await subscription.cancel();
    });
  });
}
