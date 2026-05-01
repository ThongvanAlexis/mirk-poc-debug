// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/foundation.dart';

import 'reveal_disc.dart';

/// In-memory list of [RevealDisc]s mutated on every GPS fix (FOG-01).
///
/// Notifies listeners on every successful [append]; consumers (FogLayer,
/// ShaderSanityScreen, future WispLayer) read via [snapshot] for paint-time
/// iteration. Wave 0 stub — Plan 03-02 ships the implementation.
class RevealDiscRepository extends ChangeNotifier {
  /// Returns an unmodifiable view of the current disc list. Stub returns an
  /// empty unmodifiable list — distinct identity per call so a caller that
  /// retains a snapshot does not observe future mutations through it.
  List<RevealDisc> snapshot() => List<RevealDisc>.unmodifiable(const <RevealDisc>[]);

  /// Appends [disc] to the list and notifies listeners. Stub throws — Plan
  /// 03-02 will store the disc and call [notifyListeners].
  void append(RevealDisc disc) {
    throw UnimplementedError('RevealDiscRepository.append — Plan 03-02');
  }
}
