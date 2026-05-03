// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/revealed_sdf_builder.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/shader/digit_atlas_builder.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/shader/fog_shader_uniforms.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';

/// Synthetic-disc viewport bbox covering Melun town centre — the same lat
/// range used elsewhere in the project's Phase 2 + 3 spec. The bbox shape
/// doesn't have to be precise; the sanity screen tests the SDF→shader
/// path, not the camera projection.
const double _sanityViewportSouth = 48.50;
const double _sanityViewportWest = 2.60;
const double _sanityViewportNorth = 48.57;
const double _sanityViewportEast = 2.72;

/// Identity SDF rectangle (origin (0, 0), size (1, 1)) — matches the
/// FogLayer's per-frame setting so the sanity screen exercises the same
/// shader path as production.
const (double, double, double, double) _identitySdfRect = (0.0, 0.0, 1.0, 1.0);

/// Microseconds-per-second for the elapsed-time conversion fed to the
/// shader's `uTime` slot.
const double _microsPerSecond = 1e6;

/// Plan 03.1-07 — synthetic pixelOrigin trajectory parameters for the
/// debug-spiral shader. The sanity screen lives OUTSIDE any MapCamera
/// scope so a real `camera.pixelOrigin` is unavailable; instead the
/// painter feeds a time-driven sweep mirroring a 1.5 km/s gesture at
/// zoom 13 (~411 raw pixels per second on the X axis, 0 on Y — pure
/// left-to-right pan trajectory). After 60 seconds the trajectory hits
/// ~25,000 raw pixels (equivalent to a long zoom-13 walk); after 5
/// minutes it crosses ~123,000 — well into the regime where fp32
/// precision degradation (B-1) would be visible if it's the root cause.
const double _debugSpiralSyntheticPixelOriginSpeedXPxPerSec = 411.0;
const double _debugSpiralSyntheticPixelOriginSpeedYPxPerSec = 0.0;

/// Pre-walk gate (`/sanity` route).
///
/// Renders `atmospheric_fog.frag` against a synthetic SDF (one disc of
/// radius [kPocSanityScreenSyntheticDiscRadiusMeters] at viewport centre)
/// with hardcoded `kMirkFog*` uniforms. Subjective pass criterion (Plan
/// 03-08 manual UAT): developer confirms (a) fog renders with the
/// documented atmospheric look, (b) a circular reveal hole appears
/// centered on screen, (c) zero shader-compile exceptions in the
/// FileLogger output.
///
/// If the FragmentProgram fails to load (Pitfall 3 — shader compile error
/// on Impeller iOS), the body shows an error message — the walk is then
/// aborted before sideload.
///
/// Plan 03.1-07 — gains a `Switch.adaptive` toggle in the AppBar actions
/// that swaps the production fog shader for the diagnostic
/// [kPocDebugSpiralShaderAssetPath]. Default OFF; production fog
/// rendering UNCHANGED. The debug shader renders human-readable cell-
/// index digits in the SAME `uPixelOrigin / uResolution` coordinate
/// system as production fog so the user's observation directly answers
/// what the production shader's coordinate system is doing.
class ShaderSanityScreen extends StatefulWidget {
  const ShaderSanityScreen({super.key, this.programLoaderOverride, this.atlasOverride});

  /// Test seam — bypasses `ui.FragmentProgram.fromAsset` (which a headless
  /// widget-test runner cannot resolve). Production callers leave this
  /// `null` and the screen loads the real fog shader. The path argument
  /// is forwarded so tests can assert which shader was requested
  /// (production vs debug-spiral) when the toggle is flipped.
  final Future<ui.FragmentProgram> Function(String path)? programLoaderOverride;

  /// Test seam — bypasses [DigitAtlasBuilder.atlas] which depends on
  /// `ui.PictureRecorder.endRecording().toImage()` (works in
  /// `tester.runAsync(...)` but adds latency in test setup). Production
  /// callers leave this `null` and the screen lazily builds the atlas
  /// the first time the debug spiral is toggled on.
  final Future<ui.Image> Function()? atlasOverride;

  @override
  State<ShaderSanityScreen> createState() => _ShaderSanityScreenState();
}

class _ShaderSanityScreenState extends State<ShaderSanityScreen> {
  static final Logger _log = Logger('presentation.shader_sanity_screen');

  ui.FragmentShader? _shader;
  ui.Image? _syntheticSdf;
  ui.Image? _digitAtlas;
  Object? _loadError;
  DateTime? _mountedAt;

  /// Plan 03.1-07 — debug-spiral toggle state. `false` (default) renders
  /// the production fog; `true` renders the debug-spiral diagnostic.
  /// Toggling triggers a re-load via [_load] so the appropriate shader
  /// program is loaded.
  bool _useDebugSpiral = false;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
    unawaited(_load());
  }

  /// Loads the FragmentProgram (production OR debug-spiral, depending on
  /// [_useDebugSpiral]) AND the synthetic SDF, then triggers a rebuild.
  /// On error, surfaces the exception via [_loadError]; the build path
  /// then renders an error message instead of the fog.
  ///
  /// Plan 03.1-07 — when [_useDebugSpiral] is true, also resolves the
  /// digit atlas via [DigitAtlasBuilder.atlas] (or [widget.atlasOverride]
  /// if set). The atlas is process-cached so subsequent toggles ON are
  /// instant — only the first toggle ON triggers the ~30-50 ms async
  /// rasterization (acceptable for a debug-only diagnostic; the existing
  /// loading-spinner UX absorbs the blip).
  Future<void> _load() async {
    final assetPath = _useDebugSpiral ? kPocDebugSpiralShaderAssetPath : kPocFogShaderAssetPath;
    try {
      // Reset the visible state to "loading" while the new shader+atlas
      // resolve. Without this, the previous `_shader` would briefly
      // continue rendering the OLD shader path between `_load()` start
      // and end — visually confusing during the toggle flip.
      setState(() {
        _shader = null;
        _digitAtlas = null;
        _loadError = null;
      });
      final loader = widget.programLoaderOverride ?? (path) => ui.FragmentProgram.fromAsset(path);
      final program = await loader(assetPath);
      if (!mounted) return;

      // SDF: built once on first load, reused across toggle flips. Only
      // re-build it if not already present (the production fog needs it;
      // the debug spiral does not — but reusing the existing image is
      // free, no need for conditional cleanup).
      if (_syntheticSdf == null) {
        final viewport = MirkViewportBbox(south: _sanityViewportSouth, west: _sanityViewportWest, north: _sanityViewportNorth, east: _sanityViewportEast);
        final centerLat = (viewport.south + viewport.north) * 0.5;
        final centerLon = (viewport.west + viewport.east) * 0.5;
        final disc = RevealDisc(
          id: 'rvd_sanity_synthetic',
          sessionId: 'sanity',
          lat: centerLat,
          lon: centerLon,
          radiusMeters: kPocSanityScreenSyntheticDiscRadiusMeters,
          fixedAtUtc: DateTime.now().toUtc(),
        );
        final sdf = await const RevealedSdfBuilder().buildFromDiscs(discs: <RevealDisc>[disc], viewport: viewport);
        if (!mounted) {
          sdf.dispose();
          return;
        }
        _syntheticSdf = sdf;
      }

      ui.Image? atlas;
      if (_useDebugSpiral) {
        final atlasFuture = widget.atlasOverride != null ? widget.atlasOverride!() : DigitAtlasBuilder.atlas;
        atlas = await atlasFuture;
        if (!mounted) return;
      }

      setState(() {
        _shader = program.fragmentShader();
        _digitAtlas = atlas;
      });
      _log.info('ShaderSanityScreen: program (${_useDebugSpiral ? 'debug-spiral' : 'production'}) + synthetic SDF loaded successfully');
    } on Object catch (e, st) {
      _log.severe('ShaderSanityScreen: failed to load fog shader', e, st);
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _syntheticSdf?.dispose();
    // _digitAtlas is process-cached by DigitAtlasBuilder; do NOT dispose.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.shaderSanityScreenTitle),
        // UX-01 (Plan 03.1-05) — explicit back button. The /sanity route
        // is reached via context.push() from the AppBar science action;
        // pop() returns to the previous route (typically /map). Per
        // CLAUDE.md GoRouter rule: "if the word retour has meaning in UX
        // → push". Pre-Plan-03.1-05 the developer had to force-close the
        // app to return (03.1-FALSIFICATION.md observation 5). Material's
        // automaticallyImplyLeading would insert an Icons.arrow_back wired
        // to Navigator.maybePop, but Navigator.pop does NOT pop a GoRouter
        // route reached via context.push — context.pop() is required.
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: <Widget>[
          // Plan 03.1-07 — debug-spiral toggle. Default OFF; production
          // fog renders at /sanity unchanged. Flipping ON triggers a
          // re-load via _load() that swaps the shader path AND resolves
          // the digit atlas (via DigitAtlasBuilder).
          Tooltip(
            message: l10n.debugSpiralToggleTooltip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Switch.adaptive(
                value: _useDebugSpiral,
                onChanged: (value) {
                  setState(() => _useDebugSpiral = value);
                  unawaited(_load());
                },
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// Three-state body: error message, loading spinner, or the
  /// CustomPaint (production fog OR debug spiral). Extracted so [build]
  /// stays under the project's 50-line guideline.
  Widget _buildBody() {
    final err = _loadError;
    if (err != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(16), child: Text('Shader load failed: $err')),
      );
    }
    final shader = _shader;
    final mountedAt = _mountedAt;
    if (shader == null || mountedAt == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final uTimeSeconds = DateTime.now().difference(mountedAt).inMicroseconds / _microsPerSecond;
    if (_useDebugSpiral) {
      final atlas = _digitAtlas;
      if (atlas == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return CustomPaint(
        painter: _DebugSpiralPainter(shader: shader, atlas: atlas, uTimeSeconds: uTimeSeconds),
        size: Size.infinite,
      );
    }
    final sdf = _syntheticSdf;
    if (sdf == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return CustomPaint(
      painter: _FogSanityPainter(shader: shader, sdfImage: sdf, uTimeSeconds: uTimeSeconds),
      size: Size.infinite,
    );
  }
}

/// CustomPainter that exercises the FogShaderUniforms.setAll path with the
/// synthetic SDF + hardcoded kMirkFog* atmospheric uniforms — same call
/// shape as FogLayer (Plan 03-05).
///
/// Plan 03.1-07 — renamed from `_SanityPainter` to `_FogSanityPainter`
/// for clarity now that a sibling `_DebugSpiralPainter` exists.
/// Behaviour-preserved.
class _FogSanityPainter extends CustomPainter {
  _FogSanityPainter({required this.shader, required this.sdfImage, required this.uTimeSeconds});

  final ui.FragmentShader shader;
  final ui.Image sdfImage;
  final double uTimeSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    FogShaderUniforms.setAll(
      shader,
      resolution: size,
      time: uTimeSeconds,
      pixelOrigin: const (0.0, 0.0),
      baseArgb: kMirkFogAtmosphericBaseColorArgb,
      baseAlpha: 1.0,
      highlightArgb: kMirkFogAtmosphericHighlightColorArgb,
      shadowArgb: kMirkFogAtmosphericShadowColorArgb,
      driftZFar: kMirkFogAtmosphericDriftZFar,
      driftZMid: kMirkFogAtmosphericDriftZMid,
      driftZNear: kMirkFogAtmosphericDriftZNear,
      scaleFar: kMirkFogAtmosphericScaleFar,
      scaleMid: kMirkFogAtmosphericScaleMid,
      scaleNear: kMirkFogAtmosphericScaleNear,
      opacityFar: kMirkFogOpacityFar,
      opacityMid: kMirkFogOpacityMid,
      opacityNear: kMirkFogOpacityNear,
      curlAmplitude: kMirkFogCurlAmplitude,
      curlScale: kMirkFogCurlScale,
      lightDirRadians: kMirkFogLightDirRadians,
      lightOffset: kMirkFogLightOffset,
      lightStrength: kMirkFogLightStrength,
      hueNoiseScale: kMirkFogHueNoiseScale,
      hueStrength: kMirkFogHueStrength,
      boundarySharpDistance: kMirkFogBoundarySharpDistance,
      boundaryBleedDistance: kMirkFogBoundaryBleedDistance,
      boundaryEdgeBand: kMirkFogBoundaryEdgeBand,
      boundaryDensityBoost: kMirkFogBoundaryDensityBoost,
      sdfRect: _identitySdfRect,
      sdfImage: sdfImage,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  // Always repaint — the sanity screen is not a perf path; the visual
  // animation from the time-driven uTime uniform is the whole point.
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Plan 03.1-07 — paints the debug-spiral shader with the digit atlas as
/// sampler 1 + a synthetic time-driven `uPixelOrigin` trajectory.
///
/// The synthetic trajectory mirrors a 1.5 km/s gesture at zoom 13
/// (~411 raw pixels per second X-axis, 0 Y-axis — pure left-to-right
/// pan). After 60 seconds the trajectory crosses ~25,000 raw pixels;
/// after 5 minutes it crosses ~123,000 — well into the regime where
/// fp32 precision degradation (B-1) would be visible if it's the
/// production fog shader's root cause. Per Plan 03.1-07 Task 2's
/// procedure, the user observes the rendered cells AT LEAST 60
/// SECONDS to let the trajectory cover both low and high pixelOrigin
/// magnitudes.
class _DebugSpiralPainter extends CustomPainter {
  _DebugSpiralPainter({required this.shader, required this.atlas, required this.uTimeSeconds});

  final ui.FragmentShader shader;
  final ui.Image atlas;
  final double uTimeSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    // The debug-spiral shader uses 5 float slots (0..4) plus sampler 1.
    // Slot map matches production fog slots 0..4 verbatim so the
    // coordinate-system formulation `fragUv + fract(uPixelOrigin /
    // uResolution)` reads identically.
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, uTimeSeconds);
    shader.setFloat(3, uTimeSeconds * _debugSpiralSyntheticPixelOriginSpeedXPxPerSec);
    shader.setFloat(4, uTimeSeconds * _debugSpiralSyntheticPixelOriginSpeedYPxPerSec);
    shader.setImageSampler(1, atlas);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
