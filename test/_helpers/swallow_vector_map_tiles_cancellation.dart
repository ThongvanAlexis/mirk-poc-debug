// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// ignore_for_file: depend_on_referenced_packages — `executor_lib` is a
// transitive of `vector_map_tiles`; matching its public CancellationException
// type is the whole point of this helper. Importing it here is intentional
// and matches the pattern already used in map_screen_test.dart for
// `vector_map_tiles` and `path_provider_platform_interface`.

import 'package:executor_lib/executor_lib.dart' show CancellationException;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-scaffolding filter that drops the `CancellationException` thrown by
/// `vector_map_tiles`'s `TileLoader._renderTile` while a `VectorTileLayer`
/// unmounts mid-render.
///
/// Why this exists:
/// - `vector_map_tiles 8.0.0` legitimately cancels in-flight tile renders when
///   the layer's [State.dispose] runs. The cancellation is reported through
///   Flutter's image-resource-service error channel (i.e.
///   `FlutterError.reportError`).
/// - On Linux runners, scheduler timing pushes the cancellation past the test
///   body's return — the runner attributes it to the just-completed test as a
///   "Multiple exceptions detected … failed after test completion" failure.
/// - On Windows + macOS local runs the same exception lands inside the body
///   where the test runner sometimes coalesces it harmlessly, but is also
///   intermittently fatal to the test.
///
/// Why this MUST be called from inside each test body (not from `setUp`):
/// `TestWidgetsFlutterBinding._runTest` overwrites `FlutterError.onError`
/// AFTER `setUp` callbacks have run, so a `setUp`-installed filter is
/// clobbered for the test body's lifetime. Calling this helper at the top of
/// the test body installs the filter after the binding's handler is in place,
/// and registers an `addTearDown` to restore it before the binding's
/// `postTest` does its own restore.
///
/// Usage:
/// ```dart
/// testWidgets('VectorTileLayer wired correctly', (tester) async {
///   installVectorMapTilesCancellationFilterForBody();
///   await tester.pumpWidget(...);
///   // ... assertions
/// });
/// ```
///
/// Scope discipline: this helper does NOT broaden the swallow beyond
/// `CancellationException`. A regression that throws any other exception
/// during teardown still fails the test.
void installVectorMapTilesCancellationFilterForBody() {
  final FlutterExceptionHandler? priorOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception is CancellationException) {
      // Drop on the floor — the cancellation is expected during dispose
      // of the vector_map_tiles tile layer; see helper docstring.
      return;
    }
    priorOnError?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = priorOnError;
  });
}
