// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/shader/digit_atlas_builder.dart';

/// Plan 03.1-07 — DigitAtlasBuilder unit tests.
///
/// Asserts the rasterized atlas geometry + idempotent process-cache
/// behaviour. The atlas is consumed by the debug-spiral shader as
/// sampler 1; tests do NOT exercise the shader path (that requires a
/// real Impeller backend) — they verify the `ui.Image` returned matches
/// the documented dimensions + caches across calls.
///
/// `ui.PictureRecorder().endRecording().toImage()` requires the Flutter
/// runtime's image microtask plumbing, so each test wraps its body in
/// `tester.runAsync(...)` per the convention used in Plan 02-05 +
/// Plan 03-06.
void main() {
  testWidgets('atlas getter returns non-null ui.Image with non-zero dimensions', (tester) async {
    DigitAtlasBuilder.resetCacheForTesting();
    addTearDown(DigitAtlasBuilder.resetCacheForTesting);

    final image = await tester.runAsync<ui.Image>(() async => DigitAtlasBuilder.atlas);
    expect(image, isNotNull);
    expect(image!.width, greaterThan(0));
    expect(image.height, greaterThan(0));
  });

  testWidgets('atlas getter is idempotent — second call returns the same ui.Image instance (process-cached)', (tester) async {
    DigitAtlasBuilder.resetCacheForTesting();
    addTearDown(DigitAtlasBuilder.resetCacheForTesting);

    final first = await tester.runAsync<ui.Image>(() async => DigitAtlasBuilder.atlas);
    final second = await tester.runAsync<ui.Image>(() async => DigitAtlasBuilder.atlas);
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(
      identical(first, second),
      isTrue,
      reason:
          'Plan 03.1-07: DigitAtlasBuilder.atlas must process-cache the rasterized image; subsequent toggles ON in /sanity must be instant (no re-rasterization).',
    );
  });

  testWidgets('atlas dimensions match documented geometry (640x640 for 10x10 grid of 64-px cells)', (tester) async {
    DigitAtlasBuilder.resetCacheForTesting();
    addTearDown(DigitAtlasBuilder.resetCacheForTesting);

    final image = await tester.runAsync<ui.Image>(() async => DigitAtlasBuilder.atlas);
    expect(image, isNotNull);
    expect(image!.width, equals(DigitAtlasBuilder.atlasPx.toInt()));
    expect(image.height, equals(DigitAtlasBuilder.atlasPx.toInt()));
    expect(image.width, equals(640), reason: 'Plan 03.1-07: atlas geometry contract — 10 cols × 64 px = 640 px wide.');
    expect(image.height, equals(640), reason: 'Plan 03.1-07: atlas geometry contract — 10 rows × 64 px = 640 px tall.');
  });
}
