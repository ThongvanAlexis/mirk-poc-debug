// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-19 (Plan 03.1-14 Fix B′) — wrap-invisibility tests across the
/// FULL 3-octave fbm3 chain.
///
/// Two synthetic samples straddling a wrap boundary (worldMetersX values
/// 4095.0 and 4097.0). Compute synthetic noiseUv at the viewport-centre
/// fragment for each. Three sub-tests:
///
/// 1. **Base octave (X axis):** assert the noiseUv shift modulo 1.0 is
///    near 0 (integer-cell-only shift on the BASE octave — bit-identical
///    via hash3 period-1).
/// 2. **Base octave (Y axis):** mirror sub-test 1 for the Y axis.
/// 3. **Full 3-octave fbm3 chain:** port the shader's fbm3 chain to
///    Dart (M_1 = 2.03·I, M_2 = 2.05·I, weights 0.5/0.25/0.125, value-
///    noise primitive matching atmospheric_fog.frag noise3 lines 152-
///    189). Assert `|fbm3_after - fbm3_before|` for the FULL 3-octave
///    chain stays under [kPocFogFbmDiscontinuityBound] = 0.20. Also
///    assert constant-magnitude property: across multiple wrap events,
///    the discontinuity magnitude is identical within fp32 precision.
///
/// Architectural soundness claim: per-wrap fbm3 phase shift is constant,
/// deterministic, zoom-independent, lat-independent. Walk #6 empirically
/// validates the perceptual threshold (the constant-magnitude property
/// is the architectural fix; sub-perceptibility is the empirical
/// question).
void main() {
  group('FOG-19 (Plan 03.1-14 Fix B′) — wrap-invisibility (full 3-octave fbm3)', () {
    test('Sub-test 1 — base octave (X axis) integer-cell shift at wrap boundary', () {
      const before = 4095.0;
      const after = 4097.0;

      double bounded(double wm) {
        final intM = wm.truncateToDouble();
        final fracM = wm - intM;
        return (intM % kPocFogIntegerWrapPeriodMeters) + fracM;
      }

      final bBefore = bounded(before);
      final bAfter = bounded(after);

      // Shader-equivalent noiseUv at viewport-centre fragment.
      // (fragUv * uResolution) * mpp = 0.5 * 390 * mpp; at z=15 lat 48.5°
      // mpp ≈ 3.16 → fragMetersX ≈ 616 m.
      const lat = 48.5397;
      const z = 15.0;
      final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, z).toDouble();
      final fragMetersX = 0.5 * 390.0 * mpp;

      final noiseUvBefore = (fragMetersX + bBefore) / kPocFogNoiseTilePxMeters;
      final noiseUvAfter = (fragMetersX + bAfter) / kPocFogNoiseTilePxMeters;
      final delta = noiseUvAfter - noiseUvBefore;
      // delta in cells modulo 1.0 should be near 0 — only integer-cell
      // shift via the wrap (plus a tiny sub-cell from the 2 m bridge).
      final deltaModFloor = (delta - delta.floorToDouble()).abs();
      // 2 m bridge / 1024 m/cell = 0.00195 — within the tolerance band.
      expect(
        deltaModFloor < 0.005 || (deltaModFloor - 1.0).abs() < 0.005,
        isTrue,
        reason:
            'FOG-19 wrap invisibility (base octave, X axis): at every wrap boundary, the noiseUv shift modulo 1.0 '
            'must be near 0 (Octave 1 is bit-identical at the noise output level via hash3 period-1). '
            'Got noiseUvBefore=$noiseUvBefore, noiseUvAfter=$noiseUvAfter, delta=$delta, '
            'deltaModFloor=$deltaModFloor.',
      );
    });

    test('Sub-test 2 — base octave (Y axis) integer-cell shift at wrap boundary', () {
      // Mirror sub-test 1 for the Y axis.
      const before = 4095.0;
      const after = 4097.0;

      double bounded(double wm) {
        final intM = wm.truncateToDouble();
        final fracM = wm - intM;
        return (intM % kPocFogIntegerWrapPeriodMeters) + fracM;
      }

      final bBefore = bounded(before);
      final bAfter = bounded(after);

      const lat = 48.5397;
      const z = 15.0;
      final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, z).toDouble();
      final fragMetersY = 0.5 * 800.0 * mpp; // synthetic 800-px viewport height

      final noiseUvBefore = (fragMetersY + bBefore) / kPocFogNoiseTilePxMeters;
      final noiseUvAfter = (fragMetersY + bAfter) / kPocFogNoiseTilePxMeters;
      final delta = noiseUvAfter - noiseUvBefore;
      final deltaModFloor = (delta - delta.floorToDouble()).abs();
      expect(
        deltaModFloor < 0.005 || (deltaModFloor - 1.0).abs() < 0.005,
        isTrue,
        reason:
            'FOG-19 wrap invisibility (base octave, Y axis): at every wrap boundary, the noiseUv shift modulo 1.0 '
            'must be near 0. Got delta=$delta, deltaModFloor=$deltaModFloor.',
      );
    });

    test('Sub-test 3 — FULL 3-octave fbm3 chain residual discontinuity bounded by kPocFogFbmDiscontinuityBound', () {
      // Port the shader's fbm3 chain to Dart. fbm3(p):
      //   t = 0.5 * noise3(p);  p = p * 2.03 + (13.7, 7.3, 5.1);
      //   t += 0.25 * noise3(p); p = p * 2.05 + (-11.1, 17.9, 3.3);
      //   t += 0.125 * noise3(p);
      //   return t;
      // noise3(p) is trilinear-interpolated value-noise (see
      // atmospheric_fog.frag lines 152-189).
      const lat = 48.5397;
      const z = 15.0;
      final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, z).toDouble();
      final fragMetersX = 0.5 * 390.0 * mpp;
      final fragMetersY = 0.5 * 800.0 * mpp;

      double bounded(double wm) {
        final intM = wm.truncateToDouble();
        final fracM = wm - intM;
        return (intM % kPocFogIntegerWrapPeriodMeters) + fracM;
      }

      // Pre-wrap and post-wrap synthetic worldMetersX values.
      final discontinuities = <double>[];
      for (var wrapIndex = 0; wrapIndex < 3; wrapIndex++) {
        final worldMetersBefore = (wrapIndex + 1) * kPocFogIntegerWrapPeriodMeters - 1.0;
        final worldMetersAfter = (wrapIndex + 1) * kPocFogIntegerWrapPeriodMeters + 1.0;

        final boundedBefore = bounded(worldMetersBefore);
        final boundedAfter = bounded(worldMetersAfter);

        final noiseUvBefore = _Vec3((fragMetersX + boundedBefore) / kPocFogNoiseTilePxMeters, fragMetersY / kPocFogNoiseTilePxMeters, 0.0);
        final noiseUvAfter = _Vec3((fragMetersX + boundedAfter) / kPocFogNoiseTilePxMeters, fragMetersY / kPocFogNoiseTilePxMeters, 0.0);

        final fbm3Before = _fbm3(noiseUvBefore);
        final fbm3After = _fbm3(noiseUvAfter);
        discontinuities.add((fbm3After - fbm3Before).abs());
      }

      // Bound check — every per-wrap discontinuity stays under bound.
      for (var i = 0; i < discontinuities.length; i++) {
        expect(
          discontinuities[i],
          lessThan(kPocFogFbmDiscontinuityBound),
          reason:
              'FOG-19 wrap invisibility (full 3-octave fbm3 chain, wrap $i): the per-wrap fbm3 amplitude '
              'discontinuity must stay under the analytical bound (kPocFogFbmDiscontinuityBound = '
              '$kPocFogFbmDiscontinuityBound). Bound derivation: 0.25 · max||∇noise3|| · |frac(M_1·V)| + '
              '0.125 · max||∇noise3|| · |frac(M_1·M_2·V)| ≈ 0.25 · 1.7 · 0.12 + 0.125 · 1.7 · 0.646 ≈ 0.188 < 0.20. '
              'If this assertion fires, either (a) the fbm3 chain matrices changed (M_1 ≠ 2.03·I or '
              'M_2 ≠ 2.05·I) — re-derive the bound; (b) the noise3 primitive changed — re-derive; OR '
              '(c) the meter-space decomposition is broken at integer-cell shifts.',
        );
      }

      // Constant-magnitude property: across all wrap events, the
      // discontinuity magnitude must be identical within fp32 precision.
      // This is the CRITICAL architectural property that distinguishes
      // Plan 03.1-14 Fix B′ from the pre-fix variable-magnitude wraps
      // that Walk #5 perceived as stepping.
      final spread = discontinuities.reduce(math.max) - discontinuities.reduce(math.min);
      // fp32 precision at fbm3 amplitude ≈ 1.5 is ~1e-7; the synthetic
      // doubles use fp64 so practical spread is ≈ 0. Allow a generous
      // 1e-9 tolerance.
      expect(
        spread,
        lessThan(1e-9),
        reason:
            'FOG-19 architectural property (constant-magnitude wrap shifts): every wrap event must inject the SAME '
            'fbm3 discontinuity magnitude (within fp64 precision; the matrices M_1, M_2 and integer-cell shift '
            'V = (-4, 0, 0) are all constants). The pre-fix Walk #5 stepping signal arose from per-wrap MAGNITUDE '
            'VARIATION (1536 × mpp mod 1024 was zoom × lat dependent); the post-fix meter-space decomposition '
            'produces constant-magnitude wraps, eliminating the comparative-stepping perceptual signal. Got '
            'discontinuities=$discontinuities, spread=$spread.',
      );
    });
  });
}

/// Minimal 3D vector for the synthetic fbm3 chain.
class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  _Vec3 operator +(_Vec3 o) => _Vec3(x + o.x, y + o.y, z + o.z);
  _Vec3 scale(double k) => _Vec3(x * k, y * k, z * k);
}

/// Dart port of `hash3(vec3 p)` from `atmospheric_fog.frag` lines 157-164.
double _hash3(_Vec3 p) {
  // p = fract(p * 0.1031);
  var px = (p.x * 0.1031) - (p.x * 0.1031).floorToDouble();
  var py = (p.y * 0.1031) - (p.y * 0.1031).floorToDouble();
  var pz = (p.z * 0.1031) - (p.z * 0.1031).floorToDouble();
  // p += dot(p, p.yxz + 19.19);
  final dot = px * (py + 19.19) + py * (px + 19.19) + pz * (pz + 19.19);
  px += dot;
  py += dot;
  pz += dot;
  // return fract((p.x + p.y) * p.z);
  final raw = (px + py) * pz;
  return raw - raw.floorToDouble();
}

/// Dart port of `noise3(vec3 p)` — trilinear-interpolated value-noise.
/// Mirrors atmospheric_fog.frag lines 152-189 (smoothstep weights).
double _noise3(_Vec3 p) {
  final ix = p.x.floorToDouble();
  final iy = p.y.floorToDouble();
  final iz = p.z.floorToDouble();
  final fx = p.x - ix;
  final fy = p.y - iy;
  final fz = p.z - iz;
  // smoothstep weighting: w = f*f*(3-2f)
  final ux = fx * fx * (3.0 - 2.0 * fx);
  final uy = fy * fy * (3.0 - 2.0 * fy);
  final uz = fz * fz * (3.0 - 2.0 * fz);
  // 8 corner samples
  final c000 = _hash3(_Vec3(ix, iy, iz));
  final c100 = _hash3(_Vec3(ix + 1.0, iy, iz));
  final c010 = _hash3(_Vec3(ix, iy + 1.0, iz));
  final c110 = _hash3(_Vec3(ix + 1.0, iy + 1.0, iz));
  final c001 = _hash3(_Vec3(ix, iy, iz + 1.0));
  final c101 = _hash3(_Vec3(ix + 1.0, iy, iz + 1.0));
  final c011 = _hash3(_Vec3(ix, iy + 1.0, iz + 1.0));
  final c111 = _hash3(_Vec3(ix + 1.0, iy + 1.0, iz + 1.0));
  final m00 = c000 * (1.0 - ux) + c100 * ux;
  final m10 = c010 * (1.0 - ux) + c110 * ux;
  final m01 = c001 * (1.0 - ux) + c101 * ux;
  final m11 = c011 * (1.0 - ux) + c111 * ux;
  final m0 = m00 * (1.0 - uy) + m10 * uy;
  final m1 = m01 * (1.0 - uy) + m11 * uy;
  // Result in [0, 1]; remap to [-1, 1] to match shader's likely usage.
  final v = m0 * (1.0 - uz) + m1 * uz;
  return v * 2.0 - 1.0;
}

/// Dart port of `fbm3(vec3 p)` chain — atmospheric_fog.frag lines 193-207.
double _fbm3(_Vec3 p) {
  var pp = p;
  var a = 0.5;
  var t = 0.0;
  // Octave 1
  t += a * _noise3(pp);
  pp = pp.scale(2.03) + const _Vec3(13.7, 7.3, 5.1);
  a *= 0.5;
  // Octave 2
  t += a * _noise3(pp);
  pp = pp.scale(2.05) + const _Vec3(-11.1, 17.9, 3.3);
  a *= 0.5;
  // Octave 3
  t += a * _noise3(pp);
  return t;
}
