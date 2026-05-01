// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';

/// FOG-01 — RevealDiscRepository semantics.
///
/// Wave 0 contract: these tests compile against the Plan 03-01 stub (which
/// returns empty snapshots and throws on append) and report RED until Plan
/// 03-02 ships the in-memory list + listener notification.
void main() {
  group('RevealDiscRepository (FOG-01)', () {
    test('snapshot() returns immutable view of current discs', () {
      final repo = RevealDiscRepository();
      expect(repo.snapshot(), isEmpty);

      // After an append, snapshot has one disc.
      repo.append(_disc(id: 'rvd_a'));
      expect(repo.snapshot(), hasLength(1));

      // snapshot() is unmodifiable — mutating throws.
      expect(() => repo.snapshot().add(_disc(id: 'rvd_b')), throwsUnsupportedError);
    });

    test('append notifies listeners exactly once per call', () {
      final repo = RevealDiscRepository();
      var calls = 0;
      repo.addListener(() => calls++);
      repo.append(_disc(id: 'rvd_a'));
      expect(calls, 1);
      repo.append(_disc(id: 'rvd_b'));
      expect(calls, 2);
    });

    test('snapshot() taken before append does not change after append (defensive copy semantics)', () {
      final repo = RevealDiscRepository();
      final snap0 = repo.snapshot();
      repo.append(_disc(id: 'rvd_a'));
      // The pre-append snapshot is an empty unmodifiable list — must NOT alias the live list.
      expect(snap0, isEmpty);
      expect(repo.snapshot(), hasLength(1));
    });
  });
}

RevealDisc _disc({required String id}) => RevealDisc(id: id, sessionId: 'poc', lat: 48.54, lon: 2.66, radiusMeters: 25.0, fixedAtUtc: DateTime.utc(2026, 5, 1));
