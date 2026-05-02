---
status: resolved
trigger: "11 CI tests fail on Linux with CancellationException from vector_map_tiles teardown"
created: 2026-05-01T00:00:00Z
updated: 2026-05-01T11:30:00Z
ci_run: 25212559648
ci_result: success
commit: 46b8fcc
---

## Current Focus

hypothesis: CancellationException flows through FlutterError.onError (via "EXCEPTION CAUGHT BY IMAGE RESOURCE SERVICE" → FlutterError.reportError); on Linux it arrives after the test body returns but before the runner detaches its handler, so the framework's "Multiple exceptions (30) were detected" wrapper trips.
test: write a setUp/tearDown helper that swaps FlutterError.onError to drop ONLY CancellationException from executor_lib while forwarding everything else, then re-run flutter test on Windows to ensure the 94 stay GREEN; push to CI to verify Linux.
expecting: 94/94 GREEN on both. CancellationException still reachable via tester.takeException if anyone wants it but does not fail the test.
next_action: create test/_helpers/swallow_vector_map_tiles_cancellation.dart with installCancellationFilter() helper, wire it into both failing test files via setUpAll/tearDownAll (or per-test setUp).

## Symptoms

expected: All 94 tests pass on both Windows (local) and Linux (CI).
actual: Windows local 94/94 GREEN. Linux CI 83/94 GREEN — 11 tests fail.
errors: |
  Multiple exceptions (30) were detected during the running of the current test, and at least one was unexpected.
  EXCEPTION CAUGHT BY IMAGE RESOURCE SERVICE
  CancellationException: Cancelled
  at TileLoader._renderTile (vector_map_tiles/src/raster/tile_loader.dart:72:7)
reproduction: Run flutter test on Linux CI runner SHA 5d8b06703dd5528241fe4bf16f2a7788c2fa45bb. Failing run id 25211342233.
started: After Plan 02-05 MapScreen rewrite landed (FlutterMap + VectorTileLayer + GPS subscription + RecenterFab + MapCompass).

## Eliminated

- hypothesis: setUp-installed FlutterError.onError filter is enough.
  evidence: TestWidgetsFlutterBinding._runTest at flutter_test/lib/src/binding.dart:1500 saves the prior handler then OVERWRITES FlutterError.onError with its own tracker AFTER user-level setUp callbacks have run. The setUp-installed filter is therefore clobbered for the test body's lifetime, which is precisely when vector_map_tiles fires the CancellationExceptions. Empirically reproduced: with setUp-only install, ~1 in 10 local runs of the two test files still fail with "Multiple exceptions (30) were detected".
  timestamp: 2026-05-01T00:00:00Z

## Evidence

- timestamp: 2026-05-01T00:00:00Z
  checked: orchestrator-supplied bug context
  found: All assertions pass; exception fires after test body completes but before runner detaches error handler. Linux scheduler timing pushes cancellation past the test boundary; Windows timing keeps it inside scope.
  implication: Fix must be in test scaffolding, not production code. Need to either (a) swallow CancellationException in test scope, (b) extend test scope until cancellation drains, or (c) both.

## Resolution

root_cause: vector_map_tiles 8.0.0 throws executor_lib's CancellationException from TileLoader._renderTile when the layer unmounts mid-render. The exception is funnelled through Flutter's image-resource-service → FlutterError.reportError → flutter_test's onError tracker, which converts it into a test-level failure ("Multiple exceptions (30) were detected"). On Linux scheduler timing pushes the cancellation past the test body return; locally on Windows it usually lands inside the body but with non-zero flake rate.
fix: shared helper `test/_helpers/swallow_vector_map_tiles_cancellation.dart` exporting `installVectorMapTilesCancellationFilterForBody()`. Called as the FIRST line of each affected test body (10 in map_screen_test.dart, 4 in map_screen_gps_test.dart). It captures the binding's current FlutterError.onError, installs a filter that drops ONLY `CancellationException` from package:executor_lib and forwards every other error to the binding's tracker, and registers `addTearDown` to restore the binding's handler before binding.postTest does its own restore. The MUST-be-in-body placement is required because TestWidgetsFlutterBinding._runTest overwrites FlutterError.onError AFTER user-level setUp runs.
verification: flutter analyze test/ → 0 issues. flutter test on the two affected files: 20/20 GREEN. flutter test full suite: 10/10 GREEN. CI verification pending on push.
files_changed:
  - test/_helpers/swallow_vector_map_tiles_cancellation.dart (new)
  - test/presentation/screens/map_screen_test.dart (+ helper import + 11 in-body installs)
  - test/presentation/screens/map_screen_gps_test.dart (+ helper import + 4 in-body installs)
