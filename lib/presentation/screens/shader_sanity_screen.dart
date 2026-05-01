// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';

import 'package:mirk_poc_debug/l10n/app_localizations.dart';

/// Pre-walk gate (`/sanity` route) — renders the fog shader against a
/// synthetic SDF (one 80 m disc at viewport centre, see
/// `kPocSanityScreenSyntheticDiscRadiusMeters`) with hardcoded `kMirkFog*`
/// uniforms. Subjective pass criterion: developer sees atmospheric fog with
/// a circular reveal hole — proof the SDF→shader path works before the
/// real walk in Plan 03-08.
///
/// Wave 0 stub — Plan 03-06 ships the real shader-mounting body.
class ShaderSanityScreen extends StatefulWidget {
  const ShaderSanityScreen({super.key});

  @override
  State<ShaderSanityScreen> createState() => _ShaderSanityScreenState();
}

class _ShaderSanityScreenState extends State<ShaderSanityScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shaderSanityScreenTitle)),
      body: const Center(child: Text('Shader sanity screen — Plan 03-06')),
    );
  }
}
