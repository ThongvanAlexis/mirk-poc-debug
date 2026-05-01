// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';

/// flutter_map custom layer — paints `atmospheric_fog.frag` into the
/// same Canvas as VectorTileLayer (FOG-04..07).
///
/// Reads `MapCamera.of(context)` exactly once per build (FOG-07 invariant)
/// and threads the snapshot through SDF rebuild + uniform population so the
/// fog stays locked to the map during pan / pinch / combined gestures.
///
/// Wave 0 stub — Plan 03-05 ships the implementation. The current build
/// returns `SizedBox.shrink()` so this widget can be mounted inside a
/// `FlutterMap.children` list without affecting layout.
class FogLayer extends StatefulWidget {
  const FogLayer({super.key, required this.discRepository, required this.shader, required this.sdfCache, required this.frameDeltaProbe});

  /// Reveal-disc source — the layer subscribes via `addListener` and rebuilds
  /// when new discs land.
  final RevealDiscRepository discRepository;

  /// Pre-loaded `atmospheric_fog.frag` fragment shader.
  final ui.FragmentShader shader;

  /// SDF cache (FOG-03) — the layer queries `getOrBuild(discs, viewport)`
  /// per frame; cache hits keep the per-frame cost at one hash.
  final SdfCache sdfCache;

  /// FOG-08 frame-delta probe — the layer calls
  /// [FrameDeltaProbe.recordCameraSnapshot] at the top of build and
  /// [FrameDeltaProbe.recordFogUniformPopulation] after `FogShaderUniforms.setAll`.
  final FrameDeltaProbe frameDeltaProbe;

  @override
  State<FogLayer> createState() => _FogLayerState();
}

class _FogLayerState extends State<FogLayer> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
