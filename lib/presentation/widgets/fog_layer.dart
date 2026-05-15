// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/shader/fog_shader_uniforms.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_transform_logger.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_clip_path.dart';

/// Abstraction over the 41-uniform + 1-sampler population step.
///
/// Production impl ([_FragmentShaderFogRenderer]) delegates to
/// `FogShaderUniforms.setAll(...)` — the locked single source of truth for
/// the 41-slot layout (BUG-009 / BUG-014 Iter 2 fix).
///
/// Widget tests inject `RecordingFogShaderRenderer` (test/_helpers) so
/// FOG-05 41-slot coverage can be asserted without a real
/// `ui.FragmentShader` (test envs have no GPU and
/// `FragmentProgram.fromAsset` fails without an asset bundle).
abstract class FogShaderRenderer {
  /// Populates uniforms on [shader] and binds the SDF sampler.
  ///
  /// [mirkFogConstants] carries every `kMirkFog*` numeric constant by named
  /// key so the test impl can record the exact float values without having
  /// to inspect the production code's hard-coded constant names.
  ///
  /// [zoomScale] (FOG-19 / Plan 03.1-14 Task B): `pow(2, camera.zoom -
  /// kPocFogReferenceZoom)` forwarded to the shader's slot 41 `uZoomScale`
  /// uniform. Anchors fog noise samples to lat/lng during zoom transitions
  /// (Q1b residual fix per Walk #5). At camera.zoom == kPocFogReferenceZoom
  /// (=13.0), zoomScale == 1.0 and shader noise sampling is bit-identical
  /// to the pre-FOG-19 formulation (MIRL visual-identity-preservation
  /// rule per CLAUDE.md `# MIRL solution` updated 2026-05-04).
  void render({
    required ui.FragmentShader? shader,
    required Size resolution,
    required double timeSeconds,
    required (double, double) pixelOrigin,
    required double baseAlpha,
    required (double, double, double, double) sdfRect,
    required ui.Image sdfImage,
    required Map<String, double> mirkFogConstants,
    required double zoomScale,
  });
}

/// Production renderer — delegates to the locked
/// [FogShaderUniforms.setAll] entry point. Const-constructable; FogLayer's
/// default constructor uses `const _FragmentShaderFogRenderer()` so callers
/// get the production path with zero ceremony.
class _FragmentShaderFogRenderer implements FogShaderRenderer {
  const _FragmentShaderFogRenderer();

  @override
  void render({
    required ui.FragmentShader? shader,
    required Size resolution,
    required double timeSeconds,
    required (double, double) pixelOrigin,
    required double baseAlpha,
    required (double, double, double, double) sdfRect,
    required ui.Image sdfImage,
    required Map<String, double> mirkFogConstants,
    required double zoomScale,
  }) {
    if (shader == null) return; // production never passes null; defensive guard.
    FogShaderUniforms.setAll(
      shader,
      resolution: resolution,
      time: timeSeconds,
      pixelOrigin: pixelOrigin,
      baseArgb: kMirkFogAtmosphericBaseColorArgb,
      baseAlpha: baseAlpha,
      highlightArgb: kMirkFogAtmosphericHighlightColorArgb,
      shadowArgb: kMirkFogAtmosphericShadowColorArgb,
      driftZFar: mirkFogConstants['driftZFar']!,
      driftZMid: mirkFogConstants['driftZMid']!,
      driftZNear: mirkFogConstants['driftZNear']!,
      scaleFar: mirkFogConstants['scaleFar']!,
      scaleMid: mirkFogConstants['scaleMid']!,
      scaleNear: mirkFogConstants['scaleNear']!,
      opacityFar: mirkFogConstants['opacityFar']!,
      opacityMid: mirkFogConstants['opacityMid']!,
      opacityNear: mirkFogConstants['opacityNear']!,
      curlAmplitude: mirkFogConstants['curlAmplitude']!,
      curlScale: mirkFogConstants['curlScale']!,
      lightDirRadians: mirkFogConstants['lightDirRadians']!,
      lightOffset: mirkFogConstants['lightOffset']!,
      lightStrength: mirkFogConstants['lightStrength']!,
      hueNoiseScale: mirkFogConstants['hueNoiseScale']!,
      hueStrength: mirkFogConstants['hueStrength']!,
      boundarySharpDistance: mirkFogConstants['boundarySharpDistance']!,
      boundaryBleedDistance: mirkFogConstants['boundaryBleedDistance']!,
      boundaryEdgeBand: mirkFogConstants['boundaryEdgeBand']!,
      boundaryDensityBoost: mirkFogConstants['boundaryDensityBoost']!,
      sdfRect: sdfRect,
      zoomScale: zoomScale,
      sdfImage: sdfImage,
    );
  }
}

/// Custom flutter_map layer painting `atmospheric_fog.frag` into the
/// same Canvas as the tile layer (FOG-04..07 architectural keystone +
/// FOG-08 frame-delta probe wire).
///
/// ## FOG-07 single-MapCamera-snapshot lock (KEYSTONE)
///
/// `MapCamera.of(context)` is called EXACTLY ONCE in [build]. The
/// returned [MapCamera] is captured into a final local and passed by
/// constructor to the painter. The painter NEVER re-reads context.
/// Re-reading would re-create BUG-014's white-ellipse symptom (clip
/// path computed at zoom Z, shader distance falloff at zoom Z+ε).
///
/// ## No RepaintBoundary (locked OUT per CONTEXT.md)
///
/// Wrapping FogLayer in `RepaintBoundary` would isolate it from the
/// tile layer's repaint signal, falling behind by exactly one frame —
/// effectively re-creating BUG-014 inside Flutter.
///
/// ## Per-frame uTime drift via Listenable repaint + LIVE Stopwatch
///
/// A `SingleTickerProviderStateMixin` Ticker fires per frame. The
/// internal [_Repaint] `ChangeNotifier` notifies listeners on each tick;
/// the [CustomPainter] takes `repaint: _repaint` so paint cycles run
/// without going through the build phase (RESEARCH §Pattern 1 +
/// Anti-pattern: setState in ticker callback).
///
/// CRITICAL: the painter receives the [Stopwatch] BY REFERENCE and
/// reads `_wallClock.elapsedMicroseconds` FRESH on every `paint()` call.
/// A frozen `uTimeSeconds: stopwatch.elapsedMicroseconds / 1e6` captured
/// at build time would freeze fog drift between rebuilds — failing
/// PERF-03's idle-fog-animation ≥ 50 fps gate (the shader's `uTime`
/// would never change while idle).
class FogLayer extends StatefulWidget {
  /// Constructs the fog layer. All non-test callers omit [shaderRenderer]
  /// and pick up the const production default.
  const FogLayer({
    super.key,
    required this.discRepository,
    required this.shader,
    required this.sdfCache,
    required this.frameDeltaProbe,
    required this.fogTransformLogger,
    required this.wispParticleSystem,
    required this.wispTransformLogger,
    this.shaderRenderer = const _FragmentShaderFogRenderer(),
  });

  /// Reveal-disc source — the layer subscribes via `addListener` and rebuilds
  /// when new discs land.
  final RevealDiscRepository discRepository;

  /// Pre-loaded `atmospheric_fog.frag` fragment shader.
  ///
  /// Nullable to support widget tests: `dart:ui`'s `FragmentShader` is a
  /// `base` class — it CANNOT be implemented from a test file. Tests inject
  /// `RecordingFogShaderRenderer` (which ignores the shader argument) and
  /// pass `null` here. Production callers ALWAYS pass a non-null shader; the
  /// painter's `_FragmentShaderFogRenderer` guards on null and bails early.
  final ui.FragmentShader? shader;

  /// SDF cache (FOG-03) — the layer queries `getOrBuild(discs, viewport)`
  /// and the resolved `ui.Image` is threaded into the painter.
  final SdfCache sdfCache;

  /// FOG-08 frame-delta probe — the layer calls
  /// `recordCameraSnapshot()` at the top of build and threads the returned
  /// snapshot timestamp into the painter, which calls
  /// `recordFogUniformPopulation(snap)` right before the renderer runs.
  final FrameDeltaProbe frameDeltaProbe;

  /// FOG-10 fog-transform diagnostic logger (Plan 03.1-01). The painter
  /// calls `recordPaint(...)` once per paint with `(canvas.getTransform(),
  /// camera.pixelOrigin, camera.center, appliedUOffset)`. Owned by the
  /// MapScreen lifetime; the layer just consumes the reference and forwards.
  final FogTransformLogger fogTransformLogger;

  /// WISP-01..05 (Plan 04-04) — wisp particle system. Owned by the
  /// MapScreen lifetime; threaded through to `_FogPainter` and consumed
  /// inside `_renderWisps` (additive-blend draw, after the fog drawRect,
  /// before canvas.restore — same canvas-translated frame, same clipPath).
  /// The painter calls `wispParticleSystem.advanceFromWallClock(...)` per
  /// paint to integrate physics; wisp positions stay in LatLng (WISP-01)
  /// and are projected via `camera.latLngToScreenPoint(...)` at paint time.
  final WispParticleSystem wispParticleSystem;

  /// WISP-05 (Plan 04-02 / 04-04) — wisp transform diagnostic logger
  /// (1-Hz JSONL via `Logger('infrastructure.mirk.wisp')`). Sibling to
  /// [fogTransformLogger]; the painter calls `recordPaint(...)` once per
  /// paint with the active-count + meanAge + lat/lon + screen-bounds +
  /// spawn-rate tuple. Owned by the MapScreen lifetime.
  final WispTransformLogger wispTransformLogger;

  /// Test seam — widget tests inject `RecordingFogShaderRenderer` to assert
  /// FOG-05 41-slot coverage without a real GPU. Production callers use the
  /// const default and never touch this.
  final FogShaderRenderer shaderRenderer;

  /// FOG-07 keystone test seam — invoked exactly once per build, right
  /// before `MapCamera.of(context)`. Tests count invocations to enforce
  /// the "exactly one read per build" invariant. Production: null.
  @visibleForTesting
  static void Function()? debugOnCameraRead;

  @override
  State<FogLayer> createState() => _FogLayerState();
}

class _FogLayerState extends State<FogLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// LIVE Stopwatch — passed BY REFERENCE to the painter so `paint()` reads
  /// `elapsedMicroseconds` afresh per frame. NEVER capture this as a frozen
  /// double at build time (would break PERF-03 idle-fog-animation gate).
  final Stopwatch _wallClockSinceMount = Stopwatch()..start();

  /// WISP-04 (Plan 04-04) — sibling LIVE Stopwatch for wisp dt derivation.
  /// Passed BY REFERENCE to the painter; `_renderWisps` forwards it into
  /// `WispParticleSystem.advanceFromWallClock(wispWallClock)` so each
  /// paint integrates the system over `dt = (currentMicros - lastMicros) /
  /// 1e6` clamped to [kMirkPocWispMaxDtSeconds] (Pitfall 6 — fresh dt
  /// per paint; a frozen Stopwatch would freeze wisp drift between paints).
  /// Separate from [_wallClockSinceMount] so the fog uTime stream and the
  /// wisp dt stream are independently observable in tests.
  final Stopwatch _wispWallClockSinceMount = Stopwatch()..start();

  /// Per-frame paint trigger fed by the [_ticker]. Painter takes this as its
  /// `repaint:` Listenable so paint cycles run without going through build.
  final _Repaint _repaint = _Repaint();

  /// Most recently resolved SDF image. Null on the very first frame before
  /// the cache future completes; the painter renders nothing while null
  /// (one-frame "no fog yet" at startup, < 1 ms at POC scale).
  ui.Image? _currentSdfImage;

  /// In-flight cache future. Held so a second `build()` does not kick off a
  /// second concurrent rebuild; the await chain converges via [_resolveSdfImage].
  Future<ui.Image>? _pendingSdfBuild;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _repaint.notifyListeners());
    _ticker.start();
    widget.discRepository.addListener(_onDiscsChanged);
  }

  void _onDiscsChanged() {
    if (!mounted) return;
    // Reset the SDF future so the next build picks up the new disc snapshot.
    _pendingSdfBuild = null;
    setState(() {});
  }

  @override
  void dispose() {
    widget.discRepository.removeListener(_onDiscsChanged);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  /// Map of every `kMirkFog*` numeric constant by name. The painter passes
  /// this through the [FogShaderRenderer] so the test impl can record exact
  /// values for FOG-05 41-slot coverage assertions. Static + final so it
  /// allocates once per process, not per build.
  static final Map<String, double> _mirkFogConstants = <String, double>{
    'driftZFar': kMirkFogAtmosphericDriftZFar,
    'driftZMid': kMirkFogAtmosphericDriftZMid,
    'driftZNear': kMirkFogAtmosphericDriftZNear,
    'scaleFar': kMirkFogAtmosphericScaleFar,
    'scaleMid': kMirkFogAtmosphericScaleMid,
    'scaleNear': kMirkFogAtmosphericScaleNear,
    'opacityFar': kMirkFogOpacityFar,
    'opacityMid': kMirkFogOpacityMid,
    'opacityNear': kMirkFogOpacityNear,
    'curlAmplitude': kMirkFogCurlAmplitude,
    'curlScale': kMirkFogCurlScale,
    'lightDirRadians': kMirkFogLightDirRadians,
    'lightOffset': kMirkFogLightOffset,
    'lightStrength': kMirkFogLightStrength,
    'hueNoiseScale': kMirkFogHueNoiseScale,
    'hueStrength': kMirkFogHueStrength,
    'boundarySharpDistance': kMirkFogBoundarySharpDistance,
    'boundaryBleedDistance': kMirkFogBoundaryBleedDistance,
    'boundaryEdgeBand': kMirkFogBoundaryEdgeBand,
    'boundaryDensityBoost': kMirkFogBoundaryDensityBoost,
  };

  @override
  Widget build(BuildContext context) {
    // FOG-07 LOCK — exactly one MapCamera.of(context) read per build.
    FogLayer.debugOnCameraRead?.call();
    final MapCamera camera = MapCamera.of(context);
    final discs = widget.discRepository.snapshot();

    // FOG-08 build-side wire — capture probe snapshot RIGHT after the camera read.
    final cameraSnapshotMicros = widget.frameDeltaProbe.recordCameraSnapshot();

    // Kick off (or hit) the SDF cache. Future completion updates
    // _currentSdfImage; the painter reads whatever's most-recent.
    final viewport = _viewportFromCamera(camera);
    _pendingSdfBuild ??= _resolveSdfImage(discs, viewport);

    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _FogPainter(
          camera: camera,
          discs: discs,
          shader: widget.shader,
          wallClock: _wallClockSinceMount, // BY REFERENCE — painter reads elapsedMicroseconds per paint call.
          shaderRenderer: widget.shaderRenderer,
          mirkFogConstants: _mirkFogConstants,
          frameDeltaProbe: widget.frameDeltaProbe,
          fogTransformLogger: widget.fogTransformLogger,
          cameraSnapshotMicros: cameraSnapshotMicros,
          sdfImage: _currentSdfImage,
          wispParticleSystem: widget.wispParticleSystem,
          wispTransformLogger: widget.wispTransformLogger,
          wispWallClock: _wispWallClockSinceMount, // BY REFERENCE — painter forwards into advanceFromWallClock per paint.
          repaint: _repaint,
        ),
        size: Size.infinite,
      ),
    );
  }

  Future<ui.Image> _resolveSdfImage(List<RevealDisc> discs, MirkViewportBbox viewport) async {
    final image = await widget.sdfCache.getOrBuild(discs: discs, viewport: viewport);
    if (!mounted) return image;
    setState(() {
      _currentSdfImage = image;
      _pendingSdfBuild = null;
    });
    return image;
  }

  /// Projects `camera.visibleBounds` into a [MirkViewportBbox].
  ///
  /// flutter_map 7.0.2 RESOLVED API (verified against
  /// `~/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_map-7.0.2/lib/src/geo/latlng_bounds.dart`
  /// lines 22-31): `LatLngBounds` exposes `north`, `south`, `east`, `west`
  /// as PUBLIC MUTABLE DOUBLE FIELDS — direct field access, no method calls.
  MirkViewportBbox _viewportFromCamera(MapCamera camera) {
    final bounds = camera.visibleBounds;
    return MirkViewportBbox(south: bounds.south, west: bounds.west, north: bounds.north, east: bounds.east);
  }
}

/// Per-frame paint trigger. The Ticker calls `notifyListeners()` once per
/// frame; the painter takes this as its `repaint:` Listenable so paint
/// cycles bypass build (RESEARCH §Pattern 1).
class _Repaint extends ChangeNotifier {
  // notifyListeners is protected by default; expose via a thin override so
  // the surrounding state class can fire it from the Ticker callback.
  @override
  void notifyListeners() => super.notifyListeners();
}

class _FogPainter extends CustomPainter {
  _FogPainter({
    required this.camera,
    required this.discs,
    required this.shader,
    required this.wallClock,
    required this.shaderRenderer,
    required this.mirkFogConstants,
    required this.frameDeltaProbe,
    required this.fogTransformLogger,
    required this.cameraSnapshotMicros,
    required this.sdfImage,
    required this.wispParticleSystem,
    required this.wispTransformLogger,
    required this.wispWallClock,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final MapCamera camera;
  final List<RevealDisc> discs;

  /// Nullable for the same reason as [FogLayer.shader] — widget tests can
  /// pass `null` because `RecordingFogShaderRenderer` ignores the shader
  /// argument. Production: never null; the painter still guards before
  /// calling `canvas.drawRect(..., Paint()..shader = shader)`.
  final ui.FragmentShader? shader;

  /// Live wall-clock — read fresh per `paint()` call. Anti-frozen-uTime
  /// invariant (PERF-03 idle-fog-animation gate).
  final Stopwatch wallClock;

  final FogShaderRenderer shaderRenderer;
  final Map<String, double> mirkFogConstants;
  final FrameDeltaProbe frameDeltaProbe;
  final FogTransformLogger fogTransformLogger;
  final int cameraSnapshotMicros;
  final ui.Image? sdfImage;

  /// WISP-01..05 — owned by MapScreen lifetime; passed by reference. The
  /// painter calls `advanceFromWallClock` + iterates `.wisps` + records
  /// per-paint diagnostics. Constructor injection mirrors FOG-07 discipline
  /// (no global state, no `MapCamera.of` leaks).
  final WispParticleSystem wispParticleSystem;

  /// WISP-05 — wisp-side equivalent of [fogTransformLogger]. The painter
  /// emits one `recordPaint(...)` call per paint with the active-count +
  /// meanAge + bounds + spawn-rate tuple.
  final WispTransformLogger wispTransformLogger;

  /// LIVE Stopwatch — passed BY REFERENCE so the per-paint dt derivation
  /// reads `elapsedMicroseconds` afresh per paint (Pitfall 6 prevention —
  /// frozen dt would freeze wisp drift). Sibling to [wallClock] which
  /// serves the same role for fog uTime. The painter forwards this into
  /// `wispParticleSystem.advanceFromWallClock(wispWallClock)`; the
  /// system internally tracks `_lastAdvanceMicros` and clamps dt to
  /// [kMirkPocWispMaxDtSeconds].
  final Stopwatch wispWallClock;

  @override
  void paint(Canvas canvas, Size size) {
    if (sdfImage == null) {
      // First frames before the cache resolves — paint nothing. The cache
      // resolves within ~1 ms at POC scale; the user perceives a barely-
      // visible "no fog yet" frame at startup.
      return;
    }

    // CRITICAL: read uTime LIVE from the Stopwatch on every paint call.
    // A frozen value captured at build time would freeze fog drift between
    // rebuilds (PERF-03 idle-fog-animation gate fails — shader's uTime
    // never advances while idle).
    final uTimeSeconds = wallClock.elapsedMicroseconds / _microsecondsPerSecond;

    // CANVAS-FRAME-ALIGNMENT (Plan 03.1-05 + Plan 03.1-08 + Plan 03.1-08-FIX) —
    // read the local Canvas transform ONCE per paint, then translate the
    // canvas to the world (identity) frame BEFORE any clip / draw operation.
    // Per 03.1-FALSIFICATION.md Finding 1, MobileLayerTransformer applies a
    // non-zero Canvas-level translation under conditions Plan 03-08 and Plan
    // 03.1-02 did not anticipate (canvasTx/Ty jumps to (5.035, -44.198)
    // mid-session and HOLDS, then up to (+757.35, +319.46) sustained for ~50
    // sec in Walk #2). Pre-Plan-03.1-05 the SDF reveal frame and the blue-dot
    // CircleLayer frame ended up in different Canvas frames — the reveal hole
    // offset from the blue dot during gesture (observation 4).
    //
    // Single-snapshot read discipline mirrors FOG-07 (camera) at the matrix
    // level — re-reading `canvas.getTransform()` would re-introduce a
    // multi-snapshot anti-pattern. The same Float64List is reused for both
    // the canvas-translate compensation AND the fogTransformLogger emission.
    //
    // Plan 03.1-08-FIX (post-Walk-#2-rebuild observation): the original
    // Plan 03.1-08 placed `canvas.translate(-canvasOffset)` AFTER `clipPath`
    // AND retained the Plan 03.1-05 `-canvasOffset` shift inside
    // `computeFogClipPath(...)`. That double-compensated the reveal hole
    // during pan/zoom — the user observed "the revealed area is also
    // offsetting itself during pan/zoom" on build 8a37bfd, re-introducing
    // Walk #1 obs 4 with a worsened severity. The correct architecture (per
    // Plan 03.1-08's locked design) is: translate the canvas ONCE at the
    // top of paint() so the entire painter operates in the world (identity)
    // frame; compute the clip path in raw world coordinates (no
    // canvasOffset shift); draw the rect at (Offset.zero & size) — which
    // now lands at the world-frame origin because the canvas is already
    // pre-translated. Clean single-frame discipline; no compensation
    // composition fragility.
    final canvasTransform = canvas.getTransform();
    final canvasOffset = Offset(canvasTransform[_canvasTransformTxIndex], canvasTransform[_canvasTransformTyIndex]);

    canvas.save();
    // Translate to world (identity) frame BEFORE any clip / draw. After this
    // line, the canvas is at the same frame the sibling blue-dot CircleLayer
    // renders in (its UNTRANSLATED Canvas — flutter_map's CircleLayer is not
    // wrapped by MobileLayerTransformer). All subsequent geometry —
    // clip path, draw rect — uses raw world coordinates.
    canvas.translate(-canvasOffset.dx, -canvasOffset.dy);

    // Clip path is computed in WORLD coordinates because the canvas is now
    // at the world (identity) frame. The Plan 03.1-05 `-canvasOffset` shift
    // was designed for a paint() body that NEVER translated the canvas;
    // since Plan 03.1-08 the canvas IS translated, so the shift becomes a
    // double-compensation that re-creates Walk #1 obs 4. Pass
    // `canvasOffset: Offset.zero` (the default) to opt out of the shift.
    final clipPath = computeFogClipPath(camera: camera, discs: discs);
    canvas.clipPath(clipPath);

    // FOG-08 paint-side wire — populate AFTER the camera was captured (in build),
    // RIGHT BEFORE the renderer runs. Single-source-of-truth is the
    // cameraSnapshotMicros captured in build() — re-reading from probe
    // here would re-introduce the multi-snapshot anti-pattern.
    frameDeltaProbe.recordFogUniformPopulation(cameraSnapshotMicros);

    // FIX (Plan 03.1-04, layered on Plan 03.1-02) — forward FULL-PRECISION
    // pixelOrigin to the shader; the shader applies `fract()` per-fragment.
    //
    // Plan 03.1-02 derived `(uOffsetX, uOffsetY) = (pixelOrigin.x / size.width) % 1.0`
    // at this Dart call site. Per 03.1-FALSIFICATION.md Finding 3, the modulo wrap at
    // ~120 Hz produced visible single-frame discontinuities (uOffsetX sweeping
    // 0.005..0.99 5-10× per 1-Hz rollup during gesture) — the developer's
    // "seed of the mirk was changing" failure mode (observation 2).
    //
    // The fix: pass full-precision pixelOrigin to the shader; rename the
    // uniform to uPixelOrigin (slot 3..4 unchanged); apply `fract()`
    // per-fragment inside the fragment shader so each pixel's noise sample
    // coordinate is continuous across paints.
    //
    // FOG-07 single-snapshot invariant preserved: this consumes the painter's
    // existing `camera` field (passed by FogLayer.build from the same
    // MapCamera.of(context) read).
    // FOG-21 (Pixel 4a SDF V-origin fix, 2026-05-15) — Android Impeller
    // backend samples ui.Image textures V-up while iOS Impeller-Metal samples
    // V-down (canonical). The fix flips sdfUv.y on Android by passing dynamic
    // uSdfRect values: with origin.y=1 and size.y=-1, the shader's existing
    // `sdfUv.y = (fragUv.y - origin.y) / size.y` collapses to `1 - fragUv.y`,
    // cancelling the hardware V-flip. The clamp afterwards keeps sdfUv.y in
    // [0,1].
    //
    // Why dynamic uSdfRect VALUES are safe here: BUG-014 was about Impeller-
    // Metal SPIR-V → MSL transpilation reordering vec4 COMPONENTS when a
    // sampler2D sits adjacent in the declaration. The Plan 03-08 follow-up
    // decomposed uSdfRect into four INDEPENDENT scalar slots (37, 38, 39,
    // 40) precisely to eliminate that reordering risk — with each component
    // bound to a distinct slot, there is no vec4 to reinterpret. Changing
    // the VALUES of those independent slots cannot re-introduce BUG-014.
    // iOS values stay at (0,0,1,1) — render path byte-identical to f332fb5.
    //
    // The alternative (adding a new uniform `uSdfVFlip` at slot 42) was
    // tried in the prior FOG-21 iteration and BROKE Impeller-Metal: adding
    // ANY new uniform near the SDF sampler appears to corrupt MSL
    // transpilation in a way that prevents the shader from rendering. The
    // dynamic uSdfRect approach avoids the issue by keeping the binary
    // layout at exactly 42 floats + 1 sampler.
    // FOG-18 (Plan 03.1-12) — direct pixelOrigin forwarding (FOG-17a
    // wrap eliminated).
    //
    // FOG-17a (Plan 03.1-10) introduced a Dart-side modulo wrap (period
    // = 1536 raw px = 4 × kPocFogNoiseTilePx) on top of the
    // integer/fractional decomposition to keep shader input bounded
    // under ~1537 raw px regardless of zoom — the design assumed the
    // noise function was truly periodic on `kPocFogNoiseTilePx (=384)`,
    // so the wrap event would land at an exact noise-grid-period
    // multiple and be visually invisible.
    //
    // **Walk #4 (P03.1-11 2026-05-04) falsified that premise.** The
    // debug-spiral positive control (digit-atlas cells that ARE truly
    // periodic on 384) showed ZERO steppiness during max-zoom pan,
    // while the production fog showed a visible "SNAP" at every wrap
    // event at max zoom. Conclusion: the FBM-rotated-octave noise
    // function is NOT periodic on the noise-tile period in practice —
    // the wrap event ITSELF was the bug, not the precision penalty
    // FOG-17a was designed to address.
    //
    // FOG-18 fix: forward `camera.pixelOrigin` directly. fp32 has 24
    // bits of exact-integer mantissa = 16.7M raw-px ceiling, well
    // above Walk #4's max observed `pixelOriginX` of ~4.26M. Sub-pixel
    // ULP at 4.26M is ≈ 0.5 raw px; the noise function's per-fragment
    // sampling is robust to this magnitude of jitter (the visible SNAP
    // at the wrap was orders of magnitude larger than the precision
    // penalty FOG-17a hypothesized).
    //
    // The `truncateToDouble` integer/fractional decomposition is
    // RETAINED for documentation continuity — the split is a no-op
    // recomposition (intPx + fracPx == pxOrigin within fp32) but the
    // structure is preserved in case a future C2' follow-up plan re-
    // introduces a basis derivation that uses the decomposition. See
    // `03.1-12-PLAN.md` `<scope_note>` for the C2' deferral rationale
    // (refZoom-px basis vs screen-px uResolution dimensional mismatch
    // — needs `/gsd:discuss-phase 3.1` to resolve).
    //
    // The fogTransformLogger continues to forward `appliedUOffset` =
    // the forwarded value (post-FOG-18 = `camera.pixelOrigin` exactly)
    // so post-walk JSONL grep verifies the wrap is gone (`uOffsetXMax`
    // values will track raw `pixelOriginX` magnitudes — millions at
    // zoom 13+ — instead of being bounded under 1537).
    final pixOrigin = camera.pixelOrigin;
    final intPxX = pixOrigin.x.truncateToDouble();
    final intPxY = pixOrigin.y.truncateToDouble();
    final fracPxX = pixOrigin.x - intPxX;
    final fracPxY = pixOrigin.y - intPxY;
    // FOG-18: no modulo. boundedX/Y semantically == pxOrigin.x/y
    // exactly (the recomposition is bit-stable in fp32 since intPx is
    // produced by truncateToDouble of pxOrigin and fracPx is the
    // matching residual; intPx + fracPx == pxOrigin).
    final boundedX = intPxX + fracPxX;
    final boundedY = intPxY + fracPxY;
    // FOG-23 (Pixel 4a noise direction fix, 2026-05-15) — sign-flip
    // pixelOrigin.y on Android to cancel a GPU-codegen-level Y-inversion
    // of the noise pan response, confirmed by the FOG-22 horizontal-
    // stripe probe (same worldPx the noise samples from; on Android the
    // stripes drift opposite the basemap during pan). Every Dart-side
    // value is platform-identical per the fog_transform rollups
    // (canvasSx=Sy=1.0, shear=0, pixelOrigin evolves consistently with
    // centerLat, uResolution positive, zoom matches) and FlutterFragCoord
    // is Y-down on both platforms (proven by the earlier diagnostic
    // walk's red-top / blue-bottom result). With every input verified
    // identical, the only place left for the inversion is the impellerc
    // → Vulkan/SPIR-V codegen of `worldPx.y = fragCoord.y +
    // uPixelOrigin.y` effectively becoming `fragCoord.y - uPixelOrigin.y`
    // on Adreno-Vulkan but not on Apple-Metal. Passing -boundedY to slot
    // 4 double-inverts the codegen bug back to correct on Android. iOS
    // gets the canonical positive value → render path byte-identical to
    // f332fb5. Dart-only change, no shader edit, no new uniforms (the
    // previous three uniform-add attempts each broke Impeller-Metal).
    final appliedPixelOrigin = Platform.isAndroid ? (boundedX, -boundedY) : (boundedX, boundedY);

    // FOG-19 (Plan 03.1-14 Task B) — compute uZoomScale = pow(2,
    // camera.zoom - kPocFogReferenceZoom). Anchors fog noise samples
    // to lat/lng so cells stay PUT during zoom transitions (Q1b
    // residual fix per Walk #5 developer verbatim "numbers sliding /
    // incorrect scaling"). At camera.zoom == kPocFogReferenceZoom,
    // uZoomScale = 1.0 and shader sampling is bit-identical to pre-fix
    // (MIRL visual-identity-preservation rule per CLAUDE.md
    // `# MIRL solution` updated 2026-05-04).
    final uZoomScale = math.pow(2.0, camera.zoom - kPocFogReferenceZoom).toDouble();

    // FOG-10 diagnostic capture — record AFTER the derivation but BEFORE the
    // shader call so the logged tuple is the actual value forwarded.
    // canvas.getTransform() is native-backed in Flutter 3.41.7 (sky_engine
    // painting.dart line 6436).
    //
    // The `appliedUOffset` parameter NAME is preserved for back-compat with
    // the 03.1-03 walk's session log JSONL keys (uOffsetXMin/Median/Max,
    // uOffsetYMin/Median/Max). The VALUE forwarded is now full-precision
    // pixelOrigin (zoom-13 ~1e6, zoom-15+ ~4e6) instead of the modulo-1.0
    // fraction (0..1); post-walk grep tooling reads the higher magnitude
    // directly without any key rename.
    //
    // FOG-21 noise-direction diagnostics — capture the canvas transform's
    // scale + shear components, the uResolution size, and the camera zoom
    // alongside the existing translation/origin/center fields. Localises
    // whether MobileLayerTransformer is applying anything beyond pure
    // translation on Android (a non-1.0 sx/sy or non-0.0 shear would
    // explain a Y-inverted shader output independent of the SDF V-origin).
    fogTransformLogger.recordPaint(
      canvasTransform: canvasTransform, // ← Plan 03.1-05: reuse the single allocation from above (single-snapshot at the matrix level).
      cameraPixelOrigin: pixOrigin,
      cameraCenter: camera.center,
      appliedUOffset: appliedPixelOrigin,
      canvasSx: canvasTransform[0],
      canvasSy: canvasTransform[5],
      canvasShearYX: canvasTransform[1],
      canvasShearXY: canvasTransform[4],
      uResolutionX: size.width,
      uResolutionY: size.height,
      zoom: camera.zoom,
    );

    // FOG-05: populate all 41 uniforms via the locked single source of truth
    // (FogShaderUniforms.setAll — production impl) OR record them
    // (RecordingFogShaderRenderer — widget test impl). Identity uSdfRect
    // is non-negotiable per CONTEXT.md / RESEARCH §Anti-Pattern 1.
    shaderRenderer.render(
      shader: shader,
      resolution: size,
      timeSeconds: uTimeSeconds,
      pixelOrigin: appliedPixelOrigin, // ← Plan 03.1-04 — full-precision; shader applies `fract()` per-fragment.
      baseAlpha: 1.0,
      sdfRect: Platform.isAndroid
          ? const (0.0, 1.0, 1.0, -1.0) // Android — see comment above
          : const (0.0, 0.0, 1.0, 1.0), // iOS / Impeller-Metal — identity (canonical V-down).
      sdfImage: sdfImage!,
      mirkFogConstants: mirkFogConstants,
      zoomScale: uZoomScale, // ← FOG-19 (Plan 03.1-14 Task B) — anchors noise to lat/lng during zoom.
    );

    // Production-only paint step: drawing the shader onto the canvas requires
    // a non-null FragmentShader. Widget tests pass a null shader (FragmentShader
    // is dart:ui-base, can't be subclassed in a test file) and rely on the
    // recording renderer to assert behavioural coverage.
    final liveShader = shader;
    if (liveShader != null) {
      canvas.drawRect(Offset.zero & size, Paint()..shader = liveShader);
    }

    // WISP-04 (Plan 04-04) — wisp render slot. Inside the same canvas.save /
    // canvas.restore as the fog draw; consumes THE camera snapshot (FOG-07
    // single-snapshot invariant); inside the FOG-13 canvas-translated frame;
    // inside the FOG-12 clipPath. The cross-pipeline parity check completes
    // here: `camera.latLngToScreenPoint(w.position)` is the SAME call site
    // as `fog_clip_path.dart` line 83 (used to project SDF reveal-hole
    // centres). If wisps render correctly through this projection, the
    // wisp pipeline inherits the FOG-07 keystone for free.
    _renderWisps(canvas, camera);

    canvas.restore();
  }

  /// Renders every active wisp as an additive-blended soft circle on top of
  /// the fog. Called LAST inside paint()'s save/restore block.
  ///
  /// ## Shader-agnosticism (CONTEXT §Shader-agnosticism — POC requirement)
  ///
  /// Wisps depend ONLY on [MapCamera.latLngToScreenPoint], `canvas.drawCircle`
  /// + `Paint`, the fog clipPath, and the painter's identity-frame
  /// discipline. Wisps do NOT reference `uPixelOrigin`, `uZoomScale`,
  /// `uTime`, [FogShaderUniforms], `atmospheric_fog*`, or any other
  /// fog-shader-specific symbol. Swapping the production fog shader for a
  /// different shader (or none at all) leaves the wisp pipeline behaviour
  /// unchanged. This is the keystone the POC needs because the real app
  /// will use multiple, non-periodic shaders (CLAUDE.md `# MIRL solution`
  /// + `# MIRK solution` — shader-agnostic wisp layer).
  ///
  /// ## Per-paint dt encapsulation
  ///
  /// The painter does NOT compute `dt` itself; it forwards [wispWallClock]
  /// (live Stopwatch by reference) into
  /// [WispParticleSystem.advanceFromWallClock]. The system internally
  /// tracks `_lastAdvanceMicros`, computes the per-paint dt clamped to
  /// [kMirkPocWispMaxDtSeconds], and integrates physics. Encapsulation
  /// keeps the painter declarative.
  ///
  /// ## Early return on empty system
  ///
  /// If [WispParticleSystem.activeCount] is zero (warmup gate active OR
  /// every wisp aged out OR the user just navigated to the map and no fix
  /// has arrived), this method does NOTHING — no Paint allocation, no
  /// pxPerMetre derivation, no logger emission. The fog draw above is the
  /// only paint cost on an idle / pre-warmup screen.
  ///
  /// ## Per-wisp draw
  ///
  /// 1. Project `wisp.position` (LatLng) → screen Offset via
  ///    `camera.latLngToScreenPoint` (FOG-07 single-snapshot keystone).
  /// 2. Resolve the visual radius via [_resolveWispRadius] which branches
  ///    on [kMirkPocWispRadiusBasis] (screenPx vs meters basis — A/B
  ///    comparison axis per CONTEXT §Implementation Decisions Radius basis).
  /// 3. Compute the alpha-fade curve `1 - age²` × peakAlpha × tint.a.
  /// 4. drawCircle on the additive-blend Paint hoisted outside the loop.
  ///
  /// ## Diagnostic emission
  ///
  /// Once per paint, after the loop, calls
  /// [WispTransformLogger.recordPaint] with the accumulated active-count +
  /// meanAge + lat/lon + screen-bounds + spawn-rate tuple (Pitfall 3 —
  /// single emission per paint, NOT per wisp).
  void _renderWisps(Canvas canvas, MapCamera camera) {
    // 1. Integrate the wisp system forward. dt encapsulation lives in
    //    WispParticleSystem.advanceFromWallClock — first call no-op; subsequent
    //    calls integrate dt clamped to kMirkPocWispMaxDtSeconds.
    wispParticleSystem.advanceFromWallClock(wispWallClock);

    // 2. Early return on empty system — Pitfall 3 (zero allocations on
    //    idle / pre-warmup paints).
    if (wispParticleSystem.activeCount == 0) return;

    // 3. Hoist Paint outside the per-wisp loop (Pitfall 3). Additive blend so
    //    wisps brighten the fog without saturating; the tint ARGB is decoded
    //    once into individual r/g/b/a slots so the per-wisp Paint mutation
    //    only updates `color` (cheaper than re-decoding).
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus;
    const tintRed = (kMirkPocWispTintArgb >> _wispTintRedShift) & _wispTintByteMask;
    const tintGreen = (kMirkPocWispTintArgb >> _wispTintGreenShift) & _wispTintByteMask;
    const tintBlue = kMirkPocWispTintArgb & _wispTintByteMask;
    const tintAlpha = (kMirkPocWispTintArgb >> _wispTintAlphaShift) & _wispTintByteMask;
    const tintAlphaUnit = tintAlpha / _wispTintByteMaxValue;

    // 4. pxPerMetre derivation — used by _resolveWispRadius's meters branch
    //    (the A/B comparison axis per CONTEXT §Implementation Decisions).
    //    Derived ONCE per paint via a 1e-4° lat probe (~11 m at any latitude;
    //    safely within fp32 precision); cosmetic-only.
    final pxPerMetre = _derivePxPerMetre(camera);

    // 5. Per-wisp loop with bounds accumulation for WispTransformLogger.
    var latMin = double.infinity;
    var latMax = double.negativeInfinity;
    var lonMin = double.infinity;
    var lonMax = double.negativeInfinity;
    var screenXMin = double.infinity;
    var screenXMax = double.negativeInfinity;
    var screenYMin = double.infinity;
    var screenYMax = double.negativeInfinity;
    var meanAgeAccumulator = 0.0;
    var meanAgeCount = 0;

    for (final wisp in wispParticleSystem.wisps) {
      final age = wisp.age;
      final radius = _resolveWispRadius(age, pxPerMetre);

      // Alpha curve: `1 - age²` ramps quickly from 1.0 at birth to 0.0 at
      // death. Multiplied by peakAlpha (cosmetic ceiling) × tint.a (so a
      // tint with alpha < 0xFF lowers the global wisp brightness).
      final alphaFactor = (1.0 - age * age).clamp(0.0, 1.0);
      final wispAlpha = alphaFactor * kMirkPocWispPeakAlpha * tintAlphaUnit;
      paint.color = Color.fromARGB((wispAlpha * _wispTintByteMaxValue).round(), tintRed, tintGreen, tintBlue);

      // Project LatLng → screen via THE camera snapshot (FOG-07 keystone +
      // cross-pipeline parity with `fog_clip_path.dart:83`).
      final screenPt = camera.latLngToScreenPoint(wisp.position);
      final screenOffset = Offset(screenPt.x, screenPt.y);
      canvas.drawCircle(screenOffset, radius, paint);

      // Bounds accumulation for WispTransformLogger.recordPaint.
      final wispLat = wisp.position.latitude;
      final wispLon = wisp.position.longitude;
      if (wispLat < latMin) latMin = wispLat;
      if (wispLat > latMax) latMax = wispLat;
      if (wispLon < lonMin) lonMin = wispLon;
      if (wispLon > lonMax) lonMax = wispLon;
      if (screenPt.x < screenXMin) screenXMin = screenPt.x;
      if (screenPt.x > screenXMax) screenXMax = screenPt.x;
      if (screenPt.y < screenYMin) screenYMin = screenPt.y;
      if (screenPt.y > screenYMax) screenYMax = screenPt.y;
      meanAgeAccumulator += age;
      meanAgeCount += 1;
    }

    final meanAge = meanAgeCount > 0 ? meanAgeAccumulator / meanAgeCount : 0.0;
    wispTransformLogger.recordPaint(
      activeCount: wispParticleSystem.activeCount,
      meanAge: meanAge,
      latBounds: (latMin, latMax),
      lonBounds: (lonMin, lonMax),
      screenXBounds: (screenXMin, screenXMax),
      screenYBounds: (screenYMin, screenYMax),
      spawnRatePerSecond: wispParticleSystem.spawnRatePerSecondAndReset(),
    );
  }

  /// Resolves the visual radius for a wisp at normalised [age] (0 = just
  /// born, 1 = about to die). Branches on [kMirkPocWispRadiusBasis]:
  ///
  ///   * [WispRadiusBasis.screenPx] (production default) — interpolation
  ///     between [kMirkPocWispBirthRadiusPx] and [kMirkPocWispDeathRadiusPx]
  ///     in raw screen pixels. Visual character is zoom-invariant.
  ///   * [WispRadiusBasis.meters] (A/B comparison branch) — interpolation
  ///     in metres, converted to pixels via [pxPerMetre]. Wisps shrink at
  ///     high zoom and grow at low zoom (true ground-distance basis).
  ///
  /// CONTEXT §Implementation Decisions Radius basis: enum + paired
  /// constants — Plan 04-04 ships both branches functional so A/B
  /// comparison during walks is a single-constant flip.
  double _resolveWispRadius(double age, double pxPerMetre) {
    switch (kMirkPocWispRadiusBasis) {
      case WispRadiusBasis.screenPx:
        return kMirkPocWispBirthRadiusPx + (kMirkPocWispDeathRadiusPx - kMirkPocWispBirthRadiusPx) * age;
      case WispRadiusBasis.meters:
        final radiusInMetres = kMirkPocWispBirthRadiusMeters + (kMirkPocWispDeathRadiusMeters - kMirkPocWispBirthRadiusMeters) * age;
        return radiusInMetres * pxPerMetre;
    }
  }

  /// Derives pixels-per-metre at the camera's current zoom by sampling
  /// `camera.latLngToScreenPoint` over a 1e-4° lat probe (~11 m at any
  /// latitude; safely within fp32 precision). Used by [_resolveWispRadius]'s
  /// meters branch.
  ///
  /// Cosmetic-only — a small drift in the derivation does NOT affect wisp
  /// world-position correctness (positions stay in LatLng, projection is
  /// accurate). The derivation is identical in shape to the
  /// `pixelsPerMetre` helper inside `fog_clip_path.dart` lines 105-106; we
  /// inline a small probe here rather than depend on the helper to keep
  /// the cross-file coupling minimal.
  double _derivePxPerMetre(MapCamera camera) {
    final cameraCenter = camera.center;
    final pt0 = camera.latLngToScreenPoint(cameraCenter);
    final pt1 = camera.latLngToScreenPoint(LatLng(cameraCenter.latitude + _wispLatProbeDegrees, cameraCenter.longitude));
    final probeMetres = _wispLatProbeDegrees * kMetersPerDegreeLat;
    return (pt0.y - pt1.y).abs() / probeMetres;
  }

  @override
  bool shouldRepaint(_FogPainter oldDelegate) {
    // The Listenable `repaint:` argument drives per-frame redraws. shouldRepaint
    // gates whether a NEW painter instance triggers a paint. Compare on
    // identity of the camera + discs + sdfImage — anything else is a no-op repaint.
    //
    // Wisps are DELIBERATELY NOT in shouldRepaint (Pitfall 4). The
    // SingleTickerProviderStateMixin Ticker fires per frame and the
    // `_repaint` ChangeNotifier drives per-frame paints; wisp state
    // changes (new spawns, age decay, death) are picked up automatically
    // on the next paint without needing a `shouldRepaint` re-trigger.
    // Adding `!identical(oldDelegate.wispParticleSystem, wispParticleSystem)`
    // would be a cargo-cult addition: the system reference is stable for
    // the MapScreen lifetime; only its INTERNALS mutate, which the
    // shouldRepaint identity check would never catch anyway.
    return !identical(oldDelegate.camera, camera) || !identical(oldDelegate.discs, discs) || !identical(oldDelegate.sdfImage, sdfImage);
  }
}

/// `Stopwatch.elapsedMicroseconds → seconds` divisor. Hoisted so the magic
/// `1e6` doesn't appear inline in the `paint()` body's uTime line.
const double _microsecondsPerSecond = 1e6;

/// Column-major index of the `tx` translation component in a 4x4
/// Float64List matrix returned by `Canvas.getTransform()` (CANVAS-FRAME-
/// ALIGNMENT, Plan 03.1-05). dart:ui matrices follow the same column-major
/// convention as `vector_math.Matrix4`: `m[12]` = tx, `m[13]` = ty,
/// `m[14]` = tz.
const int _canvasTransformTxIndex = 12;
const int _canvasTransformTyIndex = 13;

// ─── Plan 04-04 wisp render — file-private constants ─────────────────────
// Hoisted out of `_renderWisps` so the magic numbers don't appear inline
// (CLAUDE.md "Aucun number magique"). All cosmetic; documented per piece.

/// Bit-shifts to decode the 32-bit ARGB `kMirkPocWispTintArgb` constant
/// into individual r/g/b/a byte slots. Standard 8-bit-per-channel layout:
/// `0xAARRGGBB` — alpha occupies bits 24..31, red 16..23, green 8..15,
/// blue 0..7.
const int _wispTintAlphaShift = 24;
const int _wispTintRedShift = 16;
const int _wispTintGreenShift = 8;

/// Mask for one byte (8 bits) when decoding ARGB channels.
const int _wispTintByteMask = 0xFF;

/// Maximum value of one ARGB byte channel (used to convert byte → unit
/// fraction and unit fraction → byte).
const double _wispTintByteMaxValue = 255.0;

/// Latitude-degree probe size for the pxPerMetre derivation in
/// [_FogPainter._derivePxPerMetre]. 1e-4° ≈ 11.132 m at any latitude;
/// small enough to be cosmetically accurate, large enough to be safely
/// within fp32 precision at any zoom (the screen-Y delta of two points
/// 1e-4° apart at zoom 15 is still > 1 raw px — the floor() noise
/// inside `latLngToScreenPoint` does not collapse to zero).
const double _wispLatProbeDegrees = 1e-4;
