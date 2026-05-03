// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/shader/fog_shader_uniforms.dart';
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
  void render({
    required ui.FragmentShader? shader,
    required Size resolution,
    required double timeSeconds,
    required (double, double) pixelOrigin,
    required double baseAlpha,
    required (double, double, double, double) sdfRect,
    required ui.Image sdfImage,
    required Map<String, double> mirkFogConstants,
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
    // Identity uSdfRect (slots 37..40 → const (0,0,1,1)) UNCHANGED — RESEARCH
    // §Anti-Pattern 1 (dynamic uSdfRect re-introduces BUG-014).
    final pixOrigin = camera.pixelOrigin;
    final appliedPixelOrigin = (pixOrigin.x, pixOrigin.y);

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
    fogTransformLogger.recordPaint(
      canvasTransform: canvasTransform, // ← Plan 03.1-05: reuse the single allocation from above (single-snapshot at the matrix level).
      cameraPixelOrigin: pixOrigin,
      cameraCenter: camera.center,
      appliedUOffset: appliedPixelOrigin,
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
      sdfRect: const (0.0, 0.0, 1.0, 1.0), // identity — UNCHANGED.
      sdfImage: sdfImage!,
      mirkFogConstants: mirkFogConstants,
    );

    // Production-only paint step: drawing the shader onto the canvas requires
    // a non-null FragmentShader. Widget tests pass a null shader (FragmentShader
    // is dart:ui-base, can't be subclassed in a test file) and rely on the
    // recording renderer to assert behavioural coverage.
    final liveShader = shader;
    if (liveShader != null) {
      canvas.drawRect(Offset.zero & size, Paint()..shader = liveShader);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FogPainter oldDelegate) {
    // The Listenable `repaint:` argument drives per-frame redraws. shouldRepaint
    // gates whether a NEW painter instance triggers a paint. Compare on
    // identity of the camera + discs + sdfImage — anything else is a no-op repaint.
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
