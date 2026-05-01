// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

/// FOG-07 — single-MapCamera-snapshot invariant (KEYSTONE).
///
/// Wave 0 contract: the assertion is that across one FogLayer build, the
/// number of `MapCamera.of(context)` calls is EXACTLY 1, AND the painter's
/// internal `camera` field is `identical()` to the one read in build.
///
/// This is the single most important Phase 3 unit test — it directly defends
/// against the BUG-014 family of bugs where the SDF rect, the clip path, and
/// the shader uniforms each read a slightly-different MapCamera, producing
/// the slide-then-snap fog artefact that Phase 3 sets out to disprove.
///
/// The test seam (a recording wrapper around `MapCamera.of` or a
/// constructor-injected camera fake that records access) is specified in
/// Plan 03-05. Skipped here because the no-op stub does not yet read the
/// camera at all.
void main() {
  testWidgets('FogLayer reads MapCamera.of(context) exactly once per build; downstream consumers receive the SAME instance '
      '[skipped — Plan 03-05 introduces the camera-access counter seam (FOG-07 keystone)]', (tester) async {
    // Plan 03-05 must expose a test seam: either (a) a recording wrapper
    // around `MapCamera.of` (call-counter), or (b) a constructor-injected
    // camera fake that records access. The assertion: across one build,
    // the count is exactly 1 AND the painter's `camera` field is
    // `identical()` to the one read in build.
    final accessCounter = _CameraAccessCounter();
    // ... mount FogLayer with the counter inherited-widget seam ...
    expect(accessCounter.count, 1, reason: 'FOG-07: exactly one MapCamera.of(context) call per build');
  }, skip: true);
}

class _CameraAccessCounter {
  int count = 0;
}
