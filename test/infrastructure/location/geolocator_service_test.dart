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
import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/infrastructure/location/geolocator_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Test-only [GeolocatorPlatform] override. Captures the [LocationSettings]
/// passed to `getPositionStream` so the LOC-01 test can assert their values
/// without touching real platform channels.
class _CapturingGeolocatorPlatform extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  LocationSettings? capturedSettings;
  int callCount = 0;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    callCount++;
    capturedSettings = locationSettings;
    return const Stream<Position>.empty();
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
  });
}
