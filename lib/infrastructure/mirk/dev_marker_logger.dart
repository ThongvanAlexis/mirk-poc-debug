// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';

import 'package:logging/logging.dart';

/// Plan 03.1-09-CORR — developer-observation marker.
///
/// One-shot JSONL logger emitted on each tap of the AppBar `Icons.bug_report`
/// button (see [buildPocAppBar]). Lands in the same
/// `<app_documents>/logs/yyyymmdd_hhmm.ss_logs.txt` file the existing
/// rollup loggers (`SdfRebuildLogger`, `FrameDeltaProbe`,
/// `FogTransformLogger`) write to, so post-walk JSONL grep can correlate
/// the observation moment against the per-second pixelOrigin /
/// canvasTransform / sdf-rebuild rollups.
///
/// **Why a sibling `Logger('infrastructure.mirk.dev_marker')`:** consistent
/// with the existing `infrastructure.mirk.frame_delta`,
/// `infrastructure.mirk.sdf`, `infrastructure.mirk.fog_transform` naming
/// convention. Same `FileLogger` sink picks it up automatically — no
/// new wiring.
///
/// **Why one event per tap, no buffering:** the marker is a punctual
/// observation, not a rollup. The developer taps it the moment they SEE
/// the symptom (e.g. "steppy translation"). The emitted line carries a
/// wall-clock `epochMs` (NOT `epochSecond`) for sub-second precision —
/// the rollup loggers emit per-second, so the marker gives a finer
/// timestamp than the streams it correlates against, which is the right
/// way around (the rollup window containing the marker's epochMs is the
/// observation window).
///
/// **Tag flexibility:** the [tag] argument lets the developer narrow what
/// they observed. For Walk #4 the AppBar emits `tag: "steppy_translation"`
/// hardcoded — future plans MAY add multiple buttons (one per tag) without
/// touching this logger.
///
/// **No camera state captured here.** The AppBar has no
/// `MapController`-scoped context (it lives above the MapScreen body in
/// the widget tree), and threading a camera-readout callback through
/// would be churn for a debug-only feature. The per-second JSONL streams
/// already capture pixelOrigin / canvasTransform / centerLat / centerLon
/// continuously — the dev_marker line just needs a timestamp to point at
/// the right rollup window.
class DevMarkerLogger {
  /// Private constructor — this class is a static-only namespace.
  DevMarkerLogger._();

  static final Logger _log = Logger('infrastructure.mirk.dev_marker');

  /// Emits one INFO-level JSONL line of the form:
  ///   `{"event":"dev_marker","tag":"<tag>","epochMs":<int>}`
  ///
  /// [tag] should be a short snake_case symptom identifier (e.g.
  /// `"steppy_translation"`, `"rotation_fog_gap"`). Whitespace is preserved
  /// verbatim — `json.encode` handles escaping.
  static void emit({required String tag}) {
    final epochMs = DateTime.now().millisecondsSinceEpoch;
    final line = json.encode(<String, Object>{'event': 'dev_marker', 'tag': tag, 'epochMs': epochMs});
    _log.info(line);
  }
}
