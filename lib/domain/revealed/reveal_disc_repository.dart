// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/foundation.dart';

import 'reveal_disc.dart';

/// In-memory list of [RevealDisc]s mutated on every GPS fix (FOG-01).
///
/// Mirrors the parent MirkFall `RevealDiscRepository` shape so the POC
/// port-back is mechanical. POC scope per CONTEXT.md: in-memory only,
/// no persistence — every app launch starts with an empty list.
///
/// ## Concurrency
///
/// [snapshot] returns `List.unmodifiable(_discs)` — a defensive copy
/// (the underlying iterable IS the live list, but the wrapper rejects
/// mutation). Paint-time consumers (FogLayer.build) iterate the
/// snapshot, never the live list, defending against
/// ConcurrentModificationError when a GPS fix lands mid-paint
/// (CLAUDE.md: "Ne jamais muter une collection pendant son itération").
/// The next [append] mutates `_discs` and notifies; the next build picks
/// up a fresh snapshot.
///
/// ## Lifecycle
///
/// Owned by `MapScreenServices` — instantiated once at router /map
/// builder time, threaded into MapScreen + FogLayer via constructor
/// injection. `dispose()` is the inherited [ChangeNotifier.dispose].
class RevealDiscRepository extends ChangeNotifier {
  final List<RevealDisc> _discs = <RevealDisc>[];

  /// Immutable view of the disc list. Iterators returned here do NOT
  /// observe future [append] calls — taking a snapshot is the
  /// defensive-copy boundary.
  List<RevealDisc> snapshot() => List<RevealDisc>.unmodifiable(_discs);

  /// Appends [disc] to the live list and notifies listeners.
  void append(RevealDisc disc) {
    _discs.add(disc);
    notifyListeners();
  }
}
