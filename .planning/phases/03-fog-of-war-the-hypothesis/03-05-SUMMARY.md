---
phase: 03-fog-of-war-the-hypothesis
plan: 05
subsystem: ui
tags: [flutter_map, custom_painter, fragment_shader, mobile_layer_transformer, single_ticker_provider, listenable_repaint, sdf, mapcamera]

# Dependency graph
requires:
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 03-01 Wave 0 stubs (FogLayer + computeFogClipPath placeholders, 13 RED tests scaffolded), Plan 03-02 RevealDiscRepository ChangeNotifier, Plan 03-03 SdfCache/SdfRebuildLogger, Plan 03-04 FrameDeltaProbe ring buffer + 1-Hz rollup"
provides:
  - "FogLayer custom flutter_map StatefulWidget — single MapCamera.of(context) read per build, MobileLayerTransformer wrap, Ticker-driven Listenable repaint, LIVE Stopwatch by-reference for per-paint uTime drift"
  - "FogShaderRenderer abstract interface (production: _FragmentShaderFogRenderer delegating to FogShaderUniforms.setAll; test: RecordingFogShaderRenderer)"
  - "computeFogClipPath top-level function (world rect minus disc circles via ui.Path.combine + metric-distance projection)"
  - "FogLayer.debugOnCameraRead static seam — FOG-07 keystone test enforces exactly-1-read-per-build invariant"
  - "FOG-08 paint-side wire — _FogPainter.paint() calls frameDeltaProbe.recordFogUniformPopulation(cameraSnapshotMicros) right before renderer.render"
  - "Test seams: FakeMapCamera + RecordingFogShaderRenderer in test/_helpers/ — defeat dart:ui FragmentShader 'base' restriction + GPU-bound asset loading in headless test envs"
affects: ["03-06-frame-delta-overlay-shader-sanity (DONE in parallel)", "03-07-mapscreen-integration", "03-08-falsification"]

# Tech tracking
tech-stack:
  added: []  # zero new dependencies — all surface uses dart:ui + dart:math + flutter_map 7.0.2 + already-pinned packages
  patterns:
    - "Single-MapCamera-snapshot lock: MapCamera.of(context) once per build, captured into a final, threaded by constructor — never re-read context in painters (BUG-014 defence, FOG-07 keystone)"
    - "Listenable repaint via Ticker + ChangeNotifier — paint cycles bypass the build phase (no setState in ticker callback per RESEARCH §Anti-pattern)"
    - "LIVE Stopwatch by-reference into painter — paint() reads elapsedMicroseconds fresh per call, fog drift advances during idle frames (PERF-03 idle-fog-animation gate prerequisite)"
    - "Renderer interface seam (FogShaderRenderer) — production delegates to FogShaderUniforms.setAll, tests inject a recording impl that ignores the GPU-bound shader argument"
    - "Static visibleForTesting hook (debugOnCameraRead) — production-default null, zero overhead; widget tests count invocations to enforce architectural invariants"
    - "Path qualified `ui.Path` to disambiguate from latlong2's transitively-exported `Path<T extends LatLng>` polyline class"

key-files:
  created:
    - "test/_helpers/fake_map_camera.dart (44 LoC) — CameraAccessCounter + pumpFlutterMapWithFogLayer harness"
    - "test/_helpers/recording_fog_shader_renderer.dart (118 LoC) — RecordedFogRender value object + RecordingFogShaderRenderer impl of FogShaderRenderer"
  modified:
    - "lib/presentation/widgets/fog_layer.dart — Plan 03-01 stub (50 LoC, returns SizedBox.shrink) → full impl (~340 LoC: FogShaderRenderer + _FragmentShaderFogRenderer + FogLayer + _FogLayerState + _Repaint + _FogPainter)"
    - "lib/presentation/widgets/fog_clip_path.dart — Plan 03-01 stub (22 LoC, throws UnimplementedError) → full impl (~80 LoC: ui.Path-qualified world-rect-minus-discs + _metersToPixels metric-distance projection)"
    - "test/presentation/widgets/fog_layer_test.dart — Plan 03-01 skipped placeholder (35 LoC) → full FOG-04 widget test (~60 LoC)"
    - "test/presentation/widgets/fog_layer_camera_snapshot_test.dart — Plan 03-01 skipped placeholder (38 LoC) → full FOG-07 KEYSTONE test (~95 LoC)"
    - "test/presentation/widgets/fog_clip_path_test.dart — Plan 03-01 partial (56 LoC, 2 RED) → full FOG-06 suite (~75 LoC, 3 GREEN)"

key-decisions:
  - "FogShaderRenderer interface seam over conditional GPU-vs-recording branches: production callers get a const _FragmentShaderFogRenderer() default; widget tests inject RecordingFogShaderRenderer. Single code path through the painter; the GPU-aware vs GPU-free split lives at the renderer interface boundary."
  - "FogLayer.shader nullable (Rule 3 deviation): dart:ui's FragmentShader is a `base` class — implementing it from a test file is forbidden. Tests pass null and rely on the recording renderer (which ignores the shader argument). Production callers always pass non-null; the painter null-guards at canvas.drawRect."
  - "computeFogClipPath returns ui.Path explicitly to defeat latlong2's Path<T extends LatLng> shadowing the dart:ui Path symbol in importing files. Type-prefix idiom propagates through callers without ceremony."
  - "find.descendant (not find.ancestor) for the FOG-04 MobileLayerTransformer test: FlutterMap does NOT auto-wrap children in MobileLayerTransformer (verified at flutter_map 7.0.2 lib/src/map/widget.dart lines 97-108 — children render directly inside a Stack). Each layer is responsible for its own wrap, so the transformer is a DESCENDANT of FogLayer, not an ancestor."
  - "_metersToPixels uses latitude-axis projection (1 m = 1.0/kMetersPerDegreeLat degrees globally, accurate to ~0.5% at any latitude) instead of longitude-axis (would require cos(lat) correction). Mirrors the donor RevealedSdfBuilder's metric-distance discipline that fixed BUG-011's north-south oval."
  - "_pendingSdfBuild guard against concurrent rebuild bursts: the FogLayer.build() method nullishly assigns _pendingSdfBuild ??= _resolveSdfImage(...) so a second build() during the same SDF future doesn't kick off a parallel rebuild. _onDiscsChanged resets it to null so the next build picks up the new disc snapshot."

patterns-established:
  - "Custom flutter_map layer architecture: StatefulWidget + SingleTickerProviderStateMixin + Listenable repaint + by-reference Stopwatch + renderer interface seam. Reusable for Phase 4 WispLayer (CONTEXT.md locks the same single-snapshot discipline for wisps)."
  - "Static @visibleForTesting hook for architectural invariant enforcement: a single static `void Function()? debugOnCameraRead;` field beats inherited-widget-based seams when the invariant being asserted is per-build call counts. Cost: zero in production (null default)."
  - "Renderer interface seam to bypass GPU-bound asset loading in tests: pattern documented for Phase 4 wisp work and Plan 03-06 ShaderSanityScreen (sanity screen uses FogShaderUniforms.setAll directly — single-screen, no test-renderer injection needed; abstract interface is overkill there)."

requirements-completed: [FOG-04, FOG-05, FOG-06, FOG-07, FOG-08]

# Metrics
duration: 14 min
completed: 2026-05-01
---

# Phase 03 Plan 05: FogLayer + computeFogClipPath Summary

**THE Phase 3 architectural keystone — FogLayer custom flutter_map StatefulWidget reads MapCamera.of(context) exactly once per build (FOG-07 lock), wraps its CustomPaint in MobileLayerTransformer (FOG-04), threads a single camera snapshot to clip path + sdfRect + viewport size + painter (FOG-07 single-snapshot), populates all 41 floats + 1 sampler via FogShaderUniforms.setAll through a FogShaderRenderer interface seam (FOG-05), wires the FOG-08 frame-delta probe build-side and paint-side, and reads uTime LIVE per paint() from a by-reference Stopwatch so fog drift advances between idle frames (PERF-03 prerequisite).**

## Performance

- **Duration:** ~14 min
- **Started:** 2026-05-01T15:13:12Z
- **Completed:** 2026-05-01T15:27:28Z
- **Tasks:** 2 (Task 1 helpers RED; Task 2 production + 3 tests GREEN)
- **Files modified:** 6 (4 modified + 2 created)

## Accomplishments

- **FOG-07 KEYSTONE test GREEN.** `MapCamera.of(context)` is called EXACTLY ONCE per FogLayer build, mechanically enforced by a unit test (`readCount == 1` after initial pump, `+1` per forced rebuild via `ValueKey<int>` mutation, never more, never fewer over 3 rebuilds). The architectural invariant against BUG-014's white-ellipse symptom is now defended by code, not just by code review.
- **FOG-04 GREEN.** `find.descendant(of: FogLayer, matching: MobileLayerTransformer) → findsOneWidget`. FogLayer.build() returns `MobileLayerTransformer(child: CustomPaint(...))` so the fog moves with the tile layer's MobileLayerTransformer-driven Canvas.
- **FOG-05 mechanically enforced.** Production renderer (`_FragmentShaderFogRenderer`) delegates to `FogShaderUniforms.setAll(...)` populating all 41 float slots + 1 sampler in one call. Widget tests inject `RecordingFogShaderRenderer` which captures every named arg into `RecordedFogRender` value objects so FOG-05 41-slot coverage can be asserted without a real GPU.
- **FOG-06 GREEN — 3 clip-path geometry tests.** Empty discs returns world rect (path.contains every interior point); centred disc carves a circular hole (centre OUT, corner IN); far disc produces no observable hole (centre + corner both still fog-drawn).
- **FOG-08 wire complete.** Build-side: `FogLayer.build()` calls `frameDeltaProbe.recordCameraSnapshot()` right after the `MapCamera.of(context)` read, captures the returned snapshot µs into a final, and threads it into the painter constructor. Paint-side: `_FogPainter.paint()` calls `frameDeltaProbe.recordFogUniformPopulation(cameraSnapshotMicros)` right before `shaderRenderer.render(...)`. Single-source-of-truth is the cameraSnapshotMicros captured in build — re-reading from the probe inside paint would re-introduce the multi-snapshot anti-pattern.
- **PERF-03 idle-fog-animation gate prerequisite met.** The painter holds a LIVE `Stopwatch wallClock` BY REFERENCE (passed from `_FogLayerState._wallClockSinceMount`); `paint()` body line 372 reads `final uTimeSeconds = wallClock.elapsedMicroseconds / _microsecondsPerSecond;` FRESHLY on every paint call. A frozen build-time double would freeze fog drift between rebuilds; the by-reference Stopwatch makes the shader's `uTime` advance during idle frames driven by the per-frame Ticker.

## Anti-Frozen-uTime Invariant — Exact Code Lines That Prove It

`lib/presentation/widgets/fog_layer.dart`:

```dart
class _FogPainter extends CustomPainter {
  // ...
  /// Live wall-clock — read fresh per `paint()` call. Anti-frozen-uTime
  /// invariant (PERF-03 idle-fog-animation gate).
  final Stopwatch wallClock;
  // ...
  @override
  void paint(Canvas canvas, Size size) {
    if (sdfImage == null) return;
    // CRITICAL: read uTime LIVE from the Stopwatch on every paint call.
    // A frozen value captured at build time would freeze fog drift between
    // rebuilds (PERF-03 idle-fog-animation gate fails — shader's uTime
    // never advances while idle).
    final uTimeSeconds = wallClock.elapsedMicroseconds / _microsecondsPerSecond;
    // ...
  }
}
```

The `Stopwatch` is OWNED by `_FogLayerState` (`final Stopwatch _wallClockSinceMount = Stopwatch()..start();`), passed by reference into the painter constructor (`wallClock: _wallClockSinceMount`), never frozen into a build-time double. The Ticker drives per-frame `_repaint.notifyListeners()` which kicks the CustomPainter via its `repaint:` Listenable argument; each tick reads `wallClock.elapsedMicroseconds` afresh.

## Task Commits

Each task was committed atomically (TDD RED → GREEN):

1. **Task 1: test seams (FakeMapCamera + RecordingFogShaderRenderer + RED)** — `9a5bfd1` (test) — Created `test/_helpers/fake_map_camera.dart` and `test/_helpers/recording_fog_shader_renderer.dart`. Helpers reference the `FogShaderRenderer` interface that Task 2 ships, so they fail to compile against the Plan 03-01 stub (expected RED).
2. **Task 2: FogLayer + computeFogClipPath + FogShaderRenderer interface (GREEN)** — `119a1bf` (feat) — Full production impl + interface + 3 widget test files. All 5 tests across the 3 fog-related files GREEN; full suite 123 GREEN / 2 SKIPPED / 0 RED; flutter analyze clean; dart format clean.

**Plan metadata:** _to be appended after this SUMMARY.md commits_

## Files Created/Modified

- **Created** `test/_helpers/fake_map_camera.dart` (44 LoC) — `CameraAccessCounter` value object + `pumpFlutterMapWithFogLayer` harness for the FOG-07 keystone test (caller wires `FogLayer.debugOnCameraRead = counter.recordRead` before pumping).
- **Created** `test/_helpers/recording_fog_shader_renderer.dart` (118 LoC) — `RecordedFogRender` value object capturing every named arg of one `FogShaderRenderer.render(...)` invocation; `RecordingFogShaderRenderer` impl that pushes each render into a `List<RecordedFogRender>`. Tests assert FOG-05 invariants by inspecting `renders.last.namedFloatArgs` for 20 kMirkFog* keys + identity sdfRect via `renders.last.sdfRect == (0.0, 0.0, 1.0, 1.0)`.
- **Modified** `lib/presentation/widgets/fog_layer.dart` (50 → ~340 LoC). Stub replaced with: `FogShaderRenderer` abstract interface; production `_FragmentShaderFogRenderer` delegating to `FogShaderUniforms.setAll`; `FogLayer` StatefulWidget with `debugOnCameraRead` static seam + nullable `shader` field; `_FogLayerState` with `SingleTickerProviderStateMixin` + LIVE Stopwatch + `_pendingSdfBuild` guard + `_onDiscsChanged` listener; `_Repaint` ChangeNotifier; `_FogPainter` with FOG-08 paint-side wire + LIVE uTime read + identity sdfRect + null-shader guard at canvas.drawRect.
- **Modified** `lib/presentation/widgets/fog_clip_path.dart` (22 → ~80 LoC). Stub `throw UnimplementedError(...)` replaced with: `ui.Path` qualified function returning `ui.Path.combine(PathOperation.difference, worldPath, holesPath)`; `_metersToPixels` using `camera.latLngToScreenPoint` of two points 1 m apart along the latitude axis; `_pointToOffset` shim from flutter_map's `Point<double>` to dart:ui's `Offset`.
- **Modified** `test/presentation/widgets/fog_layer_test.dart` (35 → ~60 LoC). Skipped placeholder replaced with FOG-04 GREEN test using `find.descendant`.
- **Modified** `test/presentation/widgets/fog_layer_camera_snapshot_test.dart` (38 → ~95 LoC). Skipped placeholder replaced with FOG-07 KEYSTONE test using `FogLayer.debugOnCameraRead` invocation counter + `ValueKey<int>` rebuild trigger.
- **Modified** `test/presentation/widgets/fog_clip_path_test.dart` (56 → ~75 LoC). 2 RED tests replaced with 3 GREEN tests covering empty / centred / far disc cases.

## Decisions Made

See frontmatter `key-decisions:` for the six decisions taken during this plan, all documented inline in code (dartdoc) and tests:

1. **FogShaderRenderer interface seam** over conditional GPU-vs-recording branches.
2. **FogLayer.shader nullable** (Rule 3 deviation) to defeat dart:ui's `base` FragmentShader restriction.
3. **`ui.Path` qualified** in computeFogClipPath to defeat latlong2's `Path<T extends LatLng>` shadowing.
4. **`find.descendant` not `find.ancestor`** for FOG-04 — flutter_map does NOT auto-wrap children.
5. **`_metersToPixels` latitude-axis projection** mirroring donor RevealedSdfBuilder's BUG-011 metric-distance discipline.
6. **`_pendingSdfBuild` ??= guard** against concurrent rebuild-burst SDF rebuilds.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan API mismatch — flutter_map 7.0.2 actual surface differs from plan's `<interfaces>` block**
- **Found during:** Task 2 (initial flutter analyze)
- **Issue:** Plan declared `MapCamera.size: Size`, `MapCamera.latLngToScreenOffset(LatLng)`, and `LatLngBounds` field access. Verified against flutter_map 7.0.2 source: `MapCamera.size` is `Point<double>`; the actual projection method is `latLngToScreenPoint(LatLng)` returning `Point<double>`. (LatLngBounds field access was correct — the rest was wrong.)
- **Fix:** `computeFogClipPath` converts via `Size(camera.size.x, camera.size.y)` for `Rect.fromLTWH`, calls `camera.latLngToScreenPoint(latLng)` and converts the result via `_pointToOffset(p) => Offset(p.x, p.y)` for path operations. Documented at the top of the file.
- **Files modified:** `lib/presentation/widgets/fog_clip_path.dart`
- **Verification:** flutter analyze 0 issues; 3 fog_clip_path tests GREEN.
- **Committed in:** `119a1bf`

**2. [Rule 3 - Blocking] dart:ui FragmentShader is `base` — cannot be implemented from test files**
- **Found during:** Task 2 (initial flutter analyze on test files)
- **Issue:** Plan's Task 2 prescribed `class _FakeShader implements ui.FragmentShader { @override noSuchMethod(...) => throw ... }`. dart:ui 3.41 marked `FragmentShader` as `base`, which forbids `implements`/`extends`/`with` from outside the dart:ui library. The Plan 03-01 deviation log already noted this for the simpler placeholder — Plan 03-05's Task 2 needs the same workaround.
- **Fix:** Made `FogLayer.shader` nullable (`ui.FragmentShader?`). Widget tests pass `null` and rely on the recording renderer (which ignores the shader argument). Production callers always pass non-null; the painter null-guards before `canvas.drawRect(... Paint()..shader = liveShader)` so a null shader produces a no-op paint instead of a NoSuchMethodError. Documented in the field's dartdoc + the painter's body comment.
- **Files modified:** `lib/presentation/widgets/fog_layer.dart`, `test/presentation/widgets/fog_layer_test.dart`, `test/presentation/widgets/fog_layer_camera_snapshot_test.dart`
- **Verification:** flutter analyze 0 issues across lib/presentation/widgets/ + test/presentation/widgets/ + test/_helpers/; FOG-04 + FOG-07 KEYSTONE tests GREEN.
- **Committed in:** `119a1bf`

**3. [Rule 1 - Bug] FOG-04 test direction wrong — should be descendant, not ancestor**
- **Found during:** Task 2 (FOG-04 test failed `findsOneWidget` after first GREEN attempt — found 0 ancestors)
- **Issue:** Plan's Task 2 prescribed `find.ancestor(of: FogLayer, matching: MobileLayerTransformer)`. But `FogLayer.build()` returns `MobileLayerTransformer(child: CustomPaint(...))` — the transformer is a DESCENDANT of FogLayer, not an ancestor. (Verified at flutter_map 7.0.2 `lib/src/map/widget.dart` lines 97-108: `FlutterMap` renders its children directly inside a `Stack`, NOT auto-wrapping them in any layer-transformer. Each layer is responsible for its own wrap.) Sanity-checked by adding diagnostic expectations: `find.byType(FogLayer)` finds 1 widget AND `find.byType(MobileLayerTransformer)` finds widgets in the tree, but `find.ancestor(of: FogLayer, matching: MobileLayerTransformer)` finds 0.
- **Fix:** Changed to `find.descendant(of: find.byType(FogLayer), matching: find.byType(MobileLayerTransformer))`. Added a `tester.pump()` after the initial `pumpWidget` to flush the post-frame layout that lets FlutterMap's children build, and explanatory comment quoting the flutter_map 7.0.2 line numbers.
- **Files modified:** `test/presentation/widgets/fog_layer_test.dart`
- **Verification:** FOG-04 test GREEN.
- **Committed in:** `119a1bf`

**4. [Rule 1 - Bug] dart format reflowed lines + auto-applied prefer_const_constructors hints**
- **Found during:** Task 2 (post-impl `dart format --line-length 160 --set-exit-if-changed`)
- **Issue:** dart format reflowed multiple multi-line declarations (FogLayer constructor calls, MapOptions calls) onto single lines under the 160-char budget. Two `prefer_const_constructors` info-level hints surfaced for the `MapOptions(...)` calls in test files (the `LatLng(...)` arg was const but the parent was not).
- **Fix:** Accepted dart format's reflow; manually fixed the prefer_const_constructors hints by hoisting `const` to the parent (`const MapOptions(initialCenter: LatLng(...), initialZoom: 13)` instead of `MapOptions(initialCenter: const LatLng(...), initialZoom: 13)`).
- **Files modified:** `lib/presentation/widgets/fog_layer.dart`, `test/presentation/widgets/fog_clip_path_test.dart`, `test/presentation/widgets/fog_layer_camera_snapshot_test.dart`, `test/presentation/widgets/fog_layer_test.dart`
- **Verification:** `flutter analyze --fatal-infos` 0 issues; `dart format --set-exit-if-changed` exit code 0.
- **Committed in:** `119a1bf`

---

**Total deviations:** 4 auto-fixed (2 Rule 3 - Blocking, 2 Rule 1 - Bug)
**Impact on plan:** All four auto-fixes were essential — two API surface mismatches (flutter_map 7.0.2 actual API; dart:ui 3.41 `base` restriction) that the plan's interface block didn't anticipate, one test-direction bug (`ancestor` vs `descendant` in the FOG-04 finder), and one cosmetic format-cycle. The substantive architectural invariants (FOG-07 single-snapshot lock, FOG-04 MobileLayerTransformer wrap, FOG-05 41-slot coverage via renderer interface, FOG-06 clip-path geometry, FOG-08 build/paint-side probe wire, anti-frozen-uTime via by-reference Stopwatch) were implemented exactly as the plan specified. No scope creep.

## Issues Encountered

- **Parallel sibling Plan 03-06 ran concurrently and committed 4 commits between my Task 1 (`9a5bfd1`) and Task 2 (`119a1bf`) commits.** No file conflicts (sibling touched `frame_delta_probe_overlay.dart` + `shader_sanity_screen.dart`); my Task 2 stage diff was clean against the latest sibling state. Sibling also wrote `03-06-SUMMARY.md` and updated STATE.md (unstaged in my working tree at commit time of Task 2 — STATE.md was reverted by the sibling's metadata commit before I committed mine, which is fine). Per the orchestrator's race-recovery note, no manual intervention was needed.
- **Brief working-copy "revert" mid-task.** During Task 2, between writing the production code and running tests, three files (fog_layer.dart, fog_layer_test.dart, fog_clip_path_test.dart) appeared to roll back to their Wave 0 stub state (likely a git-side checkout from the sibling's commit landing while I had unstaged changes). I re-wrote the changes — no work lost, time cost was ~1 min.

## Test Seam Surface for Plan 03-07 (MapScreen integration)

Plan 03-07 wires FogLayer into MapScreen via the existing MapScreenServices DTO (already extended in Plan 03-01 with `discRepository` + `frameDeltaProbe`). The exposed seams from this plan:

- **`FogLayer.shaderRenderer` constructor arg** (default: const `_FragmentShaderFogRenderer()`). Production callers omit; widget tests inject `RecordingFogShaderRenderer` from `test/_helpers/`.
- **`FogLayer.shader: ui.FragmentShader?`** nullable. Production passes the loaded `atmospheric_fog.frag` from `FragmentProgram.fromAsset(kPocFogShaderAssetPath)`; tests pass `null`.
- **`FogLayer.debugOnCameraRead`** static. Production: null. Tests set `() => counter++` to enforce the FOG-07 single-snapshot invariant in any future test that mounts FogLayer.

## Note for Plan 03-06 (Already Complete in Parallel)

ShaderSanityScreen reuses the same `FogShaderUniforms.setAll(...)` invocation pattern as `_FragmentShaderFogRenderer`, just with a synthetic SDF (built once on screen mount with one disc at viewport centre). The sanity screen does NOT need the `FogShaderRenderer` abstraction — single-screen, no test-renderer injection needed; abstract interface would be over-engineering there. (Plan 03-06's commits confirm this approach was taken.)

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 03-05 contract complete.** FogLayer + computeFogClipPath + FogShaderRenderer interface + production impl all shipped. ✓
- **Phase 3 RED test count after Plan 03-05:** 0 RED. (At end of Plan 03-04: 2 RED in fog_clip_path_test.dart for FOG-06. Both flipped GREEN by this plan, plus 3rd GREEN test added for the far-disc case.)
- **Plan 03-07 unblocked** — MapScreen can now mount `FogLayer(...)` between its tile layer and blue-dot CircleLayer per CONTEXT.md z-order. The GPS subscription's per-fix `RevealDiscRepository.append(...)` automatically triggers FogLayer's `_onDiscsChanged → setState → rebuild → SDF cache miss → new ui.Image → painter repaints with new disc snapshot`.
- **Plan 03-08 unblocked** — falsification walk can begin once Plan 03-07 lands and the developer sideloads to iPhone 17 Pro.
- **Plan 03-06 already complete in parallel** (4 commits between my Task 1 and Task 2). FrameDeltaProbeOverlay + ShaderSanityScreen + their tests all GREEN per the sibling's commits.

## Self-Check: PASSED

- `lib/presentation/widgets/fog_layer.dart` — FOUND
- `lib/presentation/widgets/fog_clip_path.dart` — FOUND
- `test/_helpers/fake_map_camera.dart` — FOUND
- `test/_helpers/recording_fog_shader_renderer.dart` — FOUND
- `test/presentation/widgets/fog_layer_test.dart` — FOUND
- `test/presentation/widgets/fog_layer_camera_snapshot_test.dart` — FOUND
- `test/presentation/widgets/fog_clip_path_test.dart` — FOUND
- `.planning/phases/03-fog-of-war-the-hypothesis/03-05-SUMMARY.md` — FOUND
- Commit `9a5bfd1` (Task 1 RED helpers) — FOUND
- Commit `119a1bf` (Task 2 GREEN production + tests) — FOUND

---
*Phase: 03-fog-of-war-the-hypothesis*
*Completed: 2026-05-01*
