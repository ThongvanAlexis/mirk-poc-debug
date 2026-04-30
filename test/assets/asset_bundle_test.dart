// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mirk_poc_debug/config/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Asset bundle', () {
    test('Fra_Melun.pmtile is bundled and ~4 MB', () async {
      final data = await rootBundle.load('assets/maps/Fra_Melun.pmtile');
      const minBytes = 3 * 1024 * 1024;
      const maxBytes = 5 * 1024 * 1024;
      expect(data.lengthInBytes, greaterThan(minBytes));
      expect(data.lengthInBytes, lessThan(maxBytes));
    });

    test('atmospheric_fog.frag is bundled as a compiled IPLR shader package', () async {
      // Flutter's `shaders:` pubspec block compiles GLSL sources into binary
      // IPLR (Impeller Linker Representation) packages at build time. The
      // asset bundle therefore contains the compiled binary, NOT the original
      // GLSL text — `rootBundle.loadString(...)` would throw `FormatException:
      // Invalid UTF-8 byte` because the binary header starts with `1C 00 00 00
      // 49 50 4C 52` ("\x1C\x00\x00\x00IPLR"). This is the correct Flutter
      // packaging behaviour: at runtime the shader is loaded via
      // `FragmentProgram.fromAsset(...)` rather than as raw text.
      //
      // The smoke proof here is that the asset is non-empty and starts with
      // the IPLR magic — this confirms the shader compiler ran and the asset
      // pipeline wired the output through to the test bundle.
      final data = await rootBundle.load('assets/shaders/atmospheric_fog.frag');
      expect(data.lengthInBytes, greaterThan(0), reason: 'Compiled shader package must be non-empty');

      // First 4 bytes are little-endian header length (0x1C = 28); next 4 bytes
      // are ASCII "IPLR" — Flutter's compiled-shader magic.
      final header = data.buffer.asUint8List(0, 8);
      expect(header[4], equals(0x49), reason: 'Byte 4 should be ASCII "I" (IPLR magic)');
      expect(header[5], equals(0x50), reason: 'Byte 5 should be ASCII "P" (IPLR magic)');
      expect(header[6], equals(0x4C), reason: 'Byte 6 should be ASCII "L" (IPLR magic)');
      expect(header[7], equals(0x52), reason: 'Byte 7 should be ASCII "R" (IPLR magic)');
    });
  });

  group('lib/config/constants.dart', () {
    test('kMaxLogsDirBytes equals 10 MB', () {
      expect(kMaxLogsDirBytes, equals(10 * 1024 * 1024));
    });

    test('kMetersPerDegreeLat is the standard ~111 km value', () {
      // Earth circumference / 360 ≈ 111 320 m at the equator (parent uses 111 320.0)
      expect(kMetersPerDegreeLat, closeTo(111320, 100));
    });

    test('kEarthRadiusMeters is ~6.371 million metres', () {
      expect(kEarthRadiusMeters, closeTo(6371000, 1000));
    });
  });
}
