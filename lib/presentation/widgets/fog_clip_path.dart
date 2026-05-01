// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';

/// Computes the world-rect-minus-disc-circles clip path in screen
/// coordinates (FOG-06).
///
/// The returned [Path] covers the camera's screen rect with circular holes
/// punched at each disc centre (radius = disc radius projected to pixels at
/// the current zoom). FogLayer applies it via `canvas.clipPath` before
/// drawing the shader so the reveal hole is fully transparent.
///
/// Wave 0 stub — Plan 03-05 ships the implementation.
Path computeFogClipPath({required MapCamera camera, required List<RevealDisc> discs}) {
  throw UnimplementedError('computeFogClipPath — Plan 03-05');
}
