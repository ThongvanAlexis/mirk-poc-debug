# Phase 3: Fog of War — THE HYPOTHESIS - Research

**Researched:** 2026-05-01
**Domain:** Flutter `flutter_map` 7.0.2 custom-layer integration · `dart:ui` `FragmentProgram` / `FragmentShader` · per-frame on-device performance instrumentation (FPS + camera-to-paint frame-delta probe) on iOS 18+ Impeller / iPhone 17 Pro (A19 Pro) at 120 Hz ProMotion
**Confidence:** HIGH on the Flutter / flutter_map APIs (Context7 + official docs cross-verified) · MEDIUM on the iPhone 17 Pro shader cost number (no measurement done yet — researcher's own work proves the number on-device during the planner-built shader-sanity screen + first iPhone walk; placeholder estimate documented from architectural reasoning)

## Summary

The phase is bounded by three pillars and each pillar's load-bearing surface already exists or has been pinned by Phase 1/2:

1. **Same-Canvas custom layer.** `flutter_map` 7.0.2 documents the exact pattern needed: a `StatelessWidget` (or `StatefulWidget` for the per-frame ticker the fog drift animation needs) returned as a child of `FlutterMap`, that calls `MapCamera.of(context)` ONCE in its `build()` method, then composes its painting with `MobileLayerTransformer` so the painter shares the tile layer's coordinate transform. `MapCamera.of(context)` is a `dependOnInheritedWidgetOfExactType` call — it auto-subscribes the layer to camera changes and rebuilds it on every camera tick. This delivers FOG-04 (custom layer in same Canvas) and FOG-07 (single MapCamera snapshot) by-construction when the widget is wired correctly.

2. **41-uniform shader rendering.** The shader, the SDF builder, and the `FogShaderUniforms.setAll()` slot-layout authority are already ported verbatim from MirkFall and present in `lib/`. The renderer just composes them: `await FragmentProgram.fromAsset('assets/shaders/atmospheric_fog.frag')` once at screen mount, hold the resulting program in a `late final`, call `program.fragmentShader()` once and reuse the same `FragmentShader` instance across frames (per Flutter docs — reuse is `more efficient than creating new ones per frame`), call `FogShaderUniforms.setAll(...)` to populate all 41 floats and bind sampler 0 (the SDF `ui.Image`), call `canvas.clipPath(holePath)` and `canvas.drawRect(viewport, Paint()..shader = shader)`. Identity uSdfRect (`0, 0, 1, 1`) is non-negotiable per locked architecture (BUG-014 root cause in the parent project).

3. **Frame-delta + FPS probe.** `SchedulerBinding.instance.addTimingsCallback((List<FrameTiming>) {...})` is the supported, multi-listener-safe API for production frame timing capture. `FrameTiming` exposes `vsyncStart`, `buildStart`, `buildFinish`, `rasterStart`, `rasterFinish`, plus `totalSpan` (vsyncStart → rasterFinish) — that's the hardware-grounded "frame finished on-screen" timestamp the FOG-08 probe needs. The probe complements this with an in-paint `Stopwatch.elapsedMicroseconds` snapshot taken at the moment fog uniforms are populated; the delta `(fogUniformPopulationMicros − latestCameraUpdateMicros)` is what FOG-08 specifies. Both timestamp sources MUST be `Stopwatch.elapsedMicroseconds` (monotonic, immune to wall-clock NTP corrections during a 5-min walk).

**Primary recommendation:** Build `FogLayer` as a `StatefulWidget` whose `build()` reads `MapCamera.of(context)` exactly once into a local final `camera`, derives the `MirkViewportBbox` from `camera.visibleBounds`, builds (or cache-hits) the SDF, and wraps a `MobileLayerTransformer` → `RepaintBoundary`-FREE `CustomPaint` (with a `Listenable` repaint-on-tick driver for the fog drift `uTime` animation). All four downstream consumers — clip path, sdfRect, shader uniforms, viewport size — derive from that single `camera` value (FOG-07 lock). Use `addTimingsCallback` for the probe's per-frame `totalSpan` capture and tag each entry with the `(cameraUpdateMicros, fogPaintMicros)` pair recorded in the `CustomPainter.paint()` body via a `ValueNotifier<int>`-style cheap channel back to a singleton `FrameDeltaProbe`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### SDF rebuild policy
- **Trigger:** rebuild whenever `(disc list, viewport bbox, mean lat)` hash changes. The donor `RevealedSdfBuilder` docstring is the authoritative source — input-change-driven rebuild with hash-based caching.
- **During pan/zoom/rotate:** rebuild every frame. At POC disc counts (~5–50 discs over a 5-minute Melun walk), the cost is well under 1 ms (donor file's `~67 k pixel updates × disc-count` cost — the documented 16 ms bound applies to a 4-hour-session 1000-disc scenario, not POC scale).
- **During idle:** hash matches → reuse cached `ui.Image`, free.
- **On new GPS fix:** disc-list mutation → hash mismatches → rebuild.
- **Reading of FOG-03 ambiguity:** "rebuilt when the disc list changes" is incomplete wording — it states a sufficient condition for rebuild, not the only one. The donor docstring (`The renderer should rebuild it when EITHER changes`) is authoritative. Keep `uSdfRect = identity (0, 0, 1, 1)` per locked architecture.
- **Researcher must verify on iPhone 17 Pro:** measure actual rebuild ms at 50 discs / 256² SDF / typical viewport during Phase 3 research; document numbers in RESEARCH.md. If they exceed expectations and the falsification probe shows budget pressure, fall back to a 60 Hz cap on a 120 Hz device (default OFF; documented as a fallback knob).

#### Disc-list ownership
- **Defer to planner:** mirror the parent MirkFall `RevealDiscRepository` shape so the POC port-back is mechanical. Likely lands as a small `RevealDiscRepository` wired through `MapScreenServices` (constructor-injected, alongside the existing `pmtilesPath`, `positionStreamFactory`, `logger`). Planner reads parent code, adopts the surface verbatim where renderer-agnostic, documents adaptations.

#### FogLayer z-order
- **Default order:** tiles → FogLayer → BlueDot CircleLayer (planner discretion). The blue dot always sits at the user's GPS fix, and every fix spawns a 25 m reveal disc around that fix — so the dot is always inside a clear hole, regardless of z-order. No visual conflict; pick the cleanest order for the planner.
- **No `RepaintBoundary` around `FogLayer`** (locked from RESEARCH §Anti-patterns — would re-create BUG-014 inside Flutter).

#### SDF rebuild logging
- **Cadence:** 1-second rollup. Per-active-second emit one structured JSONL line via `Logger('infrastructure.mirk.sdf')` with: `discCount`, `intersectingDiscCount`, `rebuildCount`, `medianMs`, `p95Ms`, `maxMs`. Aligned with the frame-delta probe's persistence cadence so timelines line up post-walk.
- **No per-rebuild line** during sustained pan (would emit ~120 lines/sec on iPhone 17 Pro). Per-rebuild stats roll up into the per-second summary; raw outliers can still be reconstructed from the rollup's max field.
- **Idle seconds:** no log line (only emit on active rebuilding seconds).

#### Frame-delta probe — overlay UX
- **Placement:** top-right under MapCompass. Stack vertically with FpsCounterOverlay (top:8) → MapCompass (top:56) → FrameDeltaProbe overlay (top: ~104, right:8). Right-aligned HUD cluster.
- **Format:** three lines — `med {N} ms / p95 {N} ms / max {N} ms`.
- **Color-coding:** green / yellow / red against the falsification thresholds.
  - Median: green ≤16 ms, yellow ≤24 ms (50% over), red >24 ms.
  - p95: green ≤32 ms, yellow ≤48 ms, red >48 ms.
  - Max: green ≤48 ms, yellow ≤72 ms, red >72 ms.
- **Update cadence on overlay:** 1 Hz refresh (matches the per-second log rollup). Avoids per-frame UI churn.

#### Frame-delta probe — log persistence
- **Cadence:** 1-second rollup. One JSONL line per active second via `Logger('infrastructure.mirk.frame_delta')` with: `sampleCount`, `medianMs`, `p95Ms`, `maxMs` (and optionally `p99Ms` if cheap). Matches the SDF log cadence.
- **No per-frame raw lines** (~120 lines/sec on iPhone 17 Pro pan = 36k lines per 5-min walk).
- **Probe instrumentation point:** measure delta as `(timestamp of fog uniform population) − (timestamp of latest map camera update)` per FOG-08. Single source of truth for "camera update time" is the same `MapCamera` snapshot read once at the top of `FogLayer.build()` (FOG-07 lock).

#### Falsification document
- **Location:** `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md`. Lives alongside other Phase 3 artifacts.
- **Pre-walk content (written BEFORE the walk, committed BEFORE the iPhone build):**
  - Hypothesis statement (one paragraph) re-stating what "confirmed" / "denied" mean for the MirkFall migration.
  - **Criterion A** (frame-delta thresholds, quantitative from FOG-08 probe): median ≤16 ms, p95 ≤32 ms, max ≤48 ms across ≥10 combined gestures over a 5-min walk.
  - **Criterion B** (subjective visual lock from PERF-05): no fog slide-then-snap, no white-ellipse on fast pinch-zoom, no perceptible reveal-hole lag behind the blue dot, no inversion at any zoom.
  - **Criterion C explicitly DROPPED** per locked decisions (parent-FPS comparison removed from POC scope).
- **Walk plan section:** the doc's pre-walk section also re-states the walk shape from PERF-03/04.
- **Post-walk evidence:** manual paste — developer walks, returns, opens the shared log file from Mail, pastes the relevant frame-delta probe lines + SDF rebuild lines + FPS readings + screenshots into the doc, writes the subjective verdict by hand.
- **Verdict location:** appended at the end of the same `03-FALSIFICATION.md` doc.

#### Shader-sanity screen
- **Entry:** new AppBar action button on `/map` next to the existing share-logs button. Icon: `Icons.science` (planner's pick if a stronger candidate exists). Tap → navigate to `/sanity` (new GoRouter route).
- **Tooltip:** localized via `AppLocalizations` like the share button — French + English.
- **Hardcoded uniforms:** kMirkFog* constants from `lib/config/constants.dart` for all 41 floats. Sampler 0 (uSdf): synthetic SDF built in code on screen mount — one 80 m radius disc at the viewport center.
- **Pass criterion (subjective):** developer opens `/sanity`, confirms (a) fog renders with the documented atmospheric look, (b) a circular reveal hole appears centered on screen (proves SDF→shader path works), (c) no shader compile errors / no exceptions in the FileLogger output. Verbal "approved".
- **No golden-image diff / no automated frame-capture test** for Phase 3.
- **Lifecycle:** stays in the POC indefinitely.

#### Forward decisions for Phase 4 (locked here)
- **Wisp particle z-order:** wisps render ABOVE FogLayer.
- **`MapCamera` snapshot discipline carries over:** wisps must use the SAME single `MapCamera.of(context)` read that FogLayer uses, captured atomically per build.

### Claude's Discretion
- Exact icon glyph for the shader-sanity AppBar action (`Icons.science`, `Icons.bug_report`, `Icons.layers` etc.) — bias toward Material icons.
- Exact tooltip strings for the sanity button and probe overlay (French + English via `AppLocalizations`).
- Exact yellow-threshold mid-band cutoffs (50% over the green threshold is the working assumption).
- Exact JSONL field names for the SDF rollup and probe rollup logs.
- Whether to add a tiny "rebuilds: N" counter line to the probe overlay if it adds clarity at no cost.
- Frame-delta probe instrumentation timestamp source (`Stopwatch.elapsedMicroseconds` vs `DateTime.now().microsecondsSinceEpoch` vs `clock_gettime` via FFI) — researcher picks. **Researcher pick: `Stopwatch.elapsedMicroseconds` (monotonic, immune to NTP corrections, sub-microsecond cost — see §Architecture Patterns Pattern 6).**
- Whether `RevealDiscRepository` is its own file under `lib/domain/revealed/` or composed into the existing `lib/domain/revealed/reveal_disc.dart`.
- The exact `kMirkFog*` constant set chosen for the shader-sanity screen synthetic SDF.
- Whether the in-flight per-frame probe samples are kept in a ring buffer or computed as streaming statistics (Welford / P² estimator).

### Deferred Ideas (OUT OF SCOPE)

- **`tool/extract_walk.dart` helper** for auto-extracting probe + SDF stats from the JSONL log into a Markdown evidence block.
- **Golden-image diff for the shader-sanity screen.**
- **Frame-delta probe `p99Ms` field** (working baseline is `medianMs / p95Ms / maxMs`).
- **Probe overlay yellow-band cutoffs (50% over green)** — tune-if-needed.
- **Walk-replay tool** (record GPS fixes during a walk, replay on Pixel 4a / Windows desktop).
- **Per-rebuild raw JSONL line for the SDF logger** (default is 1-second rollup).
- **Phase 5 verdict promotion to `POC_VERDICT.md` at repo root.**
- **Pixel 4a Phase 3 walk** (PERF-06 informational FPS recording — Phase 3 plan should produce a debug APK from CI and let the developer walk Pixel 4a opportunistically; informational data only).
- **Cross-restart auto-resume routing bug** (deferred from Phase 1 AUTH-04).
- **AUTH-04 cross-restart re-grant flow.**
- **Worker-isolate SDF rebuild** — UI isolate is sufficient at POC scale.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FOG-01 | On each GPS fix, a `RevealDisc(lat, lon, 25 m)` is added to an in-memory disc list (no database) | §Architecture Patterns Pattern 4 (RevealDiscRepository in MapScreenServices); existing `_subscribeToPositions` in `MapScreen` (Phase 2) extends with `repository.append(...)` |
| FOG-02 | A 256×256 R-channel midpoint-128 SDF (`ui.Image`) is built from the disc list via `RevealedSdfBuilder.buildFromDiscs`, with distance computed in **metres**, not pixels | Asset already ported in Phase 1 BOOT-08 (`lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart` 244 lines, BUG-011 metre-distance fix preserved); §Code Examples Example 1 shows the call site |
| FOG-03 | The SDF is rebuilt when the disc list changes; the rebuild runs on the UI isolate (acceptable for `< 100` discs at `< 16 ms`); a debug log records each rebuild's duration | §Architecture Patterns Pattern 5 (input-hash cache + per-second JSONL rollup); donor docstring's `~67k pixel updates × disc-count` cost analysis |
| FOG-04 | A `FogLayer` widget is registered as a `flutter_map` custom layer that paints into the same Canvas as the tile layer | §Architecture Patterns Pattern 1 (`StatelessWidget` → `MobileLayerTransformer` → `CustomPaint`); FlutterMap children list ordering |
| FOG-05 | Inside `FogLayer.paint()`, the 41 float uniforms + 1 sampler of `atmospheric_fog.frag` are populated; identity sdfRect (`0, 0, 1, 1`) is passed because the SDF and the viewport share the same coordinate space | `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart` `setAll()` already exists with hand-counted slot indices; §Code Examples Example 3 |
| FOG-06 | The clip path (world rect minus disc circles, in screen coordinates) is computed and applied via `canvas.clipPath`; the shader is then drawn via `canvas.drawRect(viewport, Paint()..shader = fogShader)` | `MapCamera.latLngToScreenOffset(...)` for disc → screen projection; §Code Examples Example 2 |
| FOG-07 | All inputs to the per-frame fog draw — SDF rect, clip path, viewport size, shader uniforms — derive from the **same `MapCamera` snapshot**, captured atomically at the start of paint | §Architecture Patterns Pattern 2 (single MapCamera capture); §Common Pitfalls Pitfall 1 (multi-read inconsistency); §Validation Architecture (FOG-07 unit test seam) |
| FOG-08 | A frame-delta self-debug probe records, per frame: timestamp of the latest map camera update, timestamp of the fog uniform population, the delta between them; rolling median, p95, and max are exposed via the logger and an on-screen overlay | §Architecture Patterns Pattern 6 (Stopwatch monotonic source, FrameDeltaProbe singleton with Stream<rollup>); §Validation Architecture (probe rollup correctness test) |
| PERF-03 | At Phase 3 UAT walk on iPhone 17 Pro: pan-FPS with fog active ≥ 30; idle-fog-animation FPS ≥ 50 | Existing `FpsCounterOverlay` from Phase 1 already reads `display.refreshRate` for ProMotion-aware display; UAT walk template from Phase 2 plan 02-06 reusable |
| PERF-04 | Frame-delta probe shows median ≤ 16 ms, p95 ≤ 32 ms, max ≤ 48 ms across ≥ 10 combined gestures | §Architecture Patterns Pattern 6; §Validation Architecture probe-correctness test; §Common Pitfalls Pitfall 4 (DateTime.now non-monotonic) |
| PERF-05 | Developer's subjective verdict — no visible fog slip, no white-ellipse artefact during pan/zoom/combined gestures | §Common Pitfalls Pitfall 1 (the white-ellipse symptom IS the multi-MapCamera-read regression); FOG-07 unit test enforces by-construction; falsification doc Criterion B |
</phase_requirements>

## Standard Stack

### Core (already in `pubspec.yaml` — Phase 3 introduces no new runtime dependency)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter` SDK | 3.41.7 | `dart:ui` `FragmentProgram`/`FragmentShader`/`Canvas`; `flutter/scheduler.dart` `SchedulerBinding`; `flutter/widgets.dart` `CustomPaint` | The `dart:ui` shader pipeline and the scheduler `addTimingsCallback` API are the only blessed paths for these capabilities — no third-party alternative exists |
| `flutter_map` | 7.0.2 | `MapCamera`, `MapCamera.of(context)`, `MobileLayerTransformer`, `MapController.mapEventStream` | Already pinned in `pubspec.yaml` (Path A chain, planner-locked); Phase 3 layer plugs into the existing `FlutterMap` children list |
| `latlong2` | 0.9.1 | `LatLng` for projection-source coordinates (already used in Phase 2 blue-dot, recenter FAB) | Already pinned |
| `vector_map_tiles` | 8.0.0 | tile layer renderer (unrelated to fog but co-resident in the same FlutterMap) | Already pinned |
| `logging` | 1.3.0 | `Logger('infrastructure.mirk.sdf')` and `Logger('infrastructure.mirk.frame_delta')` per CONTEXT.md cadence; pipes through existing FileLogger sink | Already pinned and bootstrapped in Phase 1 |

### Supporting (already pinned)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `path_provider` | 2.1.5 | `getApplicationDocumentsDirectory()` for the FileLogger session log already used by FileLogger; no new use in Phase 3 | Existing usage suffices |
| `path` | 1.9.1 | `p.join()` for any new file paths (per CLAUDE.md "Toujours utiliser `p.join()`") | Constants only, no new path math expected |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `addTimingsCallback` | `PlatformDispatcher.instance.onReportTimings = ...` directly | The platform-dispatcher slot is single-listener — assigning it from FrameDeltaProbe overwrites any other library that might use the slot (none today, but the multi-listener API costs nothing extra and is the documented best practice). Rejected. |
| `Stopwatch.elapsedMicroseconds` for probe timestamps | `DateTime.now().microsecondsSinceEpoch` | `DateTime.now()` is wall-clock and can jump backwards on NTP correction during a 5-minute walk. The probe would emit nonsensical negative deltas. Rejected. |
| `Stopwatch.elapsedMicroseconds` for probe timestamps | `clock_gettime(CLOCK_MONOTONIC)` via FFI | Functionally equivalent on iOS (Stopwatch is implemented atop `mach_absolute_time` which is the same monotonic clock as `CLOCK_MONOTONIC_RAW`). FFI adds zero accuracy and a transitive-dep audit burden. Rejected. |
| `CustomPaint` with `Listenable` repaint | `setState()` per animation tick | `setState` triggers the build phase (incurs widget reconciliation). `Listenable` repaint skips build and goes straight to paint — the documented efficient path for animated painters. The fog drift (`uTime` uniform) needs a per-frame repaint but no widget rebuild. Use `Listenable` repaint. |
| `MobileLayerTransformer` | Manual `Transform` widget reading `camera.rotation`, `camera.center`, projection math | `MobileLayerTransformer` is the documented blessed path; rolling our own re-introduces classes of off-by-one rotation/zoom bugs the flutter_map team has already debugged. Use `MobileLayerTransformer`. |
| Per-build `program.fragmentShader()` | One `late final` shader created once at screen mount | Flutter docs explicitly say "Reuse `FragmentShader` instances across frames (more efficient than creating new ones per frame)". Per-build allocation would also break the Phase 1 anti-pattern lock against per-build allocation. Use `late final`. |

**Installation:** Phase 3 introduces NO new dependencies. Every package needed is already in `pubspec.yaml` and audited in `DEPENDENCIES.md`.

## Architecture Patterns

### Recommended Project Structure

```
lib/
├── presentation/widgets/
│   ├── fog_layer.dart                    # NEW (FOG-04..07): the custom layer; reads MapCamera.of(context) once
│   └── frame_delta_probe_overlay.dart    # NEW: 3-line med/p95/max overlay, 1 Hz refresh
├── presentation/screens/
│   └── shader_sanity_screen.dart         # NEW: hardcoded-uniforms /sanity route entry
├── infrastructure/mirk/
│   ├── frame_delta_probe.dart            # NEW (FOG-08): singleton or DI-injected; exposes Stream<FrameDeltaRollup>
│   ├── sdf_rebuild_logger.dart           # NEW: 1-second rollup of SDF rebuild stats
│   └── sdf/
│       ├── revealed_sdf_builder.dart     # EXISTING (Phase 1 BOOT-08, do not modify)
│       └── sdf_cache.dart                # NEW: input-hash cache wrapping the builder
├── domain/revealed/
│   ├── reveal_disc.dart                  # EXISTING (Phase 1 BOOT-08, do not modify)
│   └── reveal_disc_repository.dart       # NEW (FOG-01): in-memory list + ChangeNotifier
└── domain/map/
    └── map_screen_services.dart          # EXTEND: add discRepository field
```

### Pattern 1: flutter_map Custom Layer (FOG-04)

**What:** A custom flutter_map layer is a `Widget` returned in the `FlutterMap.children: <Widget>[...]` list. It runs inside the FlutterMap's `BuildContext`, so it can call `MapCamera.of(context)` to obtain the current camera state. Mobile (i.e. world-space) layers wrap their content in `MobileLayerTransformer` so the rotation / translation / zoom transforms applied to the tile layer are also applied to the custom paint.

**When to use:** For everything that paints in world space and must move WITH the map. The fog (FOG-04..06) lives entirely in world space — every disc has a `LatLng` centre, the SDF is computed in a `MirkViewportBbox` that is the camera's `visibleBounds`, the clip path is in world-projected screen pixels.

**Example:**
```dart
// Source: https://docs.fleaflet.dev/plugins/create/layers and the inferred-from-docs FogLayer skeleton.
class FogLayer extends StatefulWidget {
  const FogLayer({super.key, required this.discRepository, required this.shader, required this.frameDeltaProbe});

  final RevealDiscRepository discRepository;
  final ui.FragmentShader shader; // already-instantiated, reused across frames
  final FrameDeltaProbe frameDeltaProbe;

  @override
  State<FogLayer> createState() => _FogLayerState();
}

class _FogLayerState extends State<FogLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _wallClockSinceMount = Stopwatch()..start();
  // _Repaint extends ChangeNotifier; CustomPainter listens to it (Listenable repaint mode)
  final _Repaint _repaint = _Repaint();

  @override
  void initState() {
    super.initState();
    // Driving the fog drift uTime — ticker emits one event per frame from the
    // scheduler. The CustomPainter's repaint Listenable is notified each tick;
    // shouldRepaint is bypassed entirely (Listenable repaint skips the build
    // phase and goes straight to paint).
    _ticker = createTicker((_) => _repaint.tick());
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FOG-07 LOCK: read the camera EXACTLY ONCE, here. Every downstream
    // input (SDF rect, clip path, shader uniforms, viewport size) is
    // derived from this `camera` value or the `discRepository` snapshot.
    final MapCamera camera = MapCamera.of(context);
    final List<RevealDisc> discs = widget.discRepository.snapshot(); // immutable view

    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _FogPainter(
          camera: camera,
          discs: discs,
          shader: widget.shader,
          uTimeSeconds: _wallClockSinceMount.elapsedMicroseconds / 1e6,
          frameDeltaProbe: widget.frameDeltaProbe,
          repaint: _repaint, // Listenable — re-paints on each tick without rebuild
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _Repaint extends ChangeNotifier {
  void tick() => notifyListeners();
}
```

### Pattern 2: Single MapCamera Capture (FOG-07)

**What:** `MapCamera.of(context)` returns the current camera state, AND subscribes the calling widget to camera changes (via inherited-widget `dependOnInheritedWidgetOfExactType`). Every call from the same `BuildContext` returns the same value during a single build. But — critically — calling it twice in a build that spans an async gap, or once in `build()` and again deeper in a `CustomPainter.paint()` via a stale context, is the failure mode that re-creates BUG-014.

**When to use:** Always — this is the FOG-07 lock. There is exactly ONE `MapCamera.of(context)` call per `FogLayer.build()`. The value is captured into a final local. Every consumer downstream takes it as a constructor argument.

**Example:**
```dart
// CORRECT: single read, threaded to every consumer.
@override
Widget build(BuildContext context) {
  final MapCamera camera = MapCamera.of(context);
  final discs = widget.discRepository.snapshot();
  return MobileLayerTransformer(
    child: CustomPaint(
      painter: _FogPainter(camera: camera, discs: discs, ...),
      size: Size.infinite,
    ),
  );
}

// WRONG (re-introduces BUG-014): the painter re-reads the camera from a
// captured-at-construction-time context, which may be stale by paint time.
class _FogPainter extends CustomPainter {
  final BuildContext context; // <-- DO NOT capture context
  @override
  void paint(Canvas canvas, Size size) {
    final camera = MapCamera.of(context); // <-- DO NOT re-read here
    // ...
  }
}
```

### Pattern 3: Reusing FragmentShader Instances

**What:** `FragmentProgram.fromAsset('assets/shaders/atmospheric_fog.frag')` is asynchronous and somewhat expensive (the program is loaded from the bundled asset and prepared by Impeller). Calling `program.fragmentShader()` returns a fresh `FragmentShader` whose uniforms can be set independently. Per-frame `program.fragmentShader()` calls are wasteful per Flutter docs ("more efficient than creating new ones per frame" to reuse).

**When to use:** For the `FogLayer` and `ShaderSanityScreen`. Both load the program once at screen mount via a `Future` resolved before the first paint, then reuse the same `FragmentShader` instance across all subsequent frames.

**Example:**
```dart
// Source: https://docs.flutter.dev/ui/design/graphics/fragment-shaders + project's existing
// asset registration in pubspec.yaml `flutter.shaders`.
class _MapScreenState extends State<MapScreen> {
  ui.FragmentProgram? _fogProgram;
  ui.FragmentShader? _fogShader;

  @override
  void initState() {
    super.initState();
    _loadFogShader();
  }

  Future<void> _loadFogShader() async {
    final program = await ui.FragmentProgram.fromAsset(
      kPocFogShaderAssetPath, // 'assets/shaders/atmospheric_fog.frag'
    );
    if (!mounted) return;
    setState(() {
      _fogProgram = program;
      _fogShader = program.fragmentShader();
    });
  }

  // _fogShader is reused across every FogLayer.build() — never reallocated.
}
```

### Pattern 4: RevealDiscRepository (FOG-01)

**What:** An in-memory list of `RevealDisc` (no DB per project scope). Mutates on every GPS fix from the existing `_subscribeToPositions` listener in `MapScreen` (Phase 2). Notifies listeners on mutation so the FogLayer / shader-sanity screen can refresh. Constructor-injected through `MapScreenServices`.

**When to use:** Phase 3 introduces this; Phase 4 wisp work consumes the same repository (disc-perimeter spawning).

**Example:**
```dart
// Mirrors parent MirkFall RevealDiscRepository shape — planner verifies during port.
class RevealDiscRepository extends ChangeNotifier {
  final List<RevealDisc> _discs = <RevealDisc>[];

  /// Immutable view for paint-time consumers. Returns a List that the SDF
  /// hasher and clip-path builder can iterate without copying.
  List<RevealDisc> snapshot() => List<RevealDisc>.unmodifiable(_discs);

  void append(RevealDisc disc) {
    _discs.add(disc);
    notifyListeners();
  }
}
```

The repository is added to `MapScreenServices` and `MapScreen._subscribeToPositions` extends:
```dart
_positionSubscription = widget.services.positionStreamFactory().listen((Position fix) {
  if (!mounted) return;
  setState(() => _lastFix = fix);
  // FOG-01: every fix → 25 m disc.
  widget.services.discRepository.append(RevealDisc(
    id: 'rvd_${ulid()}',
    sessionId: 'poc',
    lat: fix.latitude,
    lon: fix.longitude,
    radiusMeters: 25.0,
    fixedAtUtc: DateTime.now().toUtc(),
  ));
  _log.info('Fix: ...');
});
```

### Pattern 5: SDF Hash Cache (FOG-03)

**What:** The donor `RevealedSdfBuilder` is stateless. The cache lives one layer up (in `FogLayer` state or a sibling `SdfCache`). Hash key: `(disc-list identity-hash, viewport bbox quantized to ~6 decimals, mean lat quantized)`. On hit, return the previous `ui.Image`. On miss, kick off `buildFromDiscs()` (returns `Future<ui.Image>`), record the rebuild duration via the `SdfRebuildLogger`, and update the cache.

**When to use:** Every `FogLayer` paint, before the shader uniform population step.

**Example:**
```dart
class SdfCache {
  ui.Image? _cachedImage;
  int? _cachedHash;
  final RevealedSdfBuilder _builder = const RevealedSdfBuilder();
  final SdfRebuildLogger _rebuildLogger;

  SdfCache(this._rebuildLogger);

  /// Returns either a cached image or kicks off a rebuild.
  /// Rebuild is `await`ed by the caller — at POC scale (~50 discs), the cost
  /// is sub-ms and we accept the synchronous hit during pan/zoom rebuilds.
  Future<ui.Image> getOrBuild({required List<RevealDisc> discs, required MirkViewportBbox viewport}) async {
    final h = _hash(discs, viewport);
    if (h == _cachedHash && _cachedImage != null) return _cachedImage!;
    final sw = Stopwatch()..start();
    final image = await _builder.buildFromDiscs(discs: discs, viewport: viewport);
    sw.stop();
    _cachedImage?.dispose();
    _cachedImage = image;
    _cachedHash = h;
    _rebuildLogger.recordRebuild(elapsedMs: sw.elapsedMicroseconds / 1000.0, discCount: discs.length);
    return image;
  }
}
```

**Caveat:** the FogLayer's per-frame paint is NOT async. The cache lookup must be synchronous in the paint path. Two-step pattern: (a) `FogLayer.build()` calls `cache.getOrBuild(...)` (returns Future), and seeds a `Future`-backed `ValueNotifier<ui.Image?>`; (b) the painter uses the most-recent-completed image. On cache hit (most pan frames after the first), the image is already there and there is no async wait.

### Pattern 6: FrameDeltaProbe + addTimingsCallback (FOG-08)

**What:** Two timestamp sources combined.
1. **In-paint Stopwatch capture:** in `_FogPainter.paint()` (after the camera was captured in `FogLayer.build()`), before `setAll()` is called, record `fogPaintMicros = _stopwatch.elapsedMicroseconds`. Pair it with the `cameraUpdateMicros` recorded when the layer's `build()` was entered (also via the same monotonic Stopwatch). The delta `(fogPaintMicros - cameraUpdateMicros)` is the FOG-08 number.
2. **`addTimingsCallback` for FPS context:** in `FrameDeltaProbe.start()`, register `SchedulerBinding.instance.addTimingsCallback`. Each batch arrives every ~100ms in profile/debug, ~1s in release. Each `FrameTiming` exposes `totalSpan` (vsyncStart → rasterFinish) — this is the gold-standard "frame finished" metric. Combined with our own (cameraUpdateMicros, fogPaintMicros) channel, we get a complete picture.

**When to use:** The probe is constructed once at app boot (or `MapScreen` init) and lives until disposal. `FogLayer.build()` and `_FogPainter.paint()` push samples to it. The probe rolls them up at 1 Hz and exposes a `Stream<FrameDeltaRollup>` consumed by both the on-screen overlay and the JSONL log writer.

**Example:**
```dart
// Singleton-or-DI'd; constructed in app.dart and threaded through MapScreenServices
// (planner picks). Time source: Stopwatch.elapsedMicroseconds — monotonic on all
// platforms; on iOS backed by mach_absolute_time / CLOCK_MONOTONIC_RAW.
class FrameDeltaProbe {
  final Stopwatch _clock = Stopwatch()..start();
  final List<int> _deltaMicrosBuffer = <int>[]; // ring buffer (caps at 2 s × 120 Hz = 240)
  Timer? _rollupTimer;

  /// Called from FogLayer.build() — captures the moment the MapCamera snapshot
  /// was read. Returns the timestamp the painter MUST pair with its own.
  int recordCameraSnapshot() => _clock.elapsedMicroseconds;

  /// Called from _FogPainter.paint() right before FogShaderUniforms.setAll().
  /// `cameraSnapshotMicros` is whatever recordCameraSnapshot() returned for
  /// this same build/paint pass.
  void recordFogUniformPopulation(int cameraSnapshotMicros) {
    final paintMicros = _clock.elapsedMicroseconds;
    _deltaMicrosBuffer.add(paintMicros - cameraSnapshotMicros);
    while (_deltaMicrosBuffer.length > kPocFrameDeltaBufferMaxSamples) {
      _deltaMicrosBuffer.removeAt(0);
    }
  }

  void start() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _rollupTimer = Timer.periodic(const Duration(seconds: 1), (_) => _emitRollup());
  }

  void _onTimings(List<FrameTiming> timings) {
    // Records totalSpan per FrameTiming; merged into the per-second rollup
    // alongside the camera-to-fog deltas.
  }

  void _emitRollup() {
    if (_deltaMicrosBuffer.isEmpty) return;
    final sorted = List<int>.from(_deltaMicrosBuffer)..sort();
    final medianMicros = sorted[sorted.length ~/ 2];
    final p95Micros = sorted[(sorted.length * 0.95).floor()];
    final maxMicros = sorted.last;
    // Emits to overlay stream + JSONL logger.
  }
}
```

### Pattern 7: Shader-Sanity Screen Lifecycle

**What:** A separate route `/sanity` that owns its own FragmentProgram load + synthetic SDF build + paint loop. Reuses `FogShaderUniforms.setAll()` with `kMirkFog*` constants from `lib/config/constants.dart`. Renders once on mount with a fixed `uTime = 0` (or a Ticker if the developer wants to verify the boil animation works).

**When to use:** Pre-walk gate. Open `/sanity` via the AppBar action button BEFORE running the falsification walk. If the screen fails to render or throws shader-compile errors in the FileLogger, the IPA is broken and the walk is aborted.

### Anti-Patterns to Avoid

- **`RepaintBoundary` around `FogLayer`** — re-creates BUG-014 inside Flutter (would isolate the fog from the tile layer's repaint signal, making the fog fall behind by exactly one frame). Locked OUT per CONTEXT.md.
- **Multiple `MapCamera.of(context)` reads per build** — see Pitfall 1.
- **Dynamic `uSdfRect`** — locked OUT (always `(0, 0, 1, 1)`). The SDF is built in viewport-normalised coordinates per Phase 1 BOOT-08 port.
- **Reordering `FogShaderUniforms.setAll()` slots** — the slot indices were hand-counted to match the `.frag` declaration order; a reorder triggers BUG-014 Iter 2 regression. Tests assert `FogShaderUniforms.totalFloatSlots == 41`.
- **Per-build `FragmentProgram.fromAsset` calls** — async, expensive, breaks per-frame budget. Load once.
- **Per-build `program.fragmentShader()` calls** — wasteful per Flutter docs. Reuse one shader instance across frames.
- **`DateTime.now().microsecondsSinceEpoch` for the probe** — wall-clock, not monotonic. Use `Stopwatch.elapsedMicroseconds`.
- **`setState` for the per-frame fog drift** — triggers widget rebuilds. Use a `Listenable` `repaint` argument on `CustomPainter`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Custom-layer rotation/translation transform | Hand-rolled `Transform` widgets reading `camera.rotation` and `camera.center` | `MobileLayerTransformer` from `flutter_map` | Officially blessed; has years of bug-fixing for combined-zoom-rotate edge cases |
| LatLng → screen-offset projection | Manual Mercator math | `MapCamera.latLngToScreenOffset(LatLng)` | Already part of `flutter_map` 7.0.2, accounts for camera rotation, world wrap, and the active CRS |
| World-space visible bbox | Manual computation from `camera.center + camera.size + camera.zoom` | `MapCamera.visibleBounds` | Already accounts for rotation widening and antimeridian wrap (per 7.0.2 changelog) |
| Camera-change subscription | Manual `addListener` on `MapController.mapEventStream` | `MapCamera.of(context)` (auto-subscribes via inherited widget) | Triggers automatic rebuild on camera change without subscription bookkeeping |
| Shader uniform layout | Hand-counting slot indices ad hoc per call site | `FogShaderUniforms.setAll()` (already in `lib/`) | Single source of truth; slot indices match `.frag` declaration order |
| SDF distance computation | Pixel-space euclidean | `RevealedSdfBuilder.buildFromDiscs` (metric distance — BUG-011 fix preserved) | Donor file already has the metric-space fix; pixel-space distance produces north-south oval at non-equatorial latitudes |
| Frame-timing capture | `PlatformDispatcher.instance.onReportTimings = ...` (single-listener slot) | `SchedulerBinding.instance.addTimingsCallback(...)` | Multi-listener-safe; documented best practice |
| Monotonic per-frame timestamps | `DateTime.now().microsecondsSinceEpoch` | `Stopwatch.elapsedMicroseconds` | Stopwatch backed by `mach_absolute_time` / `CLOCK_MONOTONIC_RAW` on iOS — immune to NTP corrections during a 5-min walk |
| Per-tick repaint trigger | `setState((){})` in a `Ticker` callback | `Listenable repaint` argument on `CustomPainter`, with the `Listenable` notifying listeners per tick | Skips the build phase entirely — paint-only repaint, the documented efficient path |
| Streaming median/p95 | Welford / P² estimator | A simple ring-buffer + sort at 1 Hz emit time | At ≤ 240 samples (2 s × 120 Hz), `O(n log n)` once per second is ~10 µs — far cheaper than the algorithmic complexity of P². Planner's discretion to upgrade if the buffer grows. |

**Key insight:** Phase 3 is mostly orchestration. The hard infrastructure (shader, SDF builder, slot layout, FPS overlay, log sink) is already done. The risk is NOT in writing new infrastructure — it is in WIRING IT WRONG (anti-patterns above).

## Common Pitfalls

### Pitfall 1: Multiple `MapCamera.of(context)` reads per build

**What goes wrong:** In a build that spans an async gap or threads `BuildContext` through to a `CustomPainter.paint()` body, each `MapCamera.of(context)` read returns the camera state AT THE TIME OF THE READ. During a fast pinch-zoom, the camera state mutates 60–120 times per second; two reads 1 ms apart can return slightly different `zoom` / `center` / `rotation` values. The downstream uniforms / clip path / sdfRect then derive from inconsistent state — the visible symptom in the parent project was a white ellipse during fast pinch-zoom (the clip path's disc circles were computed at zoom Z, the shader's distance falloff was computed at zoom Z+ε; the band between them is unfilled).

**Why it happens:** The natural temptation is to "encapsulate" by reading the camera deep in the painter. This breaks atomicity.

**How to avoid:** Single read in `FogLayer.build()`, captured into a `final MapCamera camera = MapCamera.of(context);`. Every consumer (clip path computation, SDF rect computation, shader uniform population, viewport size) takes `camera` as a constructor argument. The painter is a pure function of its constructor inputs — never re-reads context.

**Warning signs:** Any time a `BuildContext` is captured into a `CustomPainter` field, or any time the word "MapCamera" appears more than once in a non-test `FogLayer*.dart` file outside the `build()` method's first line.

**Test seam:** A unit test mounts a `FogLayer` with a fake `RevealDiscRepository` and a `MapCamera.of(context)` test seam, drives a single build, and asserts that the painter's stored `camera` field is identical (`identical()`) to the one returned by `MapCamera.of(context)`. See §Validation Architecture.

### Pitfall 2: Degree-vs-meter distance regression (FOG-01)

**What goes wrong:** Naively computing distance between `(48.5, 2.6)` and `(48.5, 3.6)` in degree space (~`sqrt(0² + 1²) = 1`) and treating it as kilometres yields ~111 km (1° lat ≈ 111 km), which is wrong because at latitude 48.5° one degree of longitude is only ~73.7 km (cos(48.5°) ≈ 0.66). The donor `RevealedSdfBuilder` (and `RevealDisc.distanceMetersTo`) already use Haversine + `kMetersPerDegreeLat` × `cos(lat)` correctly. But Phase 3 introduces new code (the FOG-01 GPS-fix-to-disc append, possibly new clip-path geometry) where this regression can sneak back in.

**Why it happens:** Pixel-space "distance" is a tempting shortcut when computing screen-space clip-path circles.

**How to avoid:** Always compute distances in metres, never in degrees, never in pixels. Use the existing `kMetersPerDegreeLat` and `kEarthRadiusMeters` constants. The `RevealDisc.distanceMetersTo` and `RevealedSdfBuilder.buildFromDiscs` methods are already correct — call THEM, don't rewrite.

**Test seam:** Required by Phase 3 success criterion 1. A unit test asserts `distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km` (not ~111 km). The function under test should be a top-level helper that simply delegates to the existing `RevealDisc` helper (or to a copy of the Haversine math factored to a shared file).

### Pitfall 3: Shader compile error on first paint (Impeller iOS)

**What goes wrong:** The shader is compiled at app build time by Impeller (post 3.10). Compile errors land at FragmentProgram.fromAsset call time, throwing an exception. If this happens during the iPhone walk it's a wasted walk.

**Why it happens:** A typo in the `.frag` (less likely — the file is verbatim from the parent and known-good), OR a uniform-count mismatch between `setAll()` and the `.frag` (a Phase 3 regression risk if anyone touches the `.frag` or `setAll`).

**How to avoid:** (a) Don't touch the `.frag` — it is verbatim from the parent BOOT-08 port. (b) The `assertion FogShaderUniforms.totalFloatSlots == 41` unit test catches divergence statically. (c) The shader-sanity screen IS a pre-walk gate — if it doesn't render, the walk doesn't happen.

**Test seam:** Pre-walk shader-sanity screen smoke test (manual but mandatory before sideload).

### Pitfall 4: Wall-clock timestamps in the probe

**What goes wrong:** During a 5-min walk, iOS may run an NTP synchronisation that adjusts the wall clock by ±100 ms. If the probe uses `DateTime.now().microsecondsSinceEpoch`, the adjustment manifests as a single frame with a 100,000 µs delta — corrupting the probe's `max` field and making the rolling p95 untrustworthy.

**Why it happens:** Wall-clock APIs feel familiar; their non-monotonic property is non-obvious.

**How to avoid:** The probe's single `Stopwatch _clock = Stopwatch()..start()` (started at probe construction) is the SOLE timestamp source for both the camera-snapshot and fog-paint markers. Stopwatch on iOS is backed by `mach_absolute_time` (Apple's monotonic raw clock) — immune to NTP, daylight-savings, and user clock changes.

**Test seam:** Unit test that records two timestamps, advances `clock_gettime(CLOCK_MONOTONIC)` by simulating elapsed time, and asserts the delta is consistent. (Or a simpler test that asserts the probe rejects negative deltas — never possible from Stopwatch but a defence-in-depth assertion.)

### Pitfall 5: `addTimingsCallback` batching surprises

**What goes wrong:** `addTimingsCallback` batches frames and delivers the list approximately every ~100 ms in profile / debug, ~1 s in release. The probe overlay would be delivering stale "1-second-old p95" if it relied on this for the on-screen number; the visible UX would be sluggish during the walk.

**Why it happens:** The batching is documented but easy to miss.

**How to avoid:** Don't use `addTimingsCallback` as the primary feed for the on-screen overlay. Use the in-paint Stopwatch capture (which fires every frame, no batching) for the live number. Use `addTimingsCallback` as a SUPPLEMENTARY feed for the JSONL log's `totalSpan` field (frame-finished-on-screen — useful post-walk context).

**Test seam:** Probe rollup correctness test asserts the median/p95/max are computed from the per-frame Stopwatch deltas, not from the batched FrameTimings.

### Pitfall 6: SDF rebuild during pan blocking the UI thread

**What goes wrong:** At Phase 3 disc counts (~50), the SDF rebuild is sub-ms. But if a regression pushes disc-count to 500+ (e.g. a bug in compaction policy), the rebuild can hit ~30 ms and visibly stall the pan.

**Why it happens:** The donor builder's documented cost is `~67k pixel updates × intersecting-disc-count`. At 50 discs over a 5-min walk in central Melun, only a handful intersect the viewport at any moment. At 500 discs the cost rises proportionally.

**How to avoid:** (a) Hash cache (Pattern 5) — most pan frames are cache hits. (b) Researcher must measure on iPhone 17 Pro during Phase 3 walk and document numbers in this RESEARCH.md before the planner builds the cache. (c) If the measurement shows budget pressure, fall back to a 60 Hz cap on the 120 Hz device (default OFF; documented as a fallback knob per CONTEXT.md). (d) Worker-isolate offload is OUT OF SCOPE for the POC (deferred to MirkFall migration per CONTEXT.md).

**Test seam:** Unit test on the SDF rebuild logger asserts the per-rebuild duration is tracked correctly. The actual measurement happens during the iPhone walk.

### Pitfall 7: Slow `FragmentProgram.fromAsset` blocking first paint

**What goes wrong:** If `_loadFogShader()` is awaited in `MapScreen.initState`'s synchronous critical path, the screen displays a loading spinner for the duration of the load. On Impeller iOS this is fast (tens of ms) but observable.

**Why it happens:** Async-await sequencing in `initState`.

**How to avoid:** Same pattern as Phase 2's `_loadTileProvider()`: kick off the load asynchronously without awaiting in the synchronous path; render a fallback (`ColoredBox`) until the shader is ready. The pattern is established in `lib/presentation/screens/map_screen.dart` already.

### Pitfall 8: `MobileLayerTransformer` missing → fog detached from map

**What goes wrong:** Forget to wrap the `CustomPaint` in `MobileLayerTransformer`, the fog renders at screen origin and doesn't move with the map. This is the OPPOSITE of BUG-014 — it's the no-rotation-no-pan trap.

**Why it happens:** Easy oversight when the layer hierarchy is being assembled.

**How to avoid:** Always wrap the painter in `MobileLayerTransformer`. The widget tree should read `MobileLayerTransformer(child: CustomPaint(...))` for any world-space layer.

**Test seam:** Widget test mounts FogLayer inside FlutterMap, captures the rendered widget tree, and asserts a `MobileLayerTransformer` ancestor exists for the painter.

### Pitfall 9: Disc-list mutation during paint

**What goes wrong:** A new GPS fix arrives mid-paint, the listener calls `repository.append`, the painter is mid-iterating the list, throws `ConcurrentModificationError`.

**Why it happens:** Dart Lists are not concurrent. CLAUDE.md explicitly bans this: "Ne jamais muter une collection pendant son itération."

**How to avoid:** `repository.snapshot()` returns `List.unmodifiable(_discs)` — a defensive copy. The painter iterates the snapshot, never the live list. New fixes mutate the underlying `_discs` and notify listeners; the next build picks up the new snapshot.

**Test seam:** Repository unit test triggers `append` during iteration via a snapshot; asserts no `ConcurrentModificationError`.

### Pitfall 10: Listenable repaint not driving the painter

**What goes wrong:** The `Ticker` fires per frame, but the painter doesn't repaint, because the `repaint:` argument was forgotten on `CustomPainter`'s super-constructor.

**Why it happens:** `CustomPainter`'s `repaint:` Listenable is an optional super argument; easy to omit.

**How to avoid:** Always pass `repaint: _repaint` (a `ChangeNotifier` driven by the Ticker) when the painter has time-varying state (uTime drift). Verify with a widget test that the painter's `paint()` method is called more than once during a `pump`.

**Test seam:** Widget test pumps a fake clock forward; asserts the painter's call count increased.

## Code Examples

### Example 1: Loading the FragmentProgram once

```dart
// Source: https://docs.flutter.dev/ui/design/graphics/fragment-shaders + project pubspec.yaml
// flutter.shaders entry. The asset path matches the pubspec entry exactly.
import 'dart:ui' as ui;

class _MapScreenState extends State<MapScreen> {
  ui.FragmentProgram? _fogProgram;
  ui.FragmentShader? _fogShader;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFogShader());
  }

  Future<void> _loadFogShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(kPocFogShaderAssetPath);
      if (!mounted) return;
      setState(() {
        _fogProgram = program;
        _fogShader = program.fragmentShader();
      });
    } on Object catch (e, st) {
      _log.severe('Failed to load fog shader', e, st);
    }
  }
}
```

### Example 2: Computing the clip path from discs (FOG-06)

```dart
// Source: inferred from MapCamera.latLngToScreenOffset and the donor disc list.
// Each disc becomes a screen-space circle subtracted from the world rect.
Path computeFogClipPath({required MapCamera camera, required List<RevealDisc> discs}) {
  final viewportRect = Offset.zero & camera.size;
  final worldPath = Path()..addRect(viewportRect);
  if (discs.isEmpty) return worldPath;

  final holesPath = Path();
  for (final disc in discs) {
    final centerOffset = camera.latLngToScreenOffset(LatLng(disc.lat, disc.lon));
    // Convert disc.radiusMeters → pixels using the camera's metres-per-pixel
    // at the disc's latitude. Reuse RevealDisc's existing latitude-aware
    // metersPerDegree math; or use camera.pixelOrigin + project at the
    // disc center.
    final pixelRadius = _metersToPixels(disc.radiusMeters, disc.lat, camera);
    holesPath.addOval(Rect.fromCircle(center: centerOffset, radius: pixelRadius));
  }
  return Path.combine(PathOperation.difference, worldPath, holesPath);
}
```

### Example 3: Painter populating uniforms and drawing (FOG-05/06)

```dart
class _FogPainter extends CustomPainter {
  _FogPainter({
    required this.camera,
    required this.discs,
    required this.shader,
    required this.uTimeSeconds,
    required this.frameDeltaProbe,
    required this.cameraSnapshotMicros,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapCamera camera;
  final List<RevealDisc> discs;
  final ui.FragmentShader shader;
  final double uTimeSeconds;
  final FrameDeltaProbe frameDeltaProbe;
  final int cameraSnapshotMicros;

  @override
  void paint(Canvas canvas, Size size) {
    final clipPath = computeFogClipPath(camera: camera, discs: discs);
    canvas.save();
    canvas.clipPath(clipPath);

    // FOG-05: populate all 41 uniforms via the locked single-source-of-truth.
    FogShaderUniforms.setAll(
      shader,
      resolution: size,
      time: uTimeSeconds,
      offset: const (0.0, 0.0),
      baseArgb: kMirkFogAtmosphericBaseColorArgb,
      baseAlpha: 1.0,
      // ... (all kMirkFog* constants)
      sdfRect: const (0.0, 0.0, 1.0, 1.0), // FOG-05 identity uSdfRect — non-negotiable
      sdfImage: _resolveSdfImageForCurrentFrame(), // from cache
    );

    // FOG-08: now record the fog-uniform-population timestamp, paired with
    // the camera-snapshot timestamp passed in the constructor.
    frameDeltaProbe.recordFogUniformPopulation(cameraSnapshotMicros);

    // FOG-06: draw the shader fill across the viewport.
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FogPainter old) =>
      old.camera != camera ||
      old.discs.length != discs.length ||
      old.uTimeSeconds != uTimeSeconds;
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Skia SkSL shader compilation at runtime | Impeller AOT shader compilation at app build time | Default on iOS since Flutter 3.10; default everywhere by 2026 | No first-frame compile jank for `.frag` files; bundling SKSL warmup files is now obsolete on iOS |
| `PlatformDispatcher.instance.onReportTimings = ...` (single listener) | `SchedulerBinding.instance.addTimingsCallback(...)` (multi-listener) | Always preferred since the multi-listener API existed; documentation now strongly recommends | No code change needed if only one feature uses it, but Phase 3 should use the latter for forward compatibility |
| `setState` for animated CustomPainter | `repaint:` Listenable on CustomPainter constructor | Documented best practice for years; still under-used | Skips the build phase entirely — paint-only repaint cycles, lower CPU per frame |
| `MapController.of(context).camera` | `MapCamera.of(context)` directly | flutter_map 7.0.0 | More performant per upstream docs (skips the controller indirection) |

**Deprecated / outdated:**
- The 2023-era recommendation to bundle `shaders_warmup.json` with the iOS app — superseded by Impeller's AOT compilation. POC ignores; no warmup bundling needed.

## Open Questions

1. **Actual iPhone 17 Pro SDF rebuild ms at 50 discs / 256² SDF / Melun viewport**
   - What we know: donor docstring estimates `~67k pixel updates × intersecting-disc-count`, putting 50 discs well under 1 ms per architectural reasoning.
   - What's unclear: actual Apple A19 Pro number — Phase 3 has had no on-device measurement yet.
   - Recommendation: Phase 3 plan includes explicit "measure rebuild ms during the walk and append to RESEARCH.md" Wave 0 step. The 1 Hz JSONL rollup carries the data automatically; no extra instrumentation needed.

2. **Whether `MapCamera.latLngToScreenOffset` accounts for rotation by itself, or whether `MobileLayerTransformer` re-applies it**
   - What we know: `MapCamera.size` is the rotation-aware viewport size (vs `nonRotatedSize`); `latLngToScreenOffset` is documented as returning widget-relative pixel positions.
   - What's unclear: whether the painter inside `MobileLayerTransformer` should project to the rotated frame (`size`) or the non-rotated frame (`nonRotatedSize`), then let `MobileLayerTransformer` rotate.
   - Recommendation: planner reads the `MobileLayerTransformer` source in flutter_map 7.0.2 to confirm convention; default reading from existing flutter_map 7.0.2 examples is "project to non-rotated; let `MobileLayerTransformer` rotate". A minimal smoke test on `/sanity` with the camera rotated 45° will surface a misalignment immediately.

3. **Whether `Ticker.start()` keeps the FogLayer at 120 Hz idle even when nothing is changing**
   - What we know: `Ticker` fires once per frame request; idle frames may not be requested. Phase 2 walk verified idle FPS sits at ~4 fps (Flutter no-dirty-frames behaviour).
   - What's unclear: whether the fog drift `uTime` animation is enough of a "dirty frame" signal to keep the scheduler producing 120 Hz frames. PERF-03's "idle-fog-animation FPS ≥ 50" gate depends on this.
   - Recommendation: planner ensures the `Ticker.start()` is unconditional (keeps requesting frames); confirms with the walk. If idle-FPS is below 50, the planner adds a `WidgetsBinding.scheduleFrame()` call from the ticker callback as a fallback (unlikely but cheap).

4. **`ulid` package vs hand-rolled disc ID**
   - What we know: `RevealDisc.id` follows `rvd_<26-char-ULID>`. POC has no `ulid` dep yet.
   - What's unclear: whether to add a ULID dep (audit cost) or hand-roll a `rvd_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1<<32)}` placeholder.
   - Recommendation: hand-roll for Phase 3; ULID purity is irrelevant to the in-memory POC. Document in adaptation notes.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (Flutter SDK 3.41.7) + `test: 1.30.0` (already pinned for `tool/test/`) |
| Config file | `analysis_options.yaml` (strict-casts/inference/raw-types); no separate test config |
| Quick run command | `flutter test test/presentation/widgets/fog_layer_test.dart -r expanded` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOG-01 | New GPS fix → `RevealDiscRepository.append` called with `RevealDisc(lat, lon, 25.0, _)` | unit | `flutter test test/domain/revealed/reveal_disc_repository_test.dart -r expanded` | Wave 0 |
| FOG-01 | `MapScreen._subscribeToPositions` calls `discRepository.append` on each fix (integration with existing position stream) | widget | `flutter test test/presentation/screens/map_screen_fog_test.dart -r expanded` | Wave 0 |
| FOG-02 | `RevealedSdfBuilder.buildFromDiscs` returns 256×256 ui.Image with metric-distance encoding | unit (regression) | `flutter test test/infrastructure/mirk/sdf/revealed_sdf_builder_test.dart -r expanded` | Wave 0 (existing donor test may already cover this; verify) |
| FOG-02 (defence) | `distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km` (NOT ~111 km — degree-vs-meter regression) | unit | `flutter test test/domain/revealed/distance_metres_test.dart -r expanded` | Wave 0 |
| FOG-03 | SDF cache hit/miss correctness: same `(discs, viewport)` returns same `ui.Image` (identity); different inputs trigger rebuild | unit | `flutter test test/infrastructure/mirk/sdf/sdf_cache_test.dart -r expanded` | Wave 0 |
| FOG-03 | SDF rebuild logger emits one JSONL line per active second with `medianMs`, `p95Ms`, `maxMs` fields | unit | `flutter test test/infrastructure/mirk/sdf_rebuild_logger_test.dart -r expanded` | Wave 0 |
| FOG-04 | `FogLayer` mounts inside `FlutterMap.children` and is wrapped by `MobileLayerTransformer` ancestor | widget | `flutter test test/presentation/widgets/fog_layer_test.dart -r expanded` | Wave 0 |
| FOG-05 | `FogShaderUniforms.setAll` populates exactly 41 float slots + 1 sampler (slot count assertion) | unit | `flutter test test/infrastructure/mirk/shader/fog_shader_uniforms_test.dart -r expanded` | Wave 0 (slot-count assertion) |
| FOG-05 | `FogShaderUniforms.totalFloatSlots == 41` (static assertion against `.frag` declaration) | unit | (covered above) | Wave 0 |
| FOG-06 | `computeFogClipPath` returns world rect minus disc circles in screen coordinates | unit | `flutter test test/presentation/widgets/fog_clip_path_test.dart -r expanded` | Wave 0 |
| FOG-07 | Single-`MapCamera`-snapshot invariant: SDF rect, clip path, shader uniforms, viewport size all derive from same `MapCamera` instance per build | widget (camera-injection seam) | `flutter test test/presentation/widgets/fog_layer_camera_snapshot_test.dart -r expanded` | Wave 0 |
| FOG-08 | Frame-delta probe rollup correctness: given synthetic per-frame deltas, emits correct `medianMs`/`p95Ms`/`maxMs` JSONL | unit | `flutter test test/infrastructure/mirk/frame_delta_probe_test.dart -r expanded` | Wave 0 |
| FOG-08 | Frame-delta probe rejects non-monotonic timestamps (Stopwatch sanity check) | unit | (covered in probe test) | Wave 0 |
| PERF-03 | iPhone 17 Pro pan-FPS with fog ≥ 30; idle-fog-animation FPS ≥ 50 | manual-only (UAT walk) | sideload + walk on iPhone 17 Pro | manual gate |
| PERF-04 | Frame-delta probe median ≤16 ms / p95 ≤32 ms / max ≤48 ms across ≥10 combined gestures | manual-only (UAT walk) | sideload + walk + JSONL grep | manual gate |
| PERF-05 | Subjective verdict: no fog slip / white-ellipse / reveal-hole lag / inversion | manual-only (UAT walk) | developer's verbal `approved` | manual gate |
| Pre-walk shader-sanity gate | `/sanity` route renders fog with hardcoded uniforms; circular reveal hole visible; no FileLogger exceptions | manual-only (sideload smoke) | sideload IPA, navigate to `/sanity`, observe | manual gate |

**Manual-only justifications:** PERF-03/04/05 inherently require a real iPhone 17 Pro at outdoor GPS coordinates (Melun) with the developer's hand performing combined gestures. No automation reasonably substitutes. The pre-walk shader-sanity smoke is manual because (a) the POC has no `flutter_test` golden infrastructure and (b) it's a single screen, single frame — visual confirmation by the developer is faster and cheaper than building a golden harness for one shot.

### Sampling Rate

- **Per task commit:** `flutter test test/{paths added by the task} -r expanded` (≤30 seconds for the per-task subset)
- **Per wave merge:** `flutter test` (full suite — ≤60 seconds total at Phase 3 scale; baseline is ~5 s pre-Phase-3)
- **Phase gate:** Full suite green + `flutter analyze` zero warnings + `dart format --line-length 160 --set-exit-if-changed .` clean + LOC-03 / BOOT-02 CI gates green + manual UAT gates above before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/presentation/widgets/fog_layer_test.dart` — covers FOG-04 (MobileLayerTransformer ancestor)
- [ ] `test/presentation/widgets/fog_layer_camera_snapshot_test.dart` — covers FOG-07 (single-MapCamera invariant; THE KEY TEST per CONTEXT.md)
- [ ] `test/presentation/widgets/fog_clip_path_test.dart` — covers FOG-06 (clip-path geometry)
- [ ] `test/domain/revealed/reveal_disc_repository_test.dart` — covers FOG-01 (append / snapshot / ChangeNotifier semantics)
- [ ] `test/domain/revealed/distance_metres_test.dart` — covers FOG-02 defence (`distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km` regression test)
- [ ] `test/infrastructure/mirk/sdf/sdf_cache_test.dart` — covers FOG-03 cache hit/miss
- [ ] `test/infrastructure/mirk/sdf_rebuild_logger_test.dart` — covers FOG-03 logger rollup
- [ ] `test/infrastructure/mirk/shader/fog_shader_uniforms_test.dart` — covers FOG-05 slot count (`totalFloatSlots == 41`); existing donor test from BOOT-08 may already partially cover; verify and extend
- [ ] `test/infrastructure/mirk/frame_delta_probe_test.dart` — covers FOG-08 probe rollup correctness
- [ ] `test/presentation/screens/map_screen_fog_test.dart` — covers MapScreen integration: GPS fix → `discRepository.append`; `_fogShader` lifecycle; FogLayer mounting

**Test seams that need engineering:**
- **MapCamera test seam.** Mounting a `FogLayer` in a widget test without a real `FlutterMap` requires either (a) a parent that provides a fake `MapCamera` via the inherited-widget pattern, or (b) a full `pumpWidget(FlutterMap(... children: [FogLayer(...)]))`. (b) is closer to production behaviour but pulls in the tile-layer harness; (a) is faster and more focused. Planner picks one; recommend (a) for unit-style FogLayer tests + (b) for the camera-snapshot integration test.
- **FragmentShader test seam.** `ui.FragmentShader` is hard to instantiate in a test environment (the ShaderProgram needs a real GPU). Plan B: a `FogShaderRenderer` interface that wraps `setAll` calls; production impl delegates to `FogShaderUniforms.setAll`; test impl records the (slot-index, float-value) pairs into a list. Tests assert the recorded list contains exactly 41 floats + 1 sampler set, and that no `MapCamera` was re-read between calls.
- **Position-stream fake.** Phase 2 already established `_CapturingGeolocatorPlatform` as the test seam (Plan 02-03). Phase 3 reuses it for the GPS-fix-to-disc-append integration test.

**Framework install:** None needed — `flutter_test` is in the SDK and `test: 1.30.0` is already pinned.

## Sources

### Primary (HIGH confidence)
- [flutter_map MapCamera class API docs](https://pub.dev/documentation/flutter_map/latest/flutter_map/MapCamera-class.html) — `MapCamera.of(context)`, properties (center, zoom, rotation, visibleBounds, size, nonRotatedSize), methods (latLngToScreenOffset, screenOffsetToLatLng, projectAtZoom)
- [flutter_map Custom Layers docs](https://docs.fleaflet.dev/plugins/create/layers) — `MobileLayerTransformer` pattern, `MapCamera.of(context)` auto-subscribe semantics, layer-as-Widget rule
- [flutter_map Listen To Events docs](https://docs.fleaflet.dev/usage/programmatic-interaction/listen-to-events) — `MapController.mapEventStream` and `MapOptions.onMapEvent` (used by Phase 2 `MapCompass` already)
- [flutter_map 7.0.2 changelog](https://pub.dev/packages/flutter_map/versions/7.0.2/changelog) — `MapCamera.visibleBounds` antimeridian fix
- [Flutter Fragment Shaders official docs](https://docs.flutter.dev/ui/design/graphics/fragment-shaders) — `FragmentProgram.fromAsset`, `program.fragmentShader()`, `setFloat`, `setImageSampler`, `Paint()..shader = shader`, FlutterFragCoord, GLSL constraints, premultiplied alpha
- [Flutter SchedulerBinding.addTimingsCallback API docs](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html) — multi-listener safety, batching cadence (~100 ms profile/debug; ~1 s release), zero-overhead-when-unused property
- [Flutter FrameTiming API docs](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html) — vsyncStart, buildStart, buildFinish, rasterStart, rasterFinish, totalSpan, vsyncOverhead, buildDuration, rasterDuration
- [Flutter CustomPainter shouldRepaint + Listenable repaint API docs](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) — repaint argument bypasses build phase
- [Dart Stopwatch.elapsedMicroseconds API docs](https://api.flutter.dev/flutter/dart-core/Stopwatch-class.html) — monotonic clock, recommended over DateTime for elapsed time

### Secondary (MEDIUM confidence — verified against primary)
- [Flutter Shader Compilation Jank guide](https://docs.flutter.dev/perf/shader) — Impeller AOT compilation supersedes runtime Skia compilation
- [flutter_map MapCamera class member docs](https://pub.dev/documentation/flutter_map/latest/flutter_map/MapCamera-class.html) — confirms `MapCamera.of(context)` rebuilds the calling widget when camera changes (verified against the Custom Layers docs)
- [Flutter SchedulerBinding mixin API docs](https://api.flutter.dev/flutter/scheduler/SchedulerBinding-mixin.html) — Ticker / scheduleFrameCallback / handleBeginFrame phasing

### Tertiary (LOW confidence — flagged)
- A19 Pro / iPhone 17 Pro shader cost numbers — no first-party benchmark for 41-uniform fog shader specifically; relying on phase-1 verbal `approved` of 120 fps PERF-02 walk for general headroom and on Phase 3 walk to confirm. Documented as Open Question 1.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every package already pinned and Phase 1 + Phase 2 closed; flutter_map 7.0.2 + dart:ui FragmentProgram + scheduler.dart are the only blessed APIs and well-documented.
- Architecture (custom layer + MapCamera capture + FragmentShader reuse + FrameDeltaProbe): HIGH — primary docs cross-verified; pattern matches Phase 2 widgets (MapCompass, RecenterFab) for consistency.
- Pitfalls: HIGH — most are verbatim from CONTEXT.md locked decisions or from explicit BUG-014 history in the parent project's research; the timestamp-source pitfall is grounded in Stopwatch documentation.
- Validation Architecture: HIGH — every test file path concrete; existing `_CapturingGeolocatorPlatform` and `PermissionHandlerPlatform.instance` test seams from Phase 1/2 generalize cleanly.
- iPhone 17 Pro performance numbers (Open Question 1): MEDIUM — architectural reasoning only; the walk itself is the measurement.

**Research date:** 2026-05-01
**Valid until:** 2026-06-01 (30 days; flutter_map and Flutter SDK both stable; revisit if Flutter 3.42+ brings shader API changes)
