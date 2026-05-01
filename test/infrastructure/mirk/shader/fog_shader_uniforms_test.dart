// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/shader/fog_shader_uniforms.dart';

/// FOG-05 — FogShaderUniforms slot count gate.
///
/// Wave 0 contract: this test is GREEN from day 1. It re-asserts the donor
/// file's `totalFloatSlots == 41` invariant so that any future change which
/// reorders or adds/removes a slot in the `.frag` uniform declaration is
/// caught BEFORE it reaches a sideload UAT walk (defends against a future
/// BUG-014 Iter-2 regression).
///
/// If a future iteration changes the uniform count, BOTH this constant and
/// the `.frag` declaration must be updated together (and the FogShaderUniforms.setAll
/// implementation reviewed) — that's the whole point of pinning the count here.
void main() {
  test('FogShaderUniforms.totalFloatSlots == 41 — slot-count gate against BUG-014 Iter 2 regression', () {
    expect(FogShaderUniforms.totalFloatSlots, 41);
  });
}
