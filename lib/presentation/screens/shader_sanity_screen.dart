// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:math' as math;
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
import 'package:mirk_poc_debug/state/debug_spiral_state.dart';

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

/// Plan 03.1-12 FOG-18 — degrees-per-half-turn (180.0). Hoisted so
/// the magic `180.0` doesn't appear inline in the synthetic
/// `metersPerPixel = kWebMercatorMetersPerPxAtEquatorZ0 * cos(lat * π/180) /
/// pow(2, zoom)` computation in /sanity painters.
const double _kSanityDegreesPerHalfTurn = 180.0;

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

  /// Plan 03.1-07 + Plan 03.1-08-FIX FIX 2 — last loaded shader path. We
  /// read [debugSpiralEnabled] at load time and cache the path so the
  /// notifier listener can detect a real change vs. a stray notify and
  /// trigger a single re-load. Without this, two listener fires for the
  /// same target value would queue two redundant loads.
  String _lastLoadedAssetPath = kPocFogShaderAssetPath;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
    debugSpiralEnabled.addListener(_onDebugSpiralToggleChanged);
    unawaited(_load());
  }

  /// Plan 03.1-08-FIX FIX 2 — reacts to the global [debugSpiralEnabled]
  /// notifier flipping. Triggers a re-load via [_load] when the desired
  /// asset path differs from the currently loaded one. Idempotent: stray
  /// notifications without a path change are silently ignored.
  void _onDebugSpiralToggleChanged() {
    if (!mounted) return;
    final desiredPath = debugSpiralEnabled.value ? kPocDebugSpiralShaderAssetPath : kPocFogShaderAssetPath;
    if (desiredPath == _lastLoadedAssetPath) return;
    unawaited(_load());
  }

  /// Loads the FragmentProgram (production OR debug-spiral, depending on
  /// the global [debugSpiralEnabled] notifier) AND the synthetic SDF,
  /// then triggers a rebuild. On error, surfaces the exception via
  /// [_loadError]; the build path then renders an error message instead
  /// of the fog.
  ///
  /// Plan 03.1-07 — when [debugSpiralEnabled] is true, also resolves the
  /// digit atlas via [DigitAtlasBuilder.atlas] (or [widget.atlasOverride]
  /// if set). The atlas is process-cached so subsequent toggles ON are
  /// instant — only the first toggle ON triggers the ~30-50 ms async
  /// rasterization (acceptable for a debug-only diagnostic; the existing
  /// loading-spinner UX absorbs the blip).
  ///
  /// Plan 03.1-08-FIX FIX 2 — reads the global [debugSpiralEnabled]
  /// notifier instead of a local field. The notifier is shared with the
  /// MapScreen toggle (PocAppBar Switch) so flipping it on either screen
  /// updates both.
  Future<void> _load() async {
    final useDebugSpiral = debugSpiralEnabled.value;
    final assetPath = useDebugSpiral ? kPocDebugSpiralShaderAssetPath : kPocFogShaderAssetPath;
    _lastLoadedAssetPath = assetPath;
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
      if (useDebugSpiral) {
        final atlasFuture = widget.atlasOverride != null ? widget.atlasOverride!() : DigitAtlasBuilder.atlas;
        atlas = await atlasFuture;
        if (!mounted) return;
      }

      setState(() {
        _shader = program.fragmentShader();
        _digitAtlas = atlas;
      });
      _log.info('ShaderSanityScreen: program (${useDebugSpiral ? 'debug-spiral' : 'production'}) + synthetic SDF loaded successfully');
    } on Object catch (e, st) {
      _log.severe('ShaderSanityScreen: failed to load fog shader', e, st);
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    debugSpiralEnabled.removeListener(_onDebugSpiralToggleChanged);
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
          // Plan 03.1-07 + Plan 03.1-08-FIX FIX 2 — debug-spiral toggle.
          // Default OFF; production fog renders at /sanity unchanged.
          // Flipping ON updates the shared [debugSpiralEnabled] notifier;
          // the listener in [_onDebugSpiralToggleChanged] then triggers
          // [_load()] which swaps the shader path AND resolves the digit
          // atlas via DigitAtlasBuilder. Same widget pattern as the
          // PocAppBar Switch on /map so the toggle UX is identical
          // across screens (state survives navigation between /map and
          // /sanity).
          Tooltip(
            message: l10n.debugSpiralToggleTooltip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: ValueListenableBuilder<bool>(
                valueListenable: debugSpiralEnabled,
                builder: (BuildContext context, bool enabled, Widget? _) {
                  return Switch.adaptive(value: enabled, onChanged: (bool value) => debugSpiralEnabled.value = value);
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
    // Read the SHARED notifier — keeps the body in lockstep with
    // whichever screen flipped the toggle. Re-rendering of this body on
    // notifier change is driven by the [_load] setState chain.
    if (debugSpiralEnabled.value) {
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
    // FOG-18 (Plan 03.1-12) — /sanity feeds a synthetic metersPerPixel
    // value (real camera not available on /sanity). Computed at
    // kPocInitialCameraLat (Melun centre) and kPocInitialZoom (z=13) — a
    // representative hike-regime value (~12.66 m/raw_px). The /sanity
    // diagnostic still reflects the FOG-18 architectural change at a
    // representative zoom; if developers need to verify zoom-variance,
    // they should toggle the debug-spiral on /map (which uses the live
    // MapCamera).
    final latRadians = kPocInitialCameraLat * math.pi / _kSanityDegreesPerHalfTurn;
    final syntheticMetersPerPixel = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRadians) / math.pow(2.0, kPocInitialZoom).toDouble();

    FogShaderUniforms.setAll(
      shader,
      resolution: size,
      time: uTimeSeconds,
      worldMetersOrigin: const (0.0, 0.0),
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
      metersPerPixel: syntheticMetersPerPixel,
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
    // The debug-spiral shader uses 6 float slots (0..5) plus sampler 0.
    // Sampler slot is 0 (not 1) — the shader has only one declared
    // sampler; Flutter's `setImageSampler(N, image)` indexes per-shader
    // from 0 in declaration order. Plan 03.1-08-FIX FIX 3: the original
    // Plan 03.1-07 landing bound at slot 1, leaving the atlas unbound
    // on iPhone Impeller — the user's "no shader displayed" report.
    //
    // Plan 03.1-14 (Fix B′ — FOG-19) — /sanity debug-spiral mirrors the
    // production meter-space FOG-17a decomposition. Synthetic time-
    // driven pixelOrigin trajectory → multiply by syntheticMpp →
    // decompose in METER space → forward bounded composite via slots 3
    // and 4. The /sanity trajectory stays at a single zoom; on-device
    // zoom-axis verification happens via the /map debug-spiral toggle.
    final latRadians = kPocInitialCameraLat * math.pi / _kSanityDegreesPerHalfTurn;
    final syntheticMetersPerPixel = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRadians) / math.pow(2.0, kPocInitialZoom).toDouble();

    // Plan 03.1-14 Fix B′ — synthetic meter-space decomposition mirror
    // of _FogPainter.paint(). The synthetic pixelOrigin trajectory is
    // (uTime × speedXPxPerSec, uTime × speedYPxPerSec) raw px; convert
    // to meter-space, decompose, forward.
    final syntheticPixelOriginX = uTimeSeconds * _debugSpiralSyntheticPixelOriginSpeedXPxPerSec;
    final syntheticPixelOriginY = uTimeSeconds * _debugSpiralSyntheticPixelOriginSpeedYPxPerSec;
    final syntheticWorldMetersX = syntheticPixelOriginX * syntheticMetersPerPixel;
    final syntheticWorldMetersY = syntheticPixelOriginY * syntheticMetersPerPixel;
    final intMetersX = syntheticWorldMetersX.truncateToDouble();
    final intMetersY = syntheticWorldMetersY.truncateToDouble();
    final fracMetersX = syntheticWorldMetersX - intMetersX;
    final fracMetersY = syntheticWorldMetersY - intMetersY;
    final boundedMetersX = (intMetersX % kPocFogIntegerWrapPeriodMeters) + fracMetersX;
    final boundedMetersY = (intMetersY % kPocFogIntegerWrapPeriodMeters) + fracMetersY;

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, uTimeSeconds);
    shader.setFloat(3, boundedMetersX); // ← Plan 03.1-14 Fix B′ — synthetic meter-space bounded composite.
    shader.setFloat(4, boundedMetersY); // ← Plan 03.1-14 Fix B′ — synthetic meter-space bounded composite.
    shader.setFloat(5, syntheticMetersPerPixel); // ← FOG-18 slot 5 (debug-spiral has slots 0..5 + sampler).
    shader.setImageSampler(0, atlas);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
