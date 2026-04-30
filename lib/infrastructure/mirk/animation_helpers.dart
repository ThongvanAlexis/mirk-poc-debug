// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// Animation helpers reusable across mirk renderers.
//
// The 2026-04-26 UAT walk surfaced that slowly varying curlScale gives
// the volumetric fog a "really alive" feel — implemented in the
// atmospheric + heavenly renderers via [triangleWave]. The helper is
// kept generic so future tunables (rotating light direction, breathing
// hue palette, etc.) can adopt the same animation pattern.

/// Computes a triangle wave between [minV] and [maxV] with full period
/// [period] in seconds. At `tSec=0` returns [minV]; at `tSec=period/2`
/// returns [maxV]; at `tSec=period` returns [minV] again. Values past
/// `period` wrap (modular phase).
///
/// Returns [minV] when [period] <= 0 — guards against a zero/negative
/// period configured by accident (the renderers would otherwise hit a
/// division-by-zero) without throwing in the paint hot path.
double triangleWave({required double tSec, required double period, required double minV, required double maxV}) {
  if (period <= 0.0) return minV;
  final phase = (tSec % period) / period;
  // Triangle wave folded around 0.5: rising on [0..0.5], falling on
  // [0.5..1.0]. The (1.0 - phase) * 2.0 expression maps the descending
  // half symmetrically back to [0..1].
  final folded = phase < 0.5 ? phase * 2.0 : (1.0 - phase) * 2.0;
  return minV + folded * (maxV - minV);
}
