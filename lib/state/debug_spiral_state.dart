// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/foundation.dart';

/// Plan 03.1-08-FIX (FIX 2) — DEBUG-ONLY shared toggle state for the
/// debug-spiral diagnostic shader (Plan 03.1-07 / DEBUG-01).
///
/// **Why a top-level [ValueNotifier]:** the toggle was originally scoped to
/// `/sanity` only (Plan 03.1-07 Task 1). Walk-bound observation needs to
/// see the spiral under PRODUCTION gesture conditions on `/map` —
/// `/sanity`'s synthetic time-driven trajectory does NOT reproduce the
/// zoom-correlated `pixelOrigin` jumps where the production shimmer
/// mechanism actually lives. Moving the toggle to the global [PocAppBar]
/// requires both `MapScreen` (the production fog painter) AND
/// `ShaderSanityScreen` (the pre-walk gate) to react to the same flag.
///
/// A single top-level [ValueNotifier] + [ValueListenableBuilder] (or
/// [AnimatedBuilder] with `listenable:`) is the minimal mechanism that
/// avoids `InheritedWidget` plumbing while keeping the toggle reactive.
/// Compared to a static bool flag, the notifier triggers automatic
/// rebuilds in both screens on flip; compared to `Provider`/`Riverpod`,
/// it adds zero dependencies (debug-only feature; CLAUDE.md "single state
/// management system" rule applies but a bare [ValueNotifier] from
/// `flutter/foundation.dart` is built-in and not a competing system).
///
/// **Default OFF**. Production fog rendering is unchanged when OFF;
/// flipping ON via the AppBar Switch swaps to the debug-spiral shader on
/// whichever screen is foregrounded. Opt-in only; no production-fog
/// regression when OFF.
///
/// **Lifetime: process-scoped.** The notifier is constructed at first
/// import and lives until the process exits. No `dispose` because the
/// toggle outlives all screens that observe it (intentional — a `/map`
/// → `/sanity` → `/map` navigation must preserve the toggle state).
final ValueNotifier<bool> debugSpiralEnabled = ValueNotifier<bool>(false);

/// Plan 03.1-16 (FOG-20) — Worley vs FBM-fallback shader A/B preview
/// toggle.
///
/// Mirrors the [debugSpiralEnabled] pattern but for the aesthetic A/B
/// preview at /sanity. Default `true` = Worley (production default);
/// flipping to `false` swaps in the frozen FBM-fallback shader at
/// [kPocFogFbmFallbackShaderAssetPath] for side-by-side comparison.
///
/// **/sanity-only.** The PocAppBar (which appears on /map and /sanity)
/// does NOT expose this Switch — production /map ALWAYS renders the
/// Worley shader. The toggle lives ONLY in the
/// [ShaderSanityScreen] AppBar actions. Rationale: this is a pre-walk
/// preview gate (Plan 03.1-16 Task 2 checkpoint:human-verify), not a
/// production runtime feature. After the developer accepts Worley at
/// the aesthetic gate, the FBM fallback shader stays at /sanity for
/// historical reference but production never loads it.
///
/// **Lifetime: process-scoped.** Same rationale as [debugSpiralEnabled].
/// Tests reset the notifier to `true` in `setUp` so each test starts
/// from the production default.
final ValueNotifier<bool> worleyVsFbmFallback = ValueNotifier<bool>(true);
