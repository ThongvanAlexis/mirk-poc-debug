// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/revealed_sdf_builder.dart';
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
class ShaderSanityScreen extends StatefulWidget {
  const ShaderSanityScreen({super.key, this.programLoaderOverride});

  /// Test seam — bypasses `ui.FragmentProgram.fromAsset` (which a headless
  /// widget-test runner cannot resolve). Production callers leave this
  /// `null` and the screen loads the real fog shader.
  final Future<ui.FragmentProgram> Function()? programLoaderOverride;

  @override
  State<ShaderSanityScreen> createState() => _ShaderSanityScreenState();
}

class _ShaderSanityScreenState extends State<ShaderSanityScreen> {
  static final Logger _log = Logger('presentation.shader_sanity_screen');

  ui.FragmentShader? _shader;
  ui.Image? _syntheticSdf;
  Object? _loadError;
  DateTime? _mountedAt;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
    unawaited(_load());
  }

  /// Loads the fog FragmentProgram (test override or
  /// [ui.FragmentProgram.fromAsset]) AND the synthetic SDF, then triggers
  /// a rebuild. On error, surfaces the exception via [_loadError]; the
  /// build path then renders an error message instead of the fog.
  Future<void> _load() async {
    try {
      final loader = widget.programLoaderOverride ?? () => ui.FragmentProgram.fromAsset(kPocFogShaderAssetPath);
      final program = await loader();
      if (!mounted) return;
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
      setState(() {
        _shader = program.fragmentShader();
        _syntheticSdf = sdf;
      });
      _log.info('ShaderSanityScreen: program + synthetic SDF loaded successfully');
    } on Object catch (e, st) {
      _log.severe('ShaderSanityScreen: failed to load fog shader', e, st);
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _syntheticSdf?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shaderSanityScreenTitle)),
      body: _buildBody(),
    );
  }

  /// Three-state body: error message, loading spinner, or the fog
  /// CustomPaint. Extracted so [build] stays under the project's 50-line
  /// guideline.
  Widget _buildBody() {
    final err = _loadError;
    if (err != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(16), child: Text('Shader load failed: $err')),
      );
    }
    final shader = _shader;
    final sdf = _syntheticSdf;
    final mountedAt = _mountedAt;
    if (shader == null || sdf == null || mountedAt == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return CustomPaint(
      painter: _SanityPainter(shader: shader, sdfImage: sdf, uTimeSeconds: DateTime.now().difference(mountedAt).inMicroseconds / _microsPerSecond),
      size: Size.infinite,
    );
  }
}

/// CustomPainter that exercises the FogShaderUniforms.setAll path with the
/// synthetic SDF + hardcoded kMirkFog* atmospheric uniforms — same call
/// shape as FogLayer (Plan 03-05).
class _SanityPainter extends CustomPainter {
  _SanityPainter({required this.shader, required this.sdfImage, required this.uTimeSeconds});

  final ui.FragmentShader shader;
  final ui.Image sdfImage;
  final double uTimeSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    FogShaderUniforms.setAll(
      shader,
      resolution: size,
      time: uTimeSeconds,
      offset: const (0.0, 0.0),
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
