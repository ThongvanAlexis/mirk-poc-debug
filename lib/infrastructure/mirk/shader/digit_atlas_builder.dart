// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Plan 03.1-07 — DEBUG-ONLY diagnostic infrastructure.
///
/// Builds a [ui.Image] containing digits 0..9 in a 10x10 grid (digits 0
/// through 9 across the top row; remaining 90 cells are intentionally
/// blank so the atlas dimensions remain a clean 640x640 — see the
/// `atmospheric_fog_debug_spiral.frag` `sampleDigit()` function which
/// only addresses the top row).
///
/// **WHY:** the production fog shader's `fract(uPixelOrigin / uResolution)`
/// formulation is mechanically opaque to the human eye during a gesture.
/// The debug-spiral shader (Plan 03.1-07) uses this digit atlas to render
/// human-readable cell-index labels in the SAME coordinate system the
/// production fog uses — observation under the debug shader directly
/// answers what the production shader is doing (translation, rotation,
/// stretching, cell-pop-in, DPR-squashing, etc.).
///
/// **WHAT:** 10x10 grid of 64x64 px cells. Total atlas dimensions:
/// 640x640 px. Top row contains digits 0..9 rasterized via [TextPainter]
/// (system font; no asset PNG or font package dependency). Remaining 90
/// cells are blank (background colour). The shader addresses only the
/// top row.
///
/// **WHEN:** lazy-built on first request via [atlas]; subsequent requests
/// return the same `ui.Image` instance (process-cached). The first
/// request triggers a one-time async rasterization (~30-50 ms blocking
/// on iPhone 17 Pro — visible as a brief loading-spinner blip while
/// `await DigitAtlasBuilder.atlas` completes). Acceptable for a
/// debug-only diagnostic toggle.
///
/// **PERMANENCE:** kept in the codebase as permanent diagnostic tooling.
/// Future regressions in production fog rendering (POC OR MirkFall after
/// port-back) can be diagnosed by toggling the debug spiral on at
/// `/sanity` without authoring new infrastructure.
class DigitAtlasBuilder {
  const DigitAtlasBuilder._();

  /// Atlas grid size — number of cells per row (and per column).
  static const int gridSize = 10;

  /// Per-cell pixel size in the atlas. Each digit is rasterized into
  /// this size with a small inner padding so the glyph fits cleanly.
  static const double cellPx = 64.0;

  /// Total atlas dimensions in pixels. `gridSize * cellPx`.
  static const double atlasPx = 640.0;

  /// Returns the cached digit atlas, building it on first call.
  ///
  /// Cached as a top-level [Future<ui.Image>] in this library — repeated
  /// calls during a single process return the SAME `ui.Image` instance
  /// (verified by [identical]).
  static Future<ui.Image> get atlas {
    return _cachedAtlas ??= _buildAtlas();
  }

  /// Resets the process cache. Test-only seam — production callers MUST
  /// NOT use this. Tests use it to isolate the cache between runs in
  /// the rare case a test wants a fresh atlas.
  static void resetCacheForTesting() {
    _cachedAtlas = null;
  }
}

Future<ui.Image>? _cachedAtlas;

/// Rasterizes the 10x10 atlas via [ui.PictureRecorder] + [Canvas] +
/// [TextPainter]. Background filled with a dark grey so the unused
/// cells (positions 10..99) blend with the debug shader's background
/// colour; digits 0..9 in the top row are rendered as white glyphs
/// centered within their 64x64 cell with a 6 px inner padding.
Future<ui.Image> _buildAtlas() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Background: dark grey matches the debug shader's background colour
  // so unused atlas cells (positions 10..99) blend rather than show as
  // a different colour. Alpha = 0 means the shader's mix() blends them
  // correctly when the atlas's red channel is sampled — the unused
  // region returns red ~ 0.08 which the shader treats as no-digit.
  final backgroundPaint = Paint()..color = const Color(0xFF141418);
  canvas.drawRect(const Rect.fromLTWH(0.0, 0.0, DigitAtlasBuilder.atlasPx, DigitAtlasBuilder.atlasPx), backgroundPaint);

  for (var digit = 0; digit < 10; digit++) {
    _paintDigitCell(canvas, digit, col: digit, row: 0);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(DigitAtlasBuilder.atlasPx.toInt(), DigitAtlasBuilder.atlasPx.toInt());
  picture.dispose();
  return image;
}

/// Rasterizes a single digit centered in its 64x64 cell at (col, row).
/// Glyph colour: white. Inner padding ~6 px so the glyph fits cleanly
/// regardless of the system font's metrics.
void _paintDigitCell(Canvas canvas, int digit, {required int col, required int row}) {
  final cellOriginX = col * DigitAtlasBuilder.cellPx;
  final cellOriginY = row * DigitAtlasBuilder.cellPx;

  final textPainter = TextPainter(
    text: TextSpan(
      text: '$digit',
      style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 48, fontWeight: FontWeight.w700, height: 1.0),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: DigitAtlasBuilder.cellPx);

  final textOffsetX = cellOriginX + (DigitAtlasBuilder.cellPx - textPainter.width) * 0.5;
  final textOffsetY = cellOriginY + (DigitAtlasBuilder.cellPx - textPainter.height) * 0.5;
  textPainter.paint(canvas, Offset(textOffsetX, textOffsetY));
  textPainter.dispose();
}
